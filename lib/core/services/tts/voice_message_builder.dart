import 'package:http/http.dart' as http;

import '../../models/message_part.dart';
import 'network_tts.dart';
import 'tts_audio_exporter.dart';

/// 把 TTS 合成音频组装成可入库的语音消息附件（[FilePart]）。
///
/// 入库由调用方通过 `ChatService.addMessage(role: assistant, parts: ...)`
/// 完成；这里只负责合成 + 附件映射，复用现有语音气泡播放器渲染。
final class VoiceMessageBuilder {
  const VoiceMessageBuilder._();

  /// 合成 [text] 并返回可入库的音频 [FilePart]；未配置语音服务、文本
  /// 为空或合成出空音频时返回 `null`。
  static Future<FilePart?> buildAudioPart({
    required TtsServiceOptions? options,
    required String text,
    http.Client? client,
  }) async {
    final result = await TtsAudioExporter.synthesizeToFile(
      options: options,
      text: text,
      client: client,
    );
    return result == null ? null : partFromResult(result);
  }

  /// 纯映射：导出结果 → 音频 [FilePart]，供单测覆盖。
  static FilePart partFromResult(TtsExportResult result) {
    return FilePart(uri: result.path, name: result.fileName, mime: result.mime);
  }
}
