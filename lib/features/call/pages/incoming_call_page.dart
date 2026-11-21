import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
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

  /// 直接播放已合成好的开场白音频文件。不依赖系统 TTS 引擎，避免部分
  /// 机型系统引擎缺失时完全静音。
  final AudioPlayer _clipPlayer = AudioPlayer();

  /// 当前这条无声音提示；非空时在通话页常驻展示，不再只是一闪而过。
  String? _noVoiceHint;

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
      final line = (session.openingLine ?? '').trim();
      final audioPath = session.openingAudioPath?.trim();
      if (line.isNotEmpty || (audioPath != null && audioPath.isNotEmpty)) {
        _spokeOpening = true;
        _speakOpening(line, audioPath);
      }
    }
    if (session == null || session.phase == CallPhase.ended) {
      unawaited(_stopSpeaking());
      Navigator.of(context).maybePop();
    }
  }

  /// 播报开场白：优先播已合成好的音频文件（最稳），文件不可用时退回
  /// 系统 TTS；两条路都不可用则给出明确提示，不再静默失败。
  void _speakOpening(String line, String? audioPath) {
    unawaited(_speakOpeningInternal(line, audioPath));
  }

  Future<void> _speakOpeningInternal(String line, String? audioPath) async {
    // 在第一个 await 之前取好 provider，避免跨异步拿 BuildContext。
    TtsProvider? tts;
    try {
      tts = context.read<TtsProvider>();
    } catch (_) {
      tts = null;
    }
    if (audioPath != null && audioPath.isNotEmpty) {
      try {
        final file = File(audioPath);
        if (await file.exists() && await file.length() > 0) {
          await _clipPlayer.stop();
          await _clipPlayer.play(DeviceFileSource(audioPath));
          return;
        }
      } catch (_) {
        // 文件播不了，继续走系统 TTS 兜底。
      }
    }
    if (line.isEmpty) {
      _notifyNoVoice('开场白为空，没有可播报的内容');
      return;
    }
    if (tts == null || !tts.isAvailable) {
      // speak() 在 provider 未初始化时是静默 return，这里显式判一下，
      // 避免"点了没声也不报错"。
      _notifyNoVoice('通话没有声音：还没配置语音服务。请到 设置 → 语音服务 → 新增（网络 TTS）填好接口和密钥');
      return;
    }
    try {
      await tts.speak(line);
    } catch (_) {
      _notifyNoVoice('通话没有声音：语音服务调用失败，请检查 设置 → 语音服务 的接口地址与密钥');
    }
  }

  void _notifyNoVoice(String message) {
    if (!mounted) return;
    setState(() => _noVoiceHint = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _stopSpeaking() async {
    // 先同步取好 provider，再进入异步清理，避免跨异步使用 context。
    TtsProvider? tts;
    try {
      tts = context.read<TtsProvider>();
    } catch (_) {
      tts = null;
    }
    try {
      await _clipPlayer.stop();
    } catch (_) {
      // Ignore player-not-ready cases.
    }
    try {
      await tts?.stop();
    } catch (_) {
      // Ignore provider-not-yet-ready cases.
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    IncomingCallService.instance.session.removeListener(_onSessionChanged);
    // dispose 里同步取好 provider，异步清理不再碰 context。
    TtsProvider? tts;
    try {
      tts = context.read<TtsProvider>();
    } catch (_) {
      tts = null;
    }
    unawaited(_speakClosingAndDispose(tts));
    super.dispose();
  }

  Future<void> _speakClosingAndDispose(TtsProvider? tts) async {
    try {
      await _clipPlayer.stop();
      await _clipPlayer.dispose();
    } catch (_) {
      // Ignore dispose races.
    }
    try {
      await tts?.stop();
    } catch (_) {
      // Ignore provider-not-yet-ready cases.
    }
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
    // 计时从接通时刻算起，响铃等待时间不计入通话时长。
    final answeredAt = session.answeredAt;
    final elapsed = answeredAt == null
        ? Duration.zero
        : DateTime.now().difference(answeredAt);
    final name = session.assistantName.trim();
    final initial = name.isEmpty ? '?' : name[0];
    final avatarSource = session.avatar ?? '';
    final isNetwork = avatarSource.startsWith('http');
    final openingLine = (session.openingLine ?? '').trim();

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
              name.isEmpty ? '未命名' : name,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              active ? _format(elapsed) : '来电中…',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
            if (_noVoiceHint != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      _noVoiceHint!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orangeAccent,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (openingLine.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  openingLine,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white60,
                    height: 1.4,
                  ),
                ),
              ),
            ],
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
