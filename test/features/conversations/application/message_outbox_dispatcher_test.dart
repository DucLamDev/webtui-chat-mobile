import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_outbox_dispatcher.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_outbox_item.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/message_outbox_repository.dart';

void main() {
  test(
    'gửi mọi phòng theo thứ tự và không gửi trùng khi kích hoạt chồng',
    () async {
      final repo = _Repository([
        _item('2', 'a', 2),
        _item('1', 'a', 1),
        _item('3', 'b', 3),
      ]);
      final sent = <String>[];
      final dispatcher = _dispatcher(repo, (item) async {
        await Future<void>.delayed(Duration.zero);
        sent.add(item.clientMessageId);
        return Success(_message(item));
      });
      addTearDown(dispatcher.dispose);
      await Future.wait([
        dispatcher.drainWorkspace('ws'),
        dispatcher.drainWorkspace('ws'),
        dispatcher.drainChannel(workspaceId: 'ws', channelId: 'a'),
      ]);
      expect(sent, ['client-1', 'client-2', 'client-3']);
      expect(repo.items, isEmpty);
    },
  );

  test(
    'mất mạng giữ tin và chặn tin sau, có mạng gửi đủ không đổi mã',
    () async {
      final repo = _Repository([
        _item('1', 'a', 1),
        _item('2', 'a', 2),
        _item('3', 'b', 3),
      ]);
      var offline = true;
      final attempts = <String>[];
      final dispatcher = _dispatcher(repo, (item) async {
        attempts.add(item.clientMessageId);
        return offline ? _networkFailure : Success(_message(item));
      });
      addTearDown(dispatcher.dispose);
      await dispatcher.drainWorkspace('ws');
      expect(attempts, ['client-1']);
      expect(repo.items.length, 3);
      offline = false;
      await dispatcher.drainWorkspace('ws');
      expect(attempts, ['client-1', 'client-1', 'client-2', 'client-3']);
      expect(repo.items, isEmpty);
    },
  );

  test('lỗi quyền một phòng không chặn phòng khác', () async {
    final repo = _Repository([_item('1', 'a', 1), _item('2', 'b', 2)]);
    final dispatcher = _dispatcher(
      repo,
      (item) async => item.channelId == 'a'
          ? const FailureResult(
              Failure(kind: FailureKind.forbidden, message: 'Không có quyền.'),
            )
          : Success(_message(item)),
    );
    addTearDown(dispatcher.dispose);
    await dispatcher.drainWorkspace('ws');
    expect(repo.items.map((item) => item.id), ['1']);
    expect(repo.items.single.status, MessageOutboxStatus.failed);
  });

  test('đổi máy chủ không gửi tin và không xoá hàng chờ', () async {
    final repo = _Repository([_item('1', 'a', 1)])..allowed = false;
    var sent = 0;
    final dispatcher = _dispatcher(repo, (item) async {
      sent++;
      return Success(_message(item));
    });
    addTearDown(dispatcher.dispose);
    await dispatcher.drainWorkspace('ws');
    expect(sent, 0);
    expect(repo.items.length, 1);
  });

  test('vào nền khi gửi chưa xong không tạo lại hẹn giờ gửi', () async {
    final repo = _Repository([_item('1', 'a', 1)]);
    final sending = Completer<void>();
    final response = Completer<Result<ChatMessage>>();
    var attempts = 0;
    final dispatcher = _dispatcher(repo, (item) {
      attempts++;
      if (!sending.isCompleted) sending.complete();
      return response.future;
    }, retry: const [Duration(milliseconds: 1)]);
    addTearDown(dispatcher.dispose);
    final run = dispatcher.drainWorkspace('ws');
    await sending.future;
    dispatcher.pauseAutoRetry();
    response.complete(_networkFailure);
    await run;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(attempts, 1);
  });

  test('huỷ bộ gửi trong lúc đọc quyền không phát yêu cầu mạng', () async {
    final repo = _Repository([_item('1', 'a', 1)]);
    final entered = Completer<void>();
    final gate = Completer<bool>();
    repo.permission = () {
      entered.complete();
      return gate.future;
    };
    var sent = 0;
    final dispatcher = _dispatcher(repo, (item) async {
      sent++;
      return Success(_message(item));
    });
    final run = dispatcher.drainWorkspace('ws');
    await entered.future;
    dispatcher.dispose();
    gate.complete(true);
    await run;
    expect(sent, 0);
    expect(repo.items.length, 1);
  });

  group('tin có tệp còn đang tải', () {
    test('không chặn tin chữ tạo sau, tải xong gửi đúng một lần', () async {
      final repo = _Repository([
        _videoItem('1', 'a', 1, ['u1', 'u2']),
        _item('2', 'a', 2),
      ]);
      final gate = Completer<void>();
      final sent = <String>[];
      final attached = <String>[];
      final dispatcher = _uploadDispatcher(
        repo,
        send: (item) async {
          sent.add(item.clientMessageId);
          return Success(_message(item));
        },
        attach: (item, message, attachment) async {
          attached.add('${attachment.fileId}@${attachment.sortOrder}');
          return Success(_attachment(attachment));
        },
        upload: (item, upload, onProgress) async {
          onProgress(0.5);
          await gate.future;
          onProgress(1);
          return Success(_file('file-${upload.clientAttachmentId}'));
        },
      );
      addTearDown(dispatcher.dispose);
      final updates = <MessageOutboxDispatchUpdate>[];
      final subscription = dispatcher.updates.listen(updates.add);
      addTearDown(subscription.cancel);

      await dispatcher.drainChannel(workspaceId: 'ws', channelId: 'a');
      // Tin chữ gửi trước, video vẫn đang tải.
      expect(sent, ['client-2']);
      expect(repo.items.map((i) => i.id), ['1']);

      gate.complete();
      await _eventually(() => repo.items.isEmpty);

      expect(sent, ['client-2', 'client-1']);
      expect(attached, ['file-u1@0', 'file-u2@1']);
      final uploading = updates.where(
        (u) => u.phase == MessageOutboxDispatchPhase.uploading,
      );
      expect(uploading, isNotEmpty);
      expect(uploading.every((u) => u.progress != null), isTrue);
      expect(uploading.last.progress, 1);
      // Gọi lại sau khi xong không gửi trùng.
      await dispatcher.drainWorkspace('ws');
      expect(sent, ['client-2', 'client-1']);
    });

    test('lỗi tải giữ tin failed cùng tệp, thử lại tải phần còn lại', () async {
      final repo = _Repository([
        _videoItem('1', 'a', 1, ['u1', 'u2']),
      ]);
      final calls = <String>[];
      var failSecond = true;
      final sent = <String>[];
      final dispatcher = _uploadDispatcher(
        repo,
        send: (item) async {
          sent.add(item.clientMessageId);
          return Success(_message(item));
        },
        attach: (item, message, attachment) async =>
            Success(_attachment(attachment)),
        upload: (item, upload, onProgress) async {
          calls.add(upload.clientAttachmentId);
          if (upload.clientAttachmentId == 'u2' && failSecond) {
            return const FailureResult(
              Failure(kind: FailureKind.validation, message: 'Tệp quá lớn.'),
            );
          }
          return Success(_file('file-${upload.clientAttachmentId}'));
        },
      );
      addTearDown(dispatcher.dispose);

      await dispatcher.drainChannel(workspaceId: 'ws', channelId: 'a');
      await _eventually(
        () => repo.items.single.status == MessageOutboxStatus.failed,
      );
      expect(repo.items.single.lastError, 'Tệp quá lớn.');
      expect(
        repo.items.single.pendingUploads.map((u) => u.clientAttachmentId),
        ['u2'],
      );
      expect(repo.items.single.attachments.map((a) => a.fileId), ['file-u1']);
      expect(sent, isEmpty);

      failSecond = false;
      calls.clear();
      await dispatcher.drainChannel(workspaceId: 'ws', channelId: 'a');
      await _eventually(() => repo.items.isEmpty);
      // Tệp u1 đã tải xong được lưu nên không tải lại.
      expect(calls, ['u2']);
      expect(sent, ['client-1']);
    });

    test('không có bộ tải thì báo lỗi và giữ tin', () async {
      final repo = _Repository([
        _videoItem('1', 'a', 1, ['u1']),
      ]);
      final dispatcher = _dispatcher(
        repo,
        (item) async => Success(_message(item)),
      );
      addTearDown(dispatcher.dispose);
      await dispatcher.drainChannel(workspaceId: 'ws', channelId: 'a');
      await _eventually(
        () => repo.items.single.status == MessageOutboxStatus.failed,
      );
      expect(repo.items.single.lastError, 'Không tải được tệp đính kèm.');
      expect(repo.items.single.hasPendingUploads, isTrue);
    });

    test('tin bị xoá khỏi hàng chờ trong lúc tải thì không gửi', () async {
      final repo = _Repository([
        _videoItem('1', 'a', 1, ['u1']),
      ]);
      final gate = Completer<void>();
      var sent = 0;
      final dispatcher = _uploadDispatcher(
        repo,
        send: (item) async {
          sent++;
          return Success(_message(item));
        },
        attach: (item, message, attachment) async =>
            Success(_attachment(attachment)),
        upload: (item, upload, onProgress) async {
          await gate.future;
          return Success(_file('file-u1'));
        },
      );
      addTearDown(dispatcher.dispose);
      await dispatcher.drainChannel(workspaceId: 'ws', channelId: 'a');
      repo.items.clear();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sent, 0);
      expect(repo.items, isEmpty);
    });

    test('đổi máy chủ thì không tải và không gửi', () async {
      final repo = _Repository([
        _videoItem('1', 'a', 1, ['u1']),
      ])..allowed = false;
      var uploads = 0;
      var sent = 0;
      final dispatcher = _uploadDispatcher(
        repo,
        send: (item) async {
          sent++;
          return Success(_message(item));
        },
        attach: (item, message, attachment) async =>
            Success(_attachment(attachment)),
        upload: (item, upload, onProgress) async {
          uploads++;
          return Success(_file('file-u1'));
        },
      );
      addTearDown(dispatcher.dispose);
      await dispatcher.drainChannel(workspaceId: 'ws', channelId: 'a');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(uploads, 0);
      expect(sent, 0);
      expect(repo.items.single.hasPendingUploads, isTrue);
    });
  });
}

