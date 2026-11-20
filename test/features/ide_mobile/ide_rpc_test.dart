import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_rpc_client.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_errors.dart';

import 'support/fakes.dart';

final class _Env {
  _Env({this.step}) {
    connection = IdeConnection(
      openChannel: () async {
        final socket = FakeIdeSocket(ops: const ['ai.sessions', 'files.get']);
        sockets.add(socket);
        return IdeChannel.connect(socket: socket, signAuth: fakeSignAuth);
      },
      backoff: const [Duration(milliseconds: 5)],
    );
    rpc = IdeRpcClient(
      connection,
      stepHandler: step,
      defaultTimeout: const Duration(milliseconds: 300),
      chunkSize: 4,
    );
  }

  final IdeStepHandler? step;
  final sockets = <FakeIdeSocket>[];
  late final IdeConnection connection;
  late final IdeRpcClient rpc;
  FakeIdeSocket get socket => sockets.last;

  Future<void> up() async {
    connection.start();
    await connection.statuses.firstWhere((s) => s.phase == IdeLinkPhase.ready);
  }

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));
}

class _Sink implements IdeFileSink {
  final bytes = <int>[];
  bool? ok;
  @override
  void onMeta(Map<String, Object?> meta) {}
  @override
  Future<void> add(List<int> b) async => bytes.addAll(b);
  @override
  Future<void> close({required bool ok}) async => this.ok = ok;
}

