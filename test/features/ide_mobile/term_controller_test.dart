import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_term_controller.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_term.dart';

import 'support/fakes.dart';

final class TermRig {
  TermRig({
    this.target = const IdeTermOpenTarget.existing('t1'),
    Duration resizeDebounce = const Duration(milliseconds: 20),
  }) {
    connection = IdeConnection(
      openChannel: () async {
        final socket = FakeIdeSocket(ops: const ['term.list']);
        sockets.add(socket);
        return IdeChannel.connect(
          socket: socket,
          signAuth: fakeSignAuth,
          pingEvery: const Duration(hours: 1),
        );
      },
    );
    controller = IdeTermController(
      connection: connection,
      target: target,
      pingEvery: const Duration(milliseconds: 40),
      resizeDebounce: resizeDebounce,
    );
  }

  final IdeTermOpenTarget target;
  late final IdeConnection connection;
  late final IdeTermController controller;
  final sockets = <FakeIdeSocket>[];

  List<FakeIdeSocket> get termSockets => [
    for (final s in sockets)
      if (s.sent.any((f) => f['type'] == 'term')) s,
  ];
  FakeIdeSocket get socket => termSockets.last;

  List<Map<String, Object?>> sent(String type) =>
      socket.sent.where((f) => f['type'] == type).toList();

  /// Chữ đã gõ lên IDE (giải base64 các khung `tin`).
  String typed() => utf8.decode([
    for (final f in sent('tin')) ...base64Decode(f['data']! as String),
  ]);

  void out(String text) =>
      socket.emit({'type': 'tout', 'data': base64Encode(utf8.encode(text))});