const _networkFailure = FailureResult<ChatMessage>(
  Failure(kind: FailureKind.network, message: 'Mất kết nối mạng.'),
);

MessageOutboxDispatcher _dispatcher(
  _Repository repo,
  SendOutboxMessage send, {
  List<Duration> retry = const [],
}) => MessageOutboxDispatcher(
  repository: repo,
  sendMessage: send,
  autoRetryDelays: retry,
  attachFile: (item, message, attachment) async =>
      throw StateError('Không có tệp'),
);

MessageOutboxItem _item(String id, String channel, int second) =>
    MessageOutboxItem(
      id: id,
      instanceScopeId: 'instance',
      workspaceId: 'ws',
      channelId: channel,
      clientMessageId: 'client-$id',
      body: 'Tin $id',
      createdAt: DateTime.utc(2026, 11, 10, 0, 0, second),
      updatedAt: DateTime.utc(2026, 11, 10),
    );

ChatMessage _message(MessageOutboxItem item) => ChatMessage(
  id: 'server-${item.id}',
  workspaceId: item.workspaceId,
  channelId: item.channelId,
  kind: 'text',
  body: item.body,
  createdAt: item.createdAt,
);

final class _Repository implements MessageOutboxRepository {
  _Repository(this.items);
  final List<MessageOutboxItem> items;
  bool allowed = true;
  Future<bool> Function()? permission;
  @override
  Future<bool> canDispatch(MessageOutboxItem item) async =>
      permission == null ? allowed : await permission!();
  @override
  Future<List<MessageOutboxItem>> list({
    required String workspaceId,
    required String channelId,
  }) async => items
      .where((i) => i.workspaceId == workspaceId && i.channelId == channelId)
      .toList();
  @override
  Future<List<MessageOutboxItem>> listWorkspace({
    required String workspaceId,
  }) async => items.where((i) => i.workspaceId == workspaceId).toList();
  @override
  Future<void> upsert(MessageOutboxItem item) async {
    final index = items.indexWhere((i) => i.id == item.id);
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }
  }

  @override
  Future<void> delete({
    required String workspaceId,
    required String channelId,
    required String itemId,
  }) async => items.removeWhere(
    (i) =>
        i.workspaceId == workspaceId &&
        i.channelId == channelId &&
        i.id == itemId,
  );
  @override
  Future<void> clearWorkspace({required String workspaceId}) async =>
      items.removeWhere((i) => i.workspaceId == workspaceId);
}