void main() {
  late _Env env;
  tearDown(() async {
    await env.rpc.dispose();
    await env.connection.dispose();
  });

  test('bắt tay rồi chọn kiểu rpc, op và result', () async {
    env = _Env();
    await env.up();
    expect(env.connection.ready!.hasOp('ai.sessions'), isTrue);
    expect(env.socket.sentOfType('auth').single['sig'], 'sig');
    expect(env.socket.sentOfType('rpc'), hasLength(1));
    final call = env.rpc.call('ai.sessions', {'a': 1});
    await env.pump();
    final op = env.socket.sentOfType('op').single;
    expect(op['op'], 'ai.sessions');
    env.socket.emit({
      'type': 'result',
      'req': op['req'],
      'ok': true,
      'data': {'items': []},
    });
    expect(await call, {'items': []});
  });

  test('lỗi có mã được ném đúng kiểu', () async {
    env = _Env();
    await env.up();
    final call = env.rpc.call('ai.sessions', {});
    await env.pump();
    env.socket.emit({
      'type': 'result',
      'req': env.socket.sentOfType('op').single['req'],
      'ok': false,
      'error': {'code': 'forbidden', 'message': 'Không được'},
    });
    await expectLater(call, throwsA(isA<IdeForbidden>()));
  });

  test('hết hạn: ném IdeTimeout và gửi cancel', () async {
    env = _Env();
    await env.up();
    final call = env.rpc.call('ai.sessions', {});
    await expectLater(call, throwsA(isA<IdeTimeout>()));
    expect(env.socket.sentOfType('cancel'), hasLength(1));
  });

  test('huỷ: gửi cancel, báo IdeCancelled, result trễ bị bỏ qua', () async {
    env = _Env();
    await env.up();
    final call = env.rpc.start('ai.sessions', {});
    final result = call.result;
    await env.pump();
    call.cancel();
    await expectLater(result, throwsA(isA<IdeCancelled>()));
    expect(env.socket.sentOfType('cancel').single['req'], call.req);
    env.socket.emit({
      'type': 'result',
      'req': call.req,
      'ok': false,
      'error': {'code': 'ide_error', 'message': 'Đã huỷ'},
    });
    await env.pump();
  });

  test('need_step: ký xong gửi step, rồi nhận result', () async {
    IdeStepRequest? seen;
    env = _Env(
      step: (r) async {
        seen = r;
        return 'chu-ky';
      },
    );
    await env.up();
    final call = env.rpc.call('deploy.run', {'env': 'prod'});
    await env.pump();
    final req = env.socket.sentOfType('op').single['req'];
    env.socket.emit({
      'type': 'need_step',
      'req': req,
      'challenge': 'Y2g=',
      'summary': 'Triển khai',
    });
    await env.pump();
    expect(seen!.op, 'deploy.run');
    expect(seen!.stream, 's_AAAAAAAAAAAAAAAAAAAAAA');
    expect(seen!.args, {'env': 'prod'});
    expect(env.socket.sentOfType('step').single['sig'], 'chu-ky');
    env.socket.emit({'type': 'result', 'req': req, 'ok': true, 'data': 'xong'});
    expect(await call, 'xong');
  });

  test('need_step lặp lại khi đang hỏi: chỉ một hộp xác nhận', () async {
    var asks = 0;
    final answer = Completer<String?>();
    env = _Env(
      step: (_) {
        asks++;
        return answer.future;
      },
    );
    await env.up();
    final call = env.rpc.call('deploy.run', {});
    await env.pump();
    final req = env.socket.sentOfType('op').single['req'];
    for (var i = 0; i < 3; i++) {
      env.socket.emit({
        'type': 'need_step',
        'req': req,
        'challenge': 'Y2g=',
        'summary': 's',
      });
    }
    await env.pump();
    expect(asks, 1);
    answer.complete('chu-ky');
    await env.pump();
    expect(env.socket.sentOfType('step'), hasLength(1));
    env.socket.emit({'type': 'result', 'req': req, 'ok': true, 'data': 1});
    expect(await call, 1);
  });

  test('số vô cực / base64 hỏng từ IDE không làm vỡ client', () async {
    env = _Env();
    await env.up();
    final sink = _Sink();
    final call = env.rpc.download('files.get', {'path': 'a'}, sink: sink);
    await env.pump();
    final req = env.socket.sentOfType('op').single['req'];
    env.socket.emitRaw('{"type":"file_ack","req":"$req","seq":1e999}');
    env.socket.emitRaw(
      '{"type":"file_chunk","req":"$req","seq":1e999,"data":"AAAA"}',
    );
    env.socket.emit({'type': 'file_chunk', 'req': req, 'seq': 0, 'data': '@@'});
    await expectLater(call, throwsA(isA<IdeError>()));
    expect(env.socket.sentOfType('cancel'), hasLength(1));
  });

  test('need_step: người dùng huỷ thì gửi cancel', () async {
    env = _Env(step: (_) async => null);
    await env.up();
    final call = env.rpc.call('deploy.run', {});
    await env.pump();
    env.socket.emit({
      'type': 'need_step',
      'req': env.socket.sentOfType('op').single['req'],
      'challenge': 'Y2g=',
      'summary': 's',
    });
    await expectLater(call, throwsA(isA<IdeCancelled>()));
    expect(env.socket.sentOfType('step'), isEmpty);
    expect(env.socket.sentOfType('cancel'), hasLength(1));
  });

  test('tải theo khúc: ack từng khúc, kiểm sha256 ở file_end', () async {
    env = _Env();
    await env.up();
    final sink = _Sink();
    final future = env.rpc.download('files.get', {'path': '/a'}, sink: sink);
    await env.pump();
    final req = env.socket.sentOfType('op').single['req'];
    final data = utf8.encode('Xin chào 😀');
    env.socket.emit({
      'type': 'file_meta',
      'req': req,
      'name': 'a.txt',
      'size': data.length,
      'mime': 'text/plain',
      'mtime': 1,
    });
    for (var i = 0, seq = 0; i < data.length; i += 5, seq++) {
      env.socket.emit({
        'type': 'file_chunk',
        'req': req,
        'seq': seq,
        'data': base64Encode(
          data.sublist(i, i + 5 > data.length ? data.length : i + 5),
        ),
      });
    }
    env.socket.emit({
      'type': 'file_end',
      'req': req,
      'sha256': sha256.convert(data).toString(),
    });
    final result = await future;
    expect(sink.bytes, data);
    expect(sink.ok, isTrue);
    expect(result.size, data.length);
    expect(env.socket.sentOfType('file_ack').length, (data.length / 5).ceil());
  });

  test('tải theo khúc: sha256 sai thì lỗi và sink báo thất bại', () async {
    env = _Env();
    await env.up();
    final sink = _Sink();
    final future = env.rpc.download('files.get', {}, sink: sink);
    await env.pump();
    final req = env.socket.sentOfType('op').single['req'];
    env.socket.emit({
      'type': 'file_meta',
      'req': req,
      'name': 'a',
      'size': 3,
      'mime': '',
      'mtime': 0,
    });
    env.socket.emit({
      'type': 'file_chunk',
      'req': req,
      'seq': 0,
      'data': base64Encode([1, 2, 3]),
    });
    env.socket.emit({'type': 'file_end', 'req': req, 'sha256': '00' * 32});
    await expectLater(future, throwsA(isA<IdeError>()));
    expect(sink.ok, isFalse);
  });

  test(
    'tải lên: chia khúc, chờ ack khi quá 4 khúc, gửi sha256 ở file_end',
    () async {
      env = _Env();
      await env.up();
      final data = List<int>.generate(40, (i) => i); // 10 khúc 4 byte
      final future = env.rpc.upload('files.put', {
        'path': '/b',
      }, Stream.value(data));
      await env.pump();
      final req = env.socket.sentOfType('op').single['req'];
      env.socket.emit({'type': 'put_ready', 'req': req});
      await env.pump();
      expect(env.socket.sentOfType('file_chunk'), hasLength(4)); // dừng chờ ack
      for (var seq = 0; seq < 10; seq++) {
        env.socket.emit({'type': 'file_ack', 'req': req, 'seq': seq});
        await env.pump();
      }
      expect(env.socket.sentOfType('file_chunk'), hasLength(10));
      final end = env.socket.sentOfType('file_end').single;
      expect(end['sha256'], sha256.convert(data).toString());
      env.socket.emit({
        'type': 'result',
        'req': req,
        'ok': true,
        'data': {'path': '/b'},
      });
      expect(await future, {'path': '/b'});
    },
  );

  test(
    'nối lại không gửi trùng: yêu cầu đang chờ báo offline, socket mới không nhận op cũ',
    () async {
      env = _Env();
      await env.up();
      final call = env.rpc.call('ai.sessions', {});
      final failed = expectLater(call, throwsA(isA<IdeOffline>()));
      await env.pump();
      await env.socket.drop();
      await failed;
      await env.connection.statuses.firstWhere(
        (s) => s.phase == IdeLinkPhase.ready,
      );
      expect(env.sockets, hasLength(2));
      await env.pump();
      expect(env.sockets.last.sentOfType('op'), isEmpty);
      expect(env.sockets.last.sentOfType('rpc'), hasLength(1));
      // Gọi mới sau khi nối lại vẫn chạy bình thường.
      final again = env.rpc.call('ai.sessions', {});
      await env.pump();
      final op = env.sockets.last.sentOfType('op').single;
      env.sockets.last.emit({
        'type': 'result',
        'req': op['req'],
        'ok': true,
        'data': 1,
      });
      expect(await again, 1);
    },
  );

  test(
    'IDE ngoại tuyến rồi bị gỡ: trạng thái revoked và gọi onRevoked',
    () async {
      var revoked = false;
      final conn = IdeConnection(
        openChannel: () async {
          final s = FakeIdeSocket(autoReady: false);
          unawaited(
            Future<void>.microtask(
              () {},
            ).then((_) => s.emit({'type': 'ide_closed', 'reason': 'revoked'})),
          );
          return IdeChannel.connect(socket: s, signAuth: fakeSignAuth);
        },
        onRevoked: (_) async => revoked = true,
        backoff: const [Duration(milliseconds: 5)],
      );
      env = _Env();
      addTearDown(conn.dispose);
      conn.start();
      final status = await conn.statuses.firstWhere(
        (s) => s.phase == IdeLinkPhase.revoked,
      );
      expect(status.phase, IdeLinkPhase.revoked);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(revoked, isTrue);
    },
  );

  test('bị gỡ: báo đúng mã máy; gắn lại xong thì nối lại được', () async {
    final revokedIds = <String>[];
    var revokeNext = true;
    var opens = 0;
    final conn = IdeConnection(
      openChannel: () async {
        opens++;
        final s = FakeIdeSocket();
        final channel = await IdeChannel.connect(
          socket: s,
          signAuth: fakeSignAuth,
        );
        channel.deviceId = 'd_dev$opens';
        if (revokeNext) {
          revokeNext = false;
          unawaited(
            Future<void>.delayed(
              Duration.zero,
            ).then((_) => s.emit({'type': 'ide_closed', 'reason': 'revoked'})),
          );
        }
        return channel;
      },
      onRevoked: (id) async => revokedIds.add(id),
      backoff: const [Duration(milliseconds: 5)],
    );
    addTearDown(conn.dispose);
    conn.start();
    await conn.statuses.firstWhere((s) => s.phase == IdeLinkPhase.revoked);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(revokedIds, ['d_dev1']);
    // Nút Thử lại / quay lại app không nối khi đã bị gỡ.
    conn.retryNow();
    conn.markActive();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(opens, 1);

    await conn.restartAfterPairing();
    await conn.statuses.firstWhere((s) => s.phase == IdeLinkPhase.ready);
    expect(opens, 2);
  });

  test('mở stream cùng lúc không vượt hạn mức; đóng kết nối giữa chừng thì '
      'đóng stream vừa mở', () async {
    final gate = Completer<void>();
    final sockets = <FakeIdeSocket>[];
    final conn = IdeConnection(
      openChannel: () async {
        final s = FakeIdeSocket();
        sockets.add(s);
        await gate.future;
        return IdeChannel.connect(socket: s, signAuth: fakeSignAuth);
      },
    );
    final opens = [
      for (var i = 0; i < IdeConnection.maxTalk + 1; i++)
        conn.openStream(IdeStreamKind.talk, {'type': 'talk'}),
    ];
    // Lần vượt hạn mức bị từ chối ngay, không chờ.
    await expectLater(opens.last, throwsA(isA<IdeBusy>()));
    await conn.dispose();
    gate.complete();
    await expectLater(opens.first, throwsA(isA<IdeBusy>()));
    expect(sockets.first.closed, isTrue);
  });

  test('unauthorized: dừng, không tự nối lại, không xoá khoá', () async {
    var revoked = false;
    var opens = 0;
    final conn = IdeConnection(
      openChannel: () async {
        opens++;
        throw const IdeHandshakeException('unauthorized', deviceId: 'd_x');
      },
      onRevoked: (_) async => revoked = true,
      backoff: const [Duration(milliseconds: 5)],
    );
    addTearDown(conn.dispose);
    conn.start();
    final status = await conn.statuses.firstWhere(
      (s) => s.reason == 'unauthorized',
    );
    expect(status.phase, IdeLinkPhase.idle);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(opens, 1);
    expect(revoked, isFalse);
    // Người dùng bấm Thử lại thì được nối.
    conn.retryNow();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(opens, 2);
  });

  test(
    'ide_closed idle: đóng bình thường, không tự nối lại, mở lại khi thao tác',
    () async {
      env = _Env();
      await env.up();
      env.socket.emit({'type': 'ide_closed', 'reason': 'idle'});
      final status = await env.connection.statuses.firstWhere(
        (s) => s.phase == IdeLinkPhase.idle,
      );
      expect(status.reason, 'idle');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(env.sockets, hasLength(1));
      env.connection.retryNow();
      await env.connection.statuses.firstWhere(
        (s) => s.phase == IdeLinkPhase.ready,
      );
      expect(env.sockets, hasLength(2));
    },
  );

  test('khung gz: giải nén có giới hạn (chặn bom gzip)', () {
    final small = gzip.encode(utf8.encode('{"t":"x"}'));
    expect(utf8.decode(ideGunzipBounded(small)!), '{"t":"x"}');
    final bomb = gzip.encode(List<int>.filled(2 * 1024 * 1024, 0x20));
    expect(bomb.length, lessThan(64 * 1024));
    expect(ideGunzipBounded(bomb, limit: 1024 * 1024), isNull);
    expect(
      ideGunzipBounded(bomb, limit: 2 * 1024 * 1024),
      hasLength(2 * 1024 * 1024),
    );
  });
}
