import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/tts_provider.dart';
import '../../../core/services/incoming_call_service.dart';
import '../../../shared/widgets/avatar_image.dart';

/// 模拟来电全屏界面：响铃中显示接听/挂断；接通后显示通话计时与挂断。
/// 仅在 App 内模拟，不拨打运营商电话。
class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({super.key});

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  Timer? _tick;
  bool _spokeOpening = false;

  static const String _fallbackOpening =
      'Hey, I missed you. Is now a good time to talk?';

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    IncomingCallService.instance.session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    final session = IncomingCallService.instance.session.value;
    if (!mounted) return;
    if (session != null &&
        session.phase == CallPhase.active &&
        !_spokeOpening) {
      _spokeOpening = true;
      _speakOpening(session);
    }
    if (session == null || session.phase == CallPhase.ended) {
      unawaited(_stopSpeaking());
      Navigator.of(context).maybePop();
    }
  }

  void _speakOpening(CallSession session) {
    try {
      final tts = context.read<TtsProvider>();
      final line = (session.openingLine ?? '').trim();
      unawaited(tts.speak(line.isEmpty ? _fallbackOpening : line));
    } catch (_) {
      // TTS unavailable: fall back to a silent call.
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await context.read<TtsProvider>().stop();
    } catch (_) {
      // Ignore provider-not-yet-ready cases.
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    IncomingCallService.instance.session.removeListener(_onSessionChanged);
    unawaited(_stopSpeaking());
    super.dispose();
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _fallbackAvatar(String initial, double size) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Colors.white24,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size / 2.4,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = IncomingCallService.instance.session.value;
    if (session == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final active = session.phase == CallPhase.active;
    final elapsed = DateTime.now().difference(session.startedAt);
    final name = session.assistantName.trim();
    final initial = name.isEmpty ? '?' : name[0];
    final avatarSource = session.avatar ?? '';
    final isNetwork = avatarSource.startsWith('http');

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            if (avatarSource.isNotEmpty)
              AvatarImage(
                source: avatarSource,
                size: 120,
                isNetwork: isNetwork,
                fallback: _fallbackAvatar(initial, 120),
              )
            else
              _fallbackAvatar(initial, 120),
            const SizedBox(height: 24),
            Text(
              name.isEmpty ? 'Unknown' : name,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              active ? _format(elapsed) : 'Incoming call…',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
            const Spacer(),
            _actions(active, theme),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _actions(bool active, ThemeData theme) {
    final hangUp = _CallAction(
      icon: Icons.call_end,
      label: 'Decline',
      color: Colors.redAccent,
      onTap: () => IncomingCallService.instance.hangUp(),
    );

    if (active) {
      return Center(child: hangUp);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          hangUp,
          _CallAction(
            icon: Icons.phone,
            label: 'Accept',
            color: Colors.green,
            onTap: () => IncomingCallService.instance.answer(),
          ),
        ],
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white, size: 28),
          style: IconButton.styleFrom(
            backgroundColor: color,
            fixedSize: const Size(64, 64),
            shape: const CircleBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