MessageOutboxDispatcher _uploadDispatcher(
  _Repository repo, {
  required SendOutboxMessage send,
  required AttachOutboxFile attach,
  required UploadOutboxFile upload,
}) => MessageOutboxDispatcher(
  repository: repo,
  sendMessage: send,
  attachFile: attach,
  uploadFile: upload,
  autoRetryDelays: const [],
);

MessageOutboxItem _videoItem(
  String id,
  String channel,
  int second,
  List<String> uploadIds,
) => MessageOutboxItem(
  id: id,
  instanceScopeId: 'instance',
  workspaceId: 'ws',
  channelId: channel,
  clientMessageId: 'client-$id',
  body: 'Video $id',
  createdAt: DateTime.utc(2026, 11, 10, 0, 0, second),
  updatedAt: DateTime.utc(2026, 11, 10),
  pendingUploads: [
    for (var index = 0; index < uploadIds.length; index += 1)
      MessageOutboxPendingUpload(
        clientAttachmentId: uploadIds[index],
        localPath: '/device/${uploadIds[index]}.mp4',
        fileName: '${uploadIds[index]}.mp4',
        mimeType: 'video/mp4',
        byteSize: 1000,
        kind: MessageAttachmentKind.video,
        sortOrder: index,
      ),
  ],
);

UploadedMessageFile _file(String id) => UploadedMessageFile(
  id: id,
  name: '$id.mp4',
  mimeType: 'video/mp4',
  byteSize: 1000,
  downloadPath: '/files/$id',
  createdAt: DateTime.utc(2026, 11, 10),
);

MessageAttachment _attachment(MessageOutboxAttachment attachment) =>
    MessageAttachment(
      id: 'att-${attachment.fileId}',
      workspaceId: 'ws',
      messageId: 'm',
      fileId: attachment.fileId,
      sortOrder: attachment.sortOrder,
      createdAt: DateTime.utc(2026, 11, 10),
      file: _file(attachment.fileId),
    );

Future<void> _eventually(bool Function() condition) async {
  for (var i = 0; i < 200; i += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'Điều kiện không đạt kịp lúc.');
}