  Future<void> settle([int ms = 40]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> live({String name = 't1'}) async {
    controller.start();
    await settle();
    socket.emit({'type': 'tready', 'name': name, 'cols': 80, 'rows': 24});
    await settle();
  }

  Future<void> dispose() async {
    controller.dispose();
    await connection.dispose();
  }
}

String screen(IdeTermController c, int y) {
  final b = c.terminal.buffer;
  return b.lines[b.scrollBack + y].getText().trimRight();
}

void main() {
  test('gắn phiên có sẵn: gửi {type:term,name}, tready -> live', () async {
    final rig = TermRig();
    rig.controller.start();
    await rig.settle();
    expect(rig.socket.sent.firstWhere((f) => f['type'] == 'term'), {
      'type': 'term',
      'name': 't1',
    });
    expect(rig.controller.state.link, IdeTermLink.connecting);
    rig.socket.emit({'type': 'tready', 'name': 't1', 'cols': 80, 'rows': 24});
    await rig.settle();
    expect(rig.controller.state.link, IdeTermLink.live);
    await rig.dispose();
  });

  test('phiên mới gửi root/cmd/cols/rows và lấy tên từ tready', () async {
    final rig = TermRig(
      target: const IdeTermOpenTarget.create(root: '/srv/x', cmd: 'claude'),
    );
    await rig.live(name: 'moi-1');
    expect(rig.socket.sent.firstWhere((f) => f['type'] == 'term'), {
      'type': 'term',
      'new': {'root': '/srv/x', 'cmd': 'claude', 'cols': 80, 'rows': 24},
    });
    expect(rig.controller.state.name, 'moi-1');
    await rig.dispose();
  });

  test(
    'tout (tiếng Việt cắt giữa khung) -> màn hình; texit -> exited',
    () async {
      final rig = TermRig();
      await rig.live();
      final bytes = utf8.encode('Chào Việt\r\n');
      for (final cut in [bytes.sublist(0, 2), bytes.sublist(2)]) {
        rig.socket.emit({'type': 'tout', 'data': base64Encode(cut)});
      }
      await rig.settle();
      expect(screen(rig.controller, 0), 'Chào Việt');
      rig.socket.emit({'type': 'texit', 'code': 3});
      await rig.settle();
      expect(rig.controller.state.link, IdeTermLink.exited);
      expect(rig.controller.state.exitCode, 3);
      // Đã kết thúc: không gửi thêm gì.
      rig.controller.sendText('x');
      await rig.settle();
      expect(rig.sent('tin'), isEmpty);
      await rig.dispose();
    },
  );

  test('forbidden / busy / not_found khi mở', () async {
    for (final (code, link) in [
      ('forbidden', IdeTermLink.denied),
      ('busy', IdeTermLink.busy),
      ('not_found', IdeTermLink.notFound),
      ('weird', IdeTermLink.failed),
    ]) {
      final rig = TermRig();
      rig.controller.start();
      await rig.settle();
      rig.socket.emit({'type': 'error', 'code': code, 'message': 'm'});
      await rig.settle();
      expect(rig.controller.state.link, link, reason: code);
      await rig.dispose();
    }
  });

  test('vượt hạn mức stream term -> busy, không mở ổ cắm', () async {
    final rig = TermRig();
    final others = [
      for (var i = 0; i < 4; i++)
        await rig.connection.openStream(IdeStreamKind.term, {
          'type': 'term',
          'name': 'a$i',
        }),
    ];
    rig.controller.start();
    await rig.settle();
    expect(rig.controller.state.link, IdeTermLink.busy);
    expect(others, hasLength(4));
    await rig.dispose();
  });

  test('mất kết nối -> lost; nối lại gắn bằng name, xoá màn hình cũ', () async {
    final rig = TermRig(
      target: const IdeTermOpenTarget.create(root: '/r', cmd: 'shell'),
    );
    await rig.live(name: 'moi-1');
    rig.out('cu\r\n');
    await rig.settle();
    expect(screen(rig.controller, 0), 'cu');
    final first = rig.socket;
    await first.drop();
    await rig.settle();
    expect(rig.controller.state.link, IdeTermLink.lost);
    rig.controller.reconnect();
    await rig.settle();
    expect(rig.termSockets, hasLength(2));
    expect(rig.socket.sent.firstWhere((f) => f['type'] == 'term'), {
      'type': 'term',
      'name': 'moi-1',
    });
    rig.socket.emit({
      'type': 'tready',
      'name': 'moi-1',
      'cols': 80,
      'rows': 24,
    });
    rig.out('moi\r\n');
    await rig.settle();
    expect(rig.controller.state.link, IdeTermLink.live);
    expect(screen(rig.controller, 0), 'moi');
    await rig.dispose();
  });

  test('đóng controller đóng stream, không gửi lệnh giết phiên', () async {
    final rig = TermRig();
    await rig.live();
    final s = rig.socket;
    rig.controller.dispose();
    await rig.settle();
    expect(s.closed, isTrue);
    expect(s.sent.where((f) => f['type'] == 'op'), isEmpty);
    await rig.connection.dispose();
  });

  test('gõ phím gửi tin base64; Ctrl dính + chữ thành mã điều khiển', () async {
    final rig = TermRig();
    await rig.live();
    rig.controller.terminal.textInput('ls');
    rig.controller.toggleCtrl();
    expect(rig.controller.state.ctrl, isTrue);
    rig.controller.terminal.textInput('c');
    expect(rig.controller.state.ctrl, isFalse);
    rig.controller.terminal.textInput('c'); // Ctrl đã nhả
    await rig.settle();
    expect(rig.typed(), 'ls\x03c');
    await rig.dispose();
  });

  test('Alt + chữ = ESC + chữ; phím phụ theo mod và chế độ con trỏ', () async {
    final rig = TermRig();
    await rig.live();
    rig.controller.toggleAlt();
    rig.controller.terminal.textInput('f');
    rig.controller.pressText(IdeTermKeys.esc);
    rig.controller.pressNav(
      (mod, app) => IdeTermKeys.arrow('up', appCursor: app, mod: mod),
    );
    rig.controller.toggleCtrl();
    rig.controller.pressNav(
      (mod, app) => IdeTermKeys.arrow('left', appCursor: app, mod: mod),
    );
    rig.controller.terminal.write('\x1b[?1h'); // con trỏ ứng dụng (vim / htop)
    rig.controller.pressNav(
      (mod, app) => IdeTermKeys.arrow('down', appCursor: app, mod: mod),
    );
    await rig.settle();
    expect(rig.typed(), '\x1bf\x1b\x1b[A\x1b[1;5D\x1bOB');
    await rig.dispose();
  });

  test('dán dài chia khung ≤ 64 KB, ghép lại đủ', () async {
    final rig = TermRig();
    await rig.live();
    final text = 'ệ' * 50000; // 150 000 byte
    rig.controller.terminal.paste(text);
    await rig.settle();
    final frames = rig.sent('tin');
    expect(frames.length, greaterThanOrEqualTo(3));
    for (final f in frames) {
      expect(
        base64Decode(f['data']! as String).length,
        lessThanOrEqualTo(65536),
      );
    }
    expect(rig.typed(), text);
    await rig.dispose();
  });

  test('resize được gom: nhiều lần đổi cỡ gửi một khung cuối', () async {
    final rig = TermRig();
    await rig.live();
    final t = rig.controller.terminal;
    t.resize(90, 30);
    t.resize(100, 31);
    t.resize(110, 32);
    await rig.settle(80);
    expect(rig.sent('resize'), [
      {'type': 'resize', 'cols': 110, 'rows': 32},
    ]);
    // Cỡ trùng cỡ IDE đã biết thì không gửi lại.
    t.resize(110, 32);
    await rig.settle(80);
    expect(rig.sent('resize'), hasLength(1));
    await rig.dispose();
  });

  test('resize kẹp theo hợp đồng (cột 20–500, hàng 5–200)', () async {
    final rig = TermRig();
    await rig.live();
    rig.controller.terminal.resize(8, 2);
    await rig.settle(80);
    expect(rig.sent('resize').last, {'type': 'resize', 'cols': 20, 'rows': 5});
    await rig.dispose();
  });

  test('gửi ping định kỳ khi live', () async {
    final rig = TermRig();
    await rig.live();
    await rig.settle(120);
    expect(rig.sent('ping'), isNotEmpty);
    await rig.dispose();
  });
}
