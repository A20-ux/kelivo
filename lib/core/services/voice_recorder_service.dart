import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// 一条录好的语音片段，等待作为音频附件进入聊天消息。
final class VoiceRecording {
  const VoiceRecording({
    required this.path,
    required this.fileName,
    required this.mime,
    required this.duration,
  });

  /// 本地绝对路径。
  final String path;

  /// 展示用文件名。
  final String fileName;

  /// 音频 MIME，AAC/M4A 为 `audio/mp4`。
  final String mime;

  /// 录音时长（从按下到松开）。
  final Duration duration;

  /// 微信式语音的最短有效时长，短于此视为误触并丢弃。
  static const minUsefulDuration = Duration(milliseconds: 800);

  bool get isTooShort => duration < minUsefulDuration;

  /// 秒数，用于气泡展示。
  int get durationSeconds => duration.inSeconds;
}

/// [VoiceRecorderService.stop] 的分类结果，便于调用方区分
/// 「太短 / 空文件 / 失败 / 成功」，而不是统一静默丢弃。
final class WxStopResult {
  const WxStopResult({this.recording, required this.reason});

  final VoiceRecording? recording;

  /// `ok` | `tooShort` | `empty` | `failed`。
  final String reason;

  bool get isOk => recording != null;
}

/// 微信式按住录音：按住开始、松开发送、上滑取消。底层走 `record` 插件，
/// 输出 AAC/M4A。纯 Dart 封装，输入栏持有一个实例即可。
final class VoiceRecorderService {
  VoiceRecorderService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  bool _recording = false;
  String? _path;
  DateTime? _startedAt;

  bool get isRecording => _recording;

  /// 申请麦克风权限，返回是否可用。
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// 开始向 [path] 录制 AAC/M4A。调用前应先确认权限。
  ///
  /// 抛出 [RecordPermissionException] 或平台错误表示无法启动。
  Future<void> start({required String path}) async {
    if (_recording) return;
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        numChannels: 1,
        sampleRate: 44100,
        bitRate: 96000,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _recording = true;
    _path = path;
    _startedAt = DateTime.now();
  }

  /// 停止录制。返回分类结果：成功带 [VoiceRecording]；过短、文件为空或
  /// 平台失败时 [WxStopResult.recording] 为 `null`，并给出 `reason`。
  Future<WxStopResult> stop() async {
    if (!_recording) return const WxStopResult(reason: 'failed');

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      _recording = false;
      _startedAt = null;
      _path = null;
      return const WxStopResult(reason: 'failed');
    }

    _recording = false;
    final startedAt = _startedAt;
    _startedAt = null;
    _path = null;

    if (path == null) return const WxStopResult(reason: 'empty');

    final file = File(path);
    bool exists;
    var length = 0;
    try {
      exists = await file.exists();
      if (exists) length = await file.length();
    } catch (_) {
      exists = false;
    }
    final duration = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);

    // 文件不存在或几乎为空：视为无效录制，清理后丢弃。
    if (!exists || length < 1024) {
      await _safeDelete(file);
      return const WxStopResult(reason: 'empty');
    }

    // 过短：视为误触，清理后丢弃。
    if (duration < VoiceRecording.minUsefulDuration) {
      await _safeDelete(file);
      return const WxStopResult(reason: 'tooShort');
    }

    return WxStopResult(
      recording: VoiceRecording(
        path: path,
        fileName: p.basename(path),
        mime: 'audio/mp4',
        duration: duration,
      ),
      reason: 'ok',
    );
  }

  /// 取消录制并删除已写出的临时文件（上滑取消 / 点叉 / 切会话 / 离开页面）。
  /// 内部全部容错，不向调用方抛异常。
  Future<void> cancel() async {
    if (!_recording) return;
    try {
      await _recorder.stop();
    } catch (_) {
      // 平台侧可能已停止，忽略。
    }
    _recording = false;
    _startedAt = null;
    final path = _path;
    _path = null;
    if (path != null) await _safeDelete(File(path));
  }

  Future<void> _safeDelete(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // 文件可能已被清理，忽略。
    }
  }

  /// 释放底层录音器。
  Future<void> dispose() async {
    if (_recording) {
      await cancel();
    }
    await _recorder.dispose();
  }
}
