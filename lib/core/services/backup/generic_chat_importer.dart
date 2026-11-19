import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../database/business_repository.dart';
import '../../database/chat_database_repository.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../models/message_part.dart';
import '../chat/chat_service.dart';

/// 通用聊天记录导入：识别多种陪聊 / 聊天 App 导出的 JSON 结构，把每条
/// 消息（角色、正文、时间）尽量完整还原成会话。
///
/// 支持的顶层形态：
/// - 数组：`[{role, content, timestamp}, ...]` → 单会话
/// - 会话对象数组：`{chats|sessions|conversations|history: [{title, messages: [...]}]}`
/// - 单会话对象：`{messages: [...]}`
///
/// 消息字段做了别名归一化：role/sender/who/author，content/text/message/body，
/// timestamp/time/createdAt/date/ts。时间支持 epoch 秒 / 毫秒与 ISO 字符串。
/// 不做附件还原（图片 / 文件），纯文本消息逐条落库，不截断条数。
class GenericChatImportResult {
  const GenericChatImportResult({
    required this.conversations,
    required this.messages,
  });

  final int conversations;
  final int messages;
}

class GenericChatImporter {
  GenericChatImporter._();

  static const _uuid = Uuid();

  static const _conversationKeys = <String>[
    'chats',
    'sessions',
    'conversations',
    'history',
    'dialogs',
    'threads',
    'messages',
  ];

  static const _messageKeys = <String>[
    'messages',
    'msgs',
    'messageList',
    'content',
    'history',
  ];

  /// 解析已解码的 JSON，返回可直接提交的批次。纯函数，便于单测。
  static List<ParsedChatImportBatch> parse(
    Object? raw, {
    String? fallbackTitle,
  }) {
    final conversations = <_RawConversation>[];

    if (raw is List) {
      final msgs = <Map<String, dynamic>>[];
      for (final entry in raw) {
        if (entry is Map) msgs.add(Map<String, dynamic>.from(entry));
      }
      if (msgs.isNotEmpty) {
        conversations.add(
          _RawConversation(
            title: fallbackTitle ?? 'Imported chat',
            messages: msgs,
          ),
        );
      }
    } else if (raw is Map<String, dynamic>) {
      Map<String, dynamic>? convMap;
      for (final key in _conversationKeys) {
        final value = raw[key];
        if (value is List && value.isNotEmpty) {
          convMap = raw;
          break;
        }
      }
      if (convMap != null) {
        for (final key in _conversationKeys) {
          final value = convMap[key];
          if (value is! List) continue;
          for (final entry in value) {
            if (entry is! Map) continue;
            final map = Map<String, dynamic>.from(entry);
            final nested = _firstMessageList(map);
            if (nested != null) {
              conversations.add(
                _RawConversation(
                  title:
                      _stringField(map, [
                        'title',
                        'name',
                        'topic',
                        'subject',
                      ]) ??
                      fallbackTitle ??
                      'Imported chat',
                  messages: nested,
                ),
              );
            } else if (_looksLikeMessage(map)) {
              // 顶层数组式条目直接作为消息。
              conversations.add(
                _RawConversation(
                  title: fallbackTitle ?? 'Imported chat',
                  messages: [map],
                ),
              );
            }
          }
        }
      } else {
        final nested = _firstMessageList(raw);
        if (nested != null) {
          conversations.add(
            _RawConversation(
              title: fallbackTitle ?? 'Imported chat',
              messages: nested,
            ),
          );
        }
      }
    }

    final batches = <ParsedChatImportBatch>[];
    for (var i = 0; i < conversations.length; i++) {
      final conv = conversations[i];
      final rawMessages = <ChatMessage>[];
      for (final rawMsg in conv.messages) {
        final role = _roleOf(rawMsg);
        final text = _textOf(rawMsg);
        if (role == null || text.isEmpty) continue;
        final timestamp =
            _timestampOf(rawMsg) ??
            DateTime.now().subtract(
              Duration(seconds: conversations.length - i),
            );
        rawMessages.add(
          ChatMessage(
            id: _uuid.v4(),
            role: role,
            parts: [TextPart(text)],
            timestamp: timestamp,
            conversationId: '',
          ),
        );
      }
      if (rawMessages.isEmpty) continue;
      final conversationId = _uuid.v4();
      final conversation = Conversation(
        id: conversationId,
        title: conv.title,
        createdAt: rawMessages.first.timestamp,
        updatedAt: rawMessages.last.timestamp,
      );
      final owned = rawMessages
          .map(
            (m) => ChatMessage(
              id: m.id,
              role: m.role,
              parts: m.parts,
              timestamp: m.timestamp,
              conversationId: conversationId,
            ),
          )
          .toList();
      batches.add((conversation: conversation, messages: owned));
    }
    return batches;
  }

