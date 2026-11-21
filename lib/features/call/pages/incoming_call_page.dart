import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

  /// 直连系统朗读引擎的兜底通道：绕过 TtsProvider 的初始化状态，
  /// 只要系统里有可用引擎就能发声。
  FlutterTts? _rawTts;

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
      final voiceError = session.openingVoiceError?.trim();
      if (line.isNotEmpty || (audioPath != null && audioPath.isNotEmpty)) {
        _spokeOpening = true;
        _speakOpening(line, audioPath);
      } else if (voiceError != null && voiceError.isNotEmpty) {
        _spokeOpening = true;
        _notifyNoVoice(voiceError);
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
    // 第一级：播已合成好的本地音频文件（最稳，不依赖任何引擎）。
    if (audioPath != null && audioPath.isNotEmpty) {
      try {
        final file = File(audioPath);
        if (await file.exists() && await file.length() > 0) {
          await _clipPlayer.stop();
          await _clipPlayer.play(DeviceFileSource(audioPath));
          return;
        }
      } catch (_) {
        // 文件播不了，继续下一级。
      }
    }
    if (line.isEmpty) {
      _notifyNoVoice('开场白为空，没有可播报的内容');
      return;
    }
    // 第二级：走 TtsProvider（已配置网络语音服务时用它）。
    if (tts != null && tts.isAvailable) {
      try {
        await tts.speak(line);
        if (tts.isSpeaking) return;
      } catch (_) {
        // 继续下一级。
      }
    }
    // 第三级：直连系统朗读引擎，绕过 provider 初始化，强制中文。
    final ok = await _speakWithSystemEngine(line);
    if (!ok) {
      _notifyNoVoice(
        '通话仍然没有声音：本机没有可用的中文朗读引擎，也没有配置网络语音服务。'
        '请到 设置 → 语音服务 新增一项网络 TTS（接口地址填你对话服务商的地址即可）',
      );
    }
  }

  /// 直接调用系统朗读引擎发声；返回是否真的开始朗读。
  Future<bool> _speakWithSystemEngine(String line) async {
    try {
      final engine = _rawTts ??= FlutterTts();
      await engine.setLanguage('zh-CN');
      await engine.setSpeechRate(0.5);
      await engine.setVolume(1.0);
      await engine.awaitSpeakCompletion(false);
      await engine.stop();
      await engine.speak(line);
      return true;
    } catch (_) {
      return false;
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
      await _rawTts?.stop();
    } catch (_) {
      // Ignore engine-not-ready cases.
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
