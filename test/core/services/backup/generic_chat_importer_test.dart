import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/backup/generic_chat_importer.dart';

void main() {
  test('flat array of messages becomes one conversation', () {
    final raw = [
      {'role': 'user', 'content': '你好', 'timestamp': 1700000000000},
      {'role': 'assistant', 'text': '你好呀', 'timestamp': 1700000001000},
    ];
    final batches = GenericChatImporter.parse(raw, fallbackTitle: '平面对话');

    expect(batches, hasLength(1));
    expect(batches.first.messages, hasLength(2));
    expect(batches.first.messages.first.role, 'user');
    expect(batches.first.messages[1].role, 'assistant');
    expect(batches.first.messages[1].content, '你好呀');
  });

  test('chats array with nested messages is split per conversation', () {
    final raw = {
      'chats': [
        {
          'title': '角色 A',
          'messages': [
            {'sender': 'user', 'text': '在吗'},
            {'sender': 'assistant', 'text': '在的'},
          ],
        },
        {
          'title': '角色 B',
          'messages': [
            {'sender': 'me', 'text': '喂'},
            {'sender': 'bot', 'text': '嗯'},
          ],
        },
      ],
    };
    final batches = GenericChatImporter.parse(raw);

    expect(batches, hasLength(2));
    expect(batches[0].conversation.title, '角色 A');
    expect(batches[1].conversation.title, '角色 B');
    expect(batches.fold<int>(0, (s, b) => s + b.messages.length), 4);
  });

  test('Operit-style sessions/msgs with sender+text', () {
    final raw = {
      'sessions': [
        {
          'name': 'Operit 会话',
          'msgs': [
            {'sender': 'me', 'text': '去睡'},
            {'sender': 'character', 'text': '好'},
          ],
        },
      ],
    };
    final batches = GenericChatImporter.parse(raw);

    expect(batches, hasLength(1));
    final msgs = batches.first.messages;
    expect(msgs.first.role, 'user');
    expect(msgs.last.role, 'assistant');
    expect(msgs.first.content, '去睡');
  });

  test('content as text part list is joined', () {
    final raw = [
      {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': '第一行'},
          {'type': 'text', 'text': '第二行'},
        ],
      },
    ];
    final batches = GenericChatImporter.parse(raw);
    expect(batches.first.messages.single.content, '第一行\n第二行');
  });

  test('timestamps accept epoch seconds, millis and ISO', () {
    final raw = [
      {'role': 'user', 'content': 's', 'timestamp': 1700000000},
      {'role': 'assistant', 'content': 'm', 'timestamp': 1700000001000},
      {'role': 'user', 'content': 'i', 'createdAt': '2024-01-01T10:00:00.000'},
    ];
    final batches = GenericChatImporter.parse(raw);
    final msgs = batches.first.messages;
    expect(msgs[0].timestamp.millisecondsSinceEpoch, 1700000000000);
    expect(msgs[1].timestamp.millisecondsSinceEpoch, 1700000001000);
    expect(msgs[2].timestamp.year, 2024);
  });

  test('empty text and unknown role are skipped', () {
    final raw = [
      {'role': 'user', 'content': '   '},
      {'role': 'system', 'content': '不该出现'},
      {'role': 'assistant', 'text': '正常回复'},
    ];
    final batches = GenericChatImporter.parse(raw);
    expect(batches.first.messages, hasLength(1));
    expect(batches.first.messages.single.content, '正常回复');
  });
}