  /// 读取文件、解析并提交到当前数据库。
  static Future<GenericChatImportResult> importFromGeneric({
    required File file,
    required BusinessRepository businessRepository,
    required ChatService chatService,
  }) async {
    final raw = jsonDecode(await file.readAsString());
    final batches = parse(raw, fallbackTitle: file.uri.pathSegments.last);
    if (batches.isEmpty) {
      return const GenericChatImportResult(conversations: 0, messages: 0);
    }
    await chatService.commitParsedImport(
      businessRepository: businessRepository,
      overwrite: false,
      conversationBatches: batches,
      messagesToAppend: const {},
      transformBusiness: (snapshot) => snapshot,
    );
    return GenericChatImportResult(
      conversations: batches.length,
      messages: batches.fold<int>(0, (sum, b) => sum + b.messages.length),
    );
  }

  static List<Map<String, dynamic>>? _firstMessageList(
    Map<dynamic, dynamic> map,
  ) {
    for (final key in _messageKeys) {
      final value = map[key];
      if (value is List) {
        final out = <Map<String, dynamic>>[];
        for (final entry in value) {
          if (entry is Map) out.add(Map<String, dynamic>.from(entry));
        }
        if (out.isNotEmpty) return out;
      }
    }
    return null;
  }

  static bool _looksLikeMessage(Map<dynamic, dynamic> map) =>
      _roleOf(map) != null && _textOf(map).isNotEmpty;

  static String? _roleOf(Map<dynamic, dynamic> map) {
    final raw = _stringField(map, ['role', 'sender', 'who', 'author', 'from']);
    if (raw == null) return null;
    final value = raw.toLowerCase().trim();
    const userRoles = {'user', 'me', 'you', 'human', '人类', '用户', '我', 'usr'};
    const assistantRoles = {
      'assistant',
      'bot',
      'ai',
      'ta',
      'character',
      '角色',
      'ai角色',
      'ass',
    };
    if (userRoles.contains(value)) return 'user';
    if (assistantRoles.contains(value)) return 'assistant';
    // 数值型角色：1/0 常见于部分导出；约定 1=用户，0/2=助手。
    if (value == '1') return 'user';
    if (value == '0' || value == '2') return 'assistant';
    return null;
  }

  static String _textOf(Map<dynamic, dynamic> map) {
    for (final key in [
      'content',
      'text',
      'message',
      'body',
      'contentText',
      'reply',
    ]) {
      final value = map[key];
      if (value == null) continue;
      if (value is String) return value.trim();
      if (value is List) {
        final parts = value
            .map(
              (e) => e is Map
                  ? _stringField(e, ['text', 'content', 'value'])
                  : null,
            )
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.isNotEmpty) return parts.join('\n').trim();
      }
    }
    return '';
  }

  static String? _stringField(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static DateTime? _timestampOf(Map<dynamic, dynamic> map) {
    for (final key in [
      'timestamp',
      'time',
      'createdAt',
      'date',
      'ts',
      'created_at',
      'sendTime',
    ]) {
      final value = map[key];
      if (value == null) continue;
      if (value is num) {
        final ms = value.abs() < 1e12 ? value * 1000 : value;
        return DateTime.fromMillisecondsSinceEpoch(ms.round());
      }
      if (value is String) {
        return DateTime.tryParse(value.trim());
      }
    }
    return null;
  }
}

class _RawConversation {
  const _RawConversation({required this.title, required this.messages});

  final String title;
  final List<Map<String, dynamic>> messages;
}
