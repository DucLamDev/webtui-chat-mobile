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
