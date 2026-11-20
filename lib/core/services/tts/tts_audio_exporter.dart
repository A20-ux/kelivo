import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../utils/app_directories.dart';
import 'network_tts.dart';

/// 一次 TTS 合成落盘后的产物，可直接作为音频附件进入聊天消息，
/// 或交给来电/通话界面播放。
final class TtsExportResult {
  const TtsExportResult({
    required this.path,
    required this.fileName,
    required this.mime,
    required this.bytes,
  });

  /// 本地绝对路径。
  final String path;

  /// 展示用文件名。
  final String fileName;

  /// 音频 MIME，例如 `audio/mpeg` 或 `audio/wav`。
  final String mime;

  /// 音频字节数。
  final int bytes;
}

/// 把文本通过当前配置的网络语音 API 合成并写入本地文件。
///
/// 与 [TtsProvider] 的「即时播放」职责分开：这里只负责合成 + 落盘，
/// 产物可被语音消息气泡、模拟来电等多条链路复用。
final class TtsAudioExporter {
  const TtsAudioExporter._();

  static String _extension(String mime) {
    switch (mime) {
      case 'audio/wav':
      case 'audio/x-wav':
        return 'wav';
      case 'audio/ogg':
      case 'audio/ogg;codecs=opus':
        return 'ogg';
      case 'audio/opus':
        return 'opus';
      case 'audio/flac':
        return 'flac';
      case 'audio/mp4':
      case 'audio/m4a':
        return 'm4a';
      case 'audio/mpeg':
      default:
        return 'mp3';
    }
  }

  /// 合成 [text] 并落盘。未配置/未启用网络语音服务、文本为空或合成出
  /// 空音频时返回 `null`，由上层决定回退到纯文字或系统 TTS。
  static Future<TtsExportResult?> synthesizeToFile({
    required TtsServiceOptions? options,
    required String text,
    http.Client? client,
  }) async {
    final trimmed = text.trim();
    if (options == null || !options.enabled || trimmed.isEmpty) return null;

    final result = await NetworkTtsService.synthesize(
      options: options,
      text: trimmed,
      client: client,
    );
    if (result.bytes.isEmpty) return null;

    final dir = await AppDirectories.getUploadDirectory();
    await dir.create(recursive: true);

    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final base =
        'tts_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    var counter = 0;
    while (true) {
      final suffix = counter == 0 ? '' : '($counter)';
      final file = File(
        p.join(dir.path, '$base$suffix.${_extension(result.mime)}'),
      );
      try {
        await file.create(exclusive: true);
        await file.writeAsBytes(result.bytes, flush: true);
        return TtsExportResult(
          path: file.path,
          fileName: p.basename(file.path),
          mime: result.mime,
          bytes: result.bytes.length,
        );
      } on FileSystemException {
        if (!await file.exists()) rethrow;
        counter++;
      }
    }
  }
}
