import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'haptics.dart';

/// 模拟来电的响铃封装：响铃期循环播放打包铃声并定时震动，
/// 接听 / 挂断后停止。铃声资源缺失或播放异常时静默降级，不崩溃。
final class CallRinger {
  CallRinger._();

  static final CallRinger instance = CallRinger._();

  static const String _ringtoneAsset = 'audio/ringtone.mp3';

  AudioPlayer? _player;
  Timer? _vibrateTimer;
  bool _ringing = false;

  /// 开始响铃。重复调用不会叠加播放器。
  Future<void> start() async {
    if (_ringing) return;
    _ringing = true;
    try {
      _player ??= AudioPlayer();
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.setSource(AssetSource(_ringtoneAsset));
      await _player!.resume();
    } catch (_) {
      // Bundled ringtone asset may be absent or the audio plugin unavailable;
      // stay silent instead of crashing the call flow.
    }
    _vibrateTimer?.cancel();
    _vibrateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      Haptics.medium();
    });
  }

  /// 停止响铃并解除震动节奏。
  Future<void> stop() async {
    _ringing = false;
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
    try {
      await _player?.stop();
    } catch (_) {
      // Ignore already-stopped or unavailable player.
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player?.dispose();
    _player = null;
  }
}
