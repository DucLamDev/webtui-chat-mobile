import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/application/message_attachment_memo.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';

MessageAttachment _attachment(String id) => MessageAttachment(
  id: id,
  workspaceId: 'ws-1',
  messageId: 'm-1',
  fileId: id,
  createdAt: DateTime.utc(2026, 11, 18),
  file: UploadedMessageFile(
    id: id,
    name: '$id.jpg',
    mimeType: 'image/jpeg',
    byteSize: 10,
    downloadPath: '/api/v1/workspaces/ws-1/files/$id/download',
    createdAt: DateTime.utc(2026, 11, 18),
  ),
);

String? _key(String? user, String message) => MessageAttachmentMemo.keyFor(
  userId: user,
  workspaceId: 'ws-1',
  channelId: 'ch-1',
  messageId: message,
);

void main() {
  hydratorTests();

  test('nhớ tệp của tin theo người dùng', () {
    final memo = MessageAttachmentMemo();
    memo.write(_key('user-a', 'm-1'), [_attachment('f-1')]);

    expect(memo.read(_key('user-a', 'm-1'))?.single.fileId, 'f-1');
    expect(memo.read(_key('user-b', 'm-1')), isNull);
    expect(
      _key(null, 'm-1'),
      isNull,
      reason: 'chưa biết người dùng thì không nhớ',
    );
    expect(_key(' ', 'm-1'), isNull);
  });

  test('danh sách rỗng không được nhớ (tin có thể còn đang gắn tệp)', () {
    final memo = MessageAttachmentMemo();
    memo.write(_key('user-a', 'm-1'), const []);
    expect(memo.read(_key('user-a', 'm-1')), isNull);
  });

  test('máy chủ báo gắn thêm tệp thì bản mới ghi đè', () {
    final memo = MessageAttachmentMemo();
    memo.write(_key('user-a', 'm-1'), [_attachment('f-1')]);
    memo.write(_key('user-a', 'm-1'), [_attachment('f-1'), _attachment('f-2')]);
    expect(memo.read(_key('user-a', 'm-1'))?.map((a) => a.fileId), [
      'f-1',
      'f-2',
    ]);
  });

  test('vượt giới hạn thì bỏ tin lâu không dùng nhất', () {
    final memo = MessageAttachmentMemo(maxEntries: 2);
    memo.write(_key('user-a', 'm-1'), [_attachment('f-1')]);
    memo.write(_key('user-a', 'm-2'), [_attachment('f-2')]);
    // Vừa đọc m-1 nên m-2 thành cũ nhất.
    expect(memo.read(_key('user-a', 'm-1')), isNotNull);
    memo.write(_key('user-a', 'm-3'), [_attachment('f-3')]);

    expect(memo.read(_key('user-a', 'm-2')), isNull);
    expect(memo.read(_key('user-a', 'm-1')), isNotNull);
    expect(memo.read(_key('user-a', 'm-3')), isNotNull);
  });
}

ChatMessage _message(String id) => ChatMessage(
  id: id,
  workspaceId: 'ws-1',
  channelId: 'ch-1',
  kind: 'file',
  body: '',
  createdAt: DateTime.utc(2026, 11, 18),
);

Future<List<String>> _hydratedIds(
  MessageAttachmentHydrator hydrator,
  List<ChatMessage> targets, {
  required String? userId,
}) async {
  final ids = <String>[];
  await for (final batch in hydrator.hydrate(targets, userId: userId)) {
    ids.addAll(batch.keys);
  }
  return ids;
}

void hydratorTests() {
  test(
    'mở lại phòng chat không hỏi lại máy chủ tệp của tin đã biết (log 17/11: 18 lần một tin)',
    () async {
      final memo = MessageAttachmentMemo();
      final fetched = <String>[];
      final hydrator = MessageAttachmentHydrator(
        memo: memo,
        fetch: (message) async {
          fetched.add(message.id);
          return [_attachment('file-${message.id}')];
        },
      );
      final targets = [_message('m-1'), _message('m-2')];

      expect(await _hydratedIds(hydrator, targets, userId: 'user-a'), [
        'm-1',
        'm-2',
      ]);
      // Mở lại phòng (bộ điều khiển mới, cùng bộ nhớ): gắn ngay, không hỏi máy chủ.
      for (var reopen = 0; reopen < 17; reopen++) {
        expect(await _hydratedIds(hydrator, targets, userId: 'user-a'), [
          'm-1',
          'm-2',
        ]);
      }
      expect(fetched, ['m-1', 'm-2']);

      // Tài khoản khác trên máy: hỏi lại máy chủ.
      await _hydratedIds(hydrator, targets, userId: 'user-b');
      expect(fetched, ['m-1', 'm-2', 'm-1', 'm-2']);
    },
  );

  test(
    'tin lỗi / chưa có tệp thì lần sau hỏi lại; màn đã đóng thì ngừng hỏi',
    () async {
      final memo = MessageAttachmentMemo();
      var calls = 0;
      final hydrator = MessageAttachmentHydrator(
        memo: memo,
        fetch: (message) async {
          calls += 1;
          return message.id == 'm-err' ? null : const <MessageAttachment>[];
        },
      );
      await _hydratedIds(hydrator, [
        _message('m-err'),
        _message('m-empty'),
      ], userId: 'u');
      await _hydratedIds(hydrator, [
        _message('m-err'),
        _message('m-empty'),
      ], userId: 'u');
      expect(calls, 4);

      var active = true;
      calls = 0;
      final stopping = MessageAttachmentHydrator(
        fetch: (message) async {
          calls += 1;
          active = false;
          return [_attachment('f')];
        },
      );
      final batches = await stopping
          .hydrate(
            [_message('a'), _message('b'), _message('c')],
            userId: 'u',
            isActive: () => active,
          )
          .toList();
      expect(batches, isEmpty);
      expect(calls, 1);
    },
  );
}
