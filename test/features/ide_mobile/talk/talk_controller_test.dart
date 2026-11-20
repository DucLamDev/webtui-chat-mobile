import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_talk_controller.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_talk_service.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_talk_models.dart';

import '../support/fakes.dart';
import '../support/rpc_env.dart';

const talkId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, Object?> msg(String id, String role, String text) => {
  'id': id,
  'role': role,
  'text': text,
};

Map<String, Object?> full(List<Map<String, Object?>> m, {int cut = 0}) => {
  'type': 'talk_delta',
  'id': talkId,
  'title': 'T',
  'messages': m,
  if (cut > 0) 'truncated_before': cut,
};

/// Dịch vụ giả: ghi lại lời gọi, không đụng mạng.
final class FakeSvc extends IdeTalkService {
  FakeSvc(super.rpc);
  final sends = <Map<String, Object?>>[];
  final gate = Completer<void>();
  bool hold = false;
  int uploads = 0;

  @override
  Future<String> uploadAttachment({
    required bool image,
    required String name,
    required String mime,
    required int size,
    required Stream<List<int>> Function() read,
  }) async {
    uploads++;
    return image ? 'img_ref_1' : 'file_ref_1';
  }

  @override
  Future<IdeTalkSendResult> send({
    required String id,
    required String text,
    String? model,
    String? effort,
    bool queue = false,
    List<String> images = const [],
    List<String> files = const [],
  }) async {
    sends.add({'id': id, 'text': text, 'images': images, 'files': files});
    if (hold) await gate.future;
    return IdeTalkSendResult(id: id);
  }
}

final class Rig {
  Rig({
    Duration idle = const Duration(milliseconds: 200),
    Duration check = const Duration(milliseconds: 30),
    Duration deltaBase = const Duration(seconds: 1),
  }) {
    connection = IdeConnection(
      openChannel: () async {
        final s = FakeIdeSocket(ops: const ['talk.list', 'talk.send']);
        sockets.add(s);
        return IdeChannel.connect(
          socket: s,
          signAuth: fakeSignAuth,
          pingEvery: const Duration(hours: 1),
        );
      },
      backoff: const [Duration(milliseconds: 5)],
    );
    final env = IdeRpcEnv((_, _) => null);
    svc = FakeSvc(env.rpc);
    controller = IdeTalkController(
      connection: connection,
      service: svc,
      talkId: talkId,
      idleReopenAfter: idle,
      idleCheckEvery: check,
      retryAfter: const Duration(milliseconds: 20),
      deltaBackoffBase: deltaBase,
    );
  }

  late final IdeConnection connection;
  late final FakeSvc svc;
  late final IdeTalkController controller;
  final sockets = <FakeIdeSocket>[];

  List<FakeIdeSocket> get talkSockets => [
    for (final s in sockets)
      if (s.sent.any((f) => f['type'] == 'talk')) s,
  ];

  Future<void> wait([int ms = 60]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> dispose() async {
    controller.dispose();
    await connection.dispose();
  }
}

void main() {
  test('full -> delta thay tin cuối -> gone', () async {
    final rig = Rig(idle: const Duration(hours: 1));
    rig.controller.start();
    await rig.wait();
    expect(rig.talkSockets.single.sent.last['id'], talkId);
    final s = rig.talkSockets.single;
    s.emit(full([msg('1', 'user', 'chào'), msg('2', 'assistant', 'Xin')]));
    await rig.wait();
    expect(rig.controller.state.link, IdeTalkLink.live);
    expect(rig.controller.state.conversation!.messages.length, 2);
    s.emit({
      'type': 'talk_delta',
      'delta': true,
      'message': msg('2', 'assistant', 'Xin chào bạn'),
    });
    await rig.wait();
    final m = rig.controller.state.conversation!.messages;
    expect(m.length, 2);
    expect(m.last.text, 'Xin chào bạn');
    s.emit({'type': 'talk_delta', 'gone': true});
    await rig.wait();
    expect(rig.controller.state.link, IdeTalkLink.gone);
    await rig.dispose();
  });

  test('heartbeat giữ stream; im quá hạn thì mở lại', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.wait();
    final first = rig.talkSockets.single;
    first.emit(full([msg('1', 'user', 'a')]));
    for (var i = 0; i < 5; i++) {
      await rig.wait(60);
      first.emit({'type': 'talk_delta', 'heartbeat': true});
    }
    expect(rig.talkSockets.length, 1);
    await rig.wait(500);
    expect(rig.talkSockets.length, greaterThan(1));
    await rig.dispose();
  });

  test('truncated_before được giữ trong state', () async {
    final rig = Rig(idle: const Duration(hours: 1));
    rig.controller.start();
    await rig.wait();
    rig.talkSockets.single.emit(full([msg('1', 'user', 'a')], cut: 12));
    await rig.wait();
    expect(rig.controller.state.conversation!.truncatedBefore, 12);
    await rig.dispose();
  });

  test('khung sai dạng bị bỏ qua', () async {
    final rig = Rig(idle: const Duration(hours: 1));
    rig.controller.start();
    await rig.wait();
    final s = rig.talkSockets.single;
    s.emit(full([msg('1', 'user', 'a')]));
    s.emit({'type': 'talk_delta', 'delta': true, 'message': 'rác'});
    s.emit({'type': 'talk_delta', 'messages': 5, 'id': talkId});
    await rig.wait();
    expect(rig.controller.state.conversation!.messages.length, 1);
    await rig.dispose();
  });

  test('gửi kèm ảnh dùng ref, không dùng đường dẫn', () async {
    final rig = Rig(idle: const Duration(hours: 1));
    await rig.controller.send(
      'xem ảnh',
      attachments: [
        IdeTalkAttachment(
          image: true,
          name: 'a.png',
          mime: 'image/png',
          size: 3,
          read: () => Stream.value(Uint8List(3)),
        ),
      ],
    );
    final sent = rig.svc.sends.single;
    expect(sent['images'], ['img_ref_1']);
    expect(sent['files'], isEmpty);
    await rig.dispose();
  });

  test('bấm gửi hai lần chỉ gửi một lượt', () async {
    final rig = Rig(idle: const Duration(hours: 1));
    rig.svc.hold = true;
    final a = rig.controller.send('một');
    final b = await rig.controller.send('hai');
    expect(b, isNull);
    rig.svc.gate.complete();
    await a;
    expect(rig.svc.sends.length, 1);
    await rig.dispose();
  });

  test('đóng controller thì đóng stream', () async {
    final rig = Rig(idle: const Duration(hours: 1));
    rig.controller.start();
    await rig.wait();
    final s = rig.talkSockets.single;
    expect(s.closed, isFalse);
    rig.controller.dispose();
    await rig.wait();
    expect(s.closed, isTrue);
    await rig.connection.dispose();
  });

  test('ra nền đóng stream, quay lại mở lại', () async {
    final rig = Rig(idle: const Duration(hours: 1));
    rig.controller.start();
    await rig.wait();
    rig.controller.pause();
    await rig.wait();
    expect(rig.talkSockets.single.closed, isTrue);
    rig.controller.resume();
    await rig.wait();
    expect(rig.talkSockets.length, 2);
    await rig.dispose();
  });
}
