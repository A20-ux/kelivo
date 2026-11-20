import '../../models/assistant.dart';
import '../../models/chat_message.dart';
import '../chat/chat_service.dart';
import 'network_tts.dart';
import 'voice_message_builder.dart';

/// 把一段 AI 文本经语音 API 合成，并作为 assistant 语音消息入库。
///
/// 合成失败、未配置语音服务或文本为空时返回 `null`，调用方保留
/// 原有纯文字消息；入库后的语音附件复用现有语音气泡播放器。
final class VoiceMessageService {
  const VoiceMessageService._();

  /// 合成 [text] 并存为一条 assistant 语音消息。
  ///
  /// [options] 为当前选中并启用的网络语音服务配置；为空或未启用时
  /// 直接返回 `null`。
  static Future<ChatMessage?> saveAssistantClip({
    required ChatService chat,
    required String conversationId,
    required String text,
    required TtsServiceOptions? options,
    Assistant? assistant,
  }) async {
    final part = await VoiceMessageBuilder.buildAudioPart(
      options: options,
      text: text,
    );
    if (part == null) return null;

    return chat.addMessage(
      conversationId: conversationId,
      role: 'assistant',
      parts: [part],
      modelId: assistant?.chatModelId,
      providerId: assistant?.chatModelProvider,
    );
  }
}
