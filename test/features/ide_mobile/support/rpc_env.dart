import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_rpc_client.dart';

import 'fakes.dart';

/// Trả lời một op: dữ liệu, hoặc `IdeFakeError` để trả lỗi có mã.
typedef IdeFakeHandler = Object? Function(String op, Map<String, Object?> args);

/// Không trả lời (để test tự gửi khung riêng, vd tải tệp).
const Object ideFakeSilent = Object();

final class IdeFakeError {
  const IdeFakeError(this.code, [this.message]);
  final String code;

  /// Câu `message` của IDE; mặc định lấy luôn mã lỗi.
  final String? message;
}

/// Ổ cắm giả tự trả lời op theo [handler].
final class AutoIdeSocket implements IdeSocket {
  AutoIdeSocket(
    this.handler,
    this.log, {
    List<String> ops = const ['ai.sessions'],
  }) : _inner = FakeIdeSocket(ops: ops);

  final FakeIdeSocket _inner;
  final IdeFakeHandler handler;
  final List<String> log;

  @override
  Stream<String> get messages => _inner.messages;

  @override
  Future<void> close() => _inner.close();

  void emit(Map<String, Object?> frame) => _inner.emit(frame);

  Iterable<Map<String, Object?>> sentOfType(String type) =>
      _inner.sentOfType(type);

  @override
  void send(String text) {
    _inner.send(text);
    final f = jsonDecode(text) as Map;
    if (f['type'] != 'op') return;
    final op = f['op'] as String;
    log.add(op);
    final args = Map<String, Object?>.from((f['args'] as Map?) ?? const {});
    final res = handler(op, args);
    if (identical(res, ideFakeSilent)) return;
    scheduleMicrotask(
      () => emit(
        res is IdeFakeError
            ? {
                'type': 'result',
                'req': f['req'],
                'ok': false,
                'error': {'code': res.code, 'message': res.message ?? res.code},
              }
            : {'type': 'result', 'req': f['req'], 'ok': true, 'data': res},
      ),
    );
  }
}

/// Máy IDE giả: kết nối thật + rpc thật, nhưng op do [handler] trả lời.
final class IdeRpcEnv {
  IdeRpcEnv(this.handler, {List<String>? ops, IdeStepHandler? step}) {
    connection = IdeConnection(
      openChannel: () async {
        final socket = AutoIdeSocket(
          handler,
          calls,
          ops: ops ?? const ['ai.sessions', 'jobs.list', 'jobs.tail'],
        );
        lastSocket = socket;
        return IdeChannel.connect(socket: socket, signAuth: fakeSignAuth);
      },
      backoff: const [Duration(milliseconds: 5)],
    );
    rpc = IdeRpcClient(
      connection,
      stepHandler: step,
      defaultTimeout: const Duration(seconds: 5),
    );
  }

  final IdeFakeHandler handler;
  final calls = <String>[];
  AutoIdeSocket? lastSocket;
  late final IdeConnection connection;
  late final IdeRpcClient rpc;

  Future<void> up() async {
    connection.start();
    await connection.statuses.firstWhere((s) => s.phase == IdeLinkPhase.ready);
  }

  Future<void> dispose() async {
    await rpc.dispose();
    await connection.dispose();
  }
}

/// Cho các tin giả (chạy ở vòng lặp thật) kịp tới nơi rồi vẽ lại.
Future<void> settle(WidgetTester tester, [int times = 3]) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
