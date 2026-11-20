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

  /// 停止录制。返回录好的片段；过短、文件不存在或为空时返回 `null`，
  /// 调用方不应把它挂进消息。
  Future<VoiceRecording?> stop() async {
    if (!_recording) return null;
    final path = await _recorder.stop();
    _recording = false;
    final startedAt = _startedAt;
    _startedAt = null;
    _path = null;

    if (path == null) return null;
    final file = File(path);
    final exists = await file.exists();
    final length = exists ? await file.length() : 0;
    final duration = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);

    // 过短或几乎为空：视为误触，直接丢弃文件。
    if (!exists ||
        length < 1024 ||
        duration < VoiceRecording.minUsefulDuration) {
      try {
        await file.delete();
      } catch (_) {
        // 文件可能已被清理，忽略。
      }
      return null;
    }

    return VoiceRecording(
      path: path,
      fileName: p.basename(path),
      mime: 'audio/mp4',
      duration: duration,
    );
  }

  /// 取消录制并删除已写出的临时文件（上滑取消 / 切会话 / 离开页面）。
  Future<void> cancel() async {
    if (!_recording) return;
    await _recorder.stop();
    _recording = false;
    _startedAt = null;
    final path = _path;
    _path = null;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {
        // 文件可能不存在，忽略。
      }
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
