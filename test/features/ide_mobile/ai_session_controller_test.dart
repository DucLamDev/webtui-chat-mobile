import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_ai_session_controller.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_connection.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_rpc_client.dart';

import 'support/fakes.dart';

/// Đường nối giả: mỗi lần mở trả một [FakeIdeSocket] mới (giữ lại để test).
final class Rig {
  Rig({this.target = const IdeAiOpenTarget.existing('k1')}) {
    connection = IdeConnection(
      openChannel: () async {
        if (failOpen != null) throw failOpen!;
        final socket = FakeIdeSocket(ops: const ['ai.sessions']);
        sockets.add(socket);
        return IdeChannel.connect(
          socket: socket,
          signAuth: fakeSignAuth,
          pingEvery: const Duration(hours: 1),
        );
      },
    );
    controller = IdeAiSessionController(
      connection: connection,
      target: target,
      clientId: () async => 'mobile-11111111-1111-4111-8111-111111111111',
      stepHandler: (request) async {
        steps.add(request);
        return stepSignature;
      },
      coalesce: const Duration(milliseconds: 5),
      pingEvery: const Duration(milliseconds: 40),
      backoff: const [Duration(milliseconds: 10)],
    );
  }

  final IdeAiOpenTarget target;
  late final IdeConnection connection;
  late final IdeAiSessionController controller;
  final sockets = <FakeIdeSocket>[];
  final steps = <IdeStepRequest>[];
  Object? failOpen;
  String? stepSignature = 'SIG';

  /// Ổ cắm của stream `ai` (bỏ ổ của stream rpc mà IdeConnection tự giữ).
  List<FakeIdeSocket> get aiSockets => [
    for (final s in sockets)
      if (s.sent.any((f) => f['type'] == 'open')) s,
  ];

  FakeIdeSocket get socket => aiSockets.last;

  Future<void> settle([int ms = 30]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> dispose() async {
    controller.dispose();
    await connection.dispose();
  }
}

Map<String, Object?> stateFrame({int rev = 1, Map<String, Object?>? extra}) => {
  'type': 'state',
  'sessionKey': 'k1',
  'state': {'revision': rev, 'messages': <Object?>[], 'busy': false, ...?extra},
};

void main() {
  test('mở stream ai, hello rồi subscribe patch:1', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    final sent = rig.socket.sent.where((f) => f['type'] != 'auth').toList();
    expect(sent[0], {'type': 'open', 'session_key': 'k1'});
    expect(sent[1]['type'], 'hello');
    expect(sent[1]['clientId'], startsWith('mobile-'));
    expect(sent[2], {'type': 'subscribe', 'patch': 1});
    await rig.dispose();
  });

  test(
    'phiên mới gửi kind/root/worktree rồi lấy sessionKey từ state',
    () async {
      final rig = Rig(
        target: const IdeAiOpenTarget.create(
          kind: 'claude',
          root: '/srv/x',
          worktree: 'nhanh',
        ),
      );
      rig.controller.start();
      await rig.settle();
      expect(rig.socket.sent.firstWhere((f) => f['type'] == 'open'), {
        'type': 'open',
        'kind': 'claude',
        'root': '/srv/x',
        'worktree': 'nhanh',
      });
      rig.socket.emit(stateFrame());
      await rig.settle();
      expect(rig.controller.state.sessionKey, 'k1');
      expect(rig.controller.state.link, IdeAiLink.live);
      await rig.dispose();
    },
  );

  test('áp state + patch; patch lệch thì subscribe lại', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    rig.socket.emit(stateFrame(extra: {'busy': true}));
    rig.socket.emit({
      'type': 'patch',
      'base': 1,
      'revision': 2,
      'set': {'busy': false},
    });
    await rig.settle();
    expect(rig.controller.state.view.busy, false);
    expect(rig.controller.state.revision, 2);
    final before = rig.socket.sentOfType('subscribe').length;
    rig.socket.emit({'type': 'patch', 'base': 9, 'revision': 10, 'set': {}});
    rig.socket.emit({'type': 'patch', 'base': 9, 'revision': 10, 'set': {}});
    await rig.settle();
    // Hai patch lệch liên tiếp chỉ gửi một lần subscribe.
    expect(rig.socket.sentOfType('subscribe').length, before + 1);
    await rig.dispose();
  });

  test('giải khung gz', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    final inner = utf8.encode(jsonEncode(stateFrame(extra: {'busy': true})));
    rig.socket.emit({'type': 'gz', 'data': base64Encode(gzip.encode(inner))});
    await rig.settle();
    expect(rig.controller.state.view.busy, true);
    await rig.dispose();
  });

  test('role, clients, notice, error VIEW_ONLY', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    rig.socket
      ..emit(stateFrame())
      ..emit({'type': 'role', 'control': false, 'free': false})
      ..emit({'type': 'clients', 'count': 2})
      ..emit({'type': 'notice', 'message': 'Xong'})
      ..emit({'type': 'error', 'message': 'VIEW_ONLY: chỉ xem'});
    await rig.settle();
    final s = rig.controller.state;
    expect(s.canControl, false);
    expect(s.clients, 2);
    expect(s.notice, 'Xong');
    expect(s.problem?.viewOnly, true);
    rig.controller.claim();
    expect(rig.socket.sentOfType('claim').single['take'], true);
    await rig.dispose();
  });

  test('need_step ký bằng op ai.answer, args bỏ type, rồi gửi step', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    rig.controller.answer('ap1', allow: true);
    rig.socket.emit({
      'type': 'need_step',
      'req': 'a_ap1',
      'challenge': 'Q0g=',
      'summary': 'Cho phép',
    });
    await rig.settle();
    expect(rig.steps.single.op, 'ai.answer');
    expect(rig.steps.single.req, 'a_ap1');
    expect(rig.steps.single.args, {'id': 'ap1', 'decision': 'allow'});
    expect(rig.socket.sentOfType('step').single, {
      'type': 'step',
      'req': 'a_ap1',
      'sig': 'SIG',
    });
    await rig.dispose();
  });

  test(
    'need_step lạ không khớp khung giữ thì bỏ qua, không hỏi vân tay',
    () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      rig.controller.answer('ap1', allow: true);
      rig.socket.emit({
        'type': 'need_step',
        'req': 'x_zzz',
        'challenge': 'Q0g=',
      });
      rig.socket.emit({
        'type': 'need_step',
        'req': 'a_khac',
        'challenge': 'Q0g=',
      });
      await rig.settle();
      expect(rig.steps, isEmpty);
      expect(rig.socket.sentOfType('step'), isEmpty);
      await rig.dispose();
    },
  );

  test('mỗi req chỉ hỏi một lần; tóm tắt do app dựng', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    rig.controller.answer('ap1', allow: false);
    for (var i = 0; i < 2; i++) {
      rig.socket.emit({
        'type': 'need_step',
        'req': 'a_ap1',
        'challenge': 'Q0g=',
        'summary': 'Tóm tắt của IDE',
      });
    }
    await rig.settle();
    expect(rig.steps, hasLength(1));
    expect(rig.steps.single.summary, contains('Từ chối'));
    expect(rig.steps.single.summary, contains('Tóm tắt của IDE'));
    expect(rig.socket.sentOfType('step'), hasLength(1));
    await rig.dispose();
  });

  test('hai need_step cùng lúc: hỏi lần lượt, mỗi lần một hộp', () async {
    final rig = Rig();
    var open = 0;
    var maxOpen = 0;
    final gate = Completer<void>();
    final c = IdeAiSessionController(
      connection: rig.connection,
      target: rig.target,
      clientId: () async => 'mobile-11111111-1111-4111-8111-111111111111',
      stepHandler: (r) async {
        open++;
        if (open > maxOpen) maxOpen = open;
        rig.steps.add(r);
        await gate.future;
        open--;
        return 'SIG';
      },
      coalesce: const Duration(milliseconds: 5),
      backoff: const [Duration(milliseconds: 10)],
    )..start();
    await rig.settle();
    c.answer('ap1', allow: true);
    c.answer('ap2', allow: true);
    rig.socket.emit({'type': 'need_step', 'req': 'a_ap1', 'challenge': 'Q0g='});
    rig.socket.emit({'type': 'need_step', 'req': 'a_ap2', 'challenge': 'Q0g='});
    await rig.settle();
    expect(rig.steps, hasLength(1));
    gate.complete();
    await rig.settle();
    expect(rig.steps, hasLength(2));
    expect(maxOpen, 1);
    expect(rig.socket.sentOfType('step'), hasLength(2));
    c.dispose();
    await rig.dispose();
  });

  test(
    'need_step req=plan ký khung approve_plan; khung khác không ký',
    () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      rig.controller.approvePlan(decisions: [1, 2]);
      rig.controller.reset();
      rig.socket.emit({
        'type': 'need_step',
        'req': 'reset',
        'challenge': 'Q0g=',
      });
      rig.socket.emit({
        'type': 'need_step',
        'req': 'plan',
        'challenge': 'Q0g=',
      });
      await rig.settle();
      expect(rig.steps, hasLength(1));
      expect(rig.steps.single.op, 'ai.approve_plan');
      expect(rig.steps.single.args, {
        'decisions': [1, 2],
      });
      expect(
        rig.steps.single.summary,
        contains('Duyệt kế hoạch (2 quyết định)'),
      );
      expect(rig.socket.sentOfType('step').single['req'], 'plan');
      await rig.dispose();
    },
  );

  test('need_step req=plan khi không giữ approve_plan thì bỏ qua', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    rig.socket.emit({'type': 'need_step', 'req': 'plan', 'challenge': 'Q0g='});
    await rig.settle();
    expect(rig.steps, isEmpty);
    await rig.dispose();
  });

  test('huỷ vân tay thì không gửi step và không gửi deny', () async {
    final rig = Rig()..stepSignature = null;
    rig.controller.start();
    await rig.settle();
    rig.controller.answer('ap1', allow: true);
    rig.socket.emit({'type': 'need_step', 'req': 'a_ap1', 'challenge': 'Q0g='});
    await rig.settle();
    expect(rig.socket.sentOfType('step'), isEmpty);
    expect(
      rig.socket.sentOfType('answer').where((f) => f['decision'] == 'deny'),
      isEmpty,
    );
    await rig.dispose();
  });

  test(
    'rớt mạng thì nối lại cùng session_key và gửi lại hello/subscribe',
    () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      rig.socket.emit(stateFrame());
      await rig.settle();
      await rig.socket.drop();
      await rig.settle(80);
      expect(rig.aiSockets.length, 2);
      final sent = rig.aiSockets[1].sent;
      expect(sent.firstWhere((f) => f['type'] == 'open')['session_key'], 'k1');
      expect(sent.map((f) => f['type']), containsAll(['hello', 'subscribe']));
      await rig.dispose();
    },
  );

  test('ide_closed revoked thì dừng hẳn, không nối lại', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    rig.socket.emit({'type': 'ide_closed', 'reason': 'revoked'});
    await rig.settle(80);
    expect(rig.controller.state.link, IdeAiLink.closed);
    expect(rig.controller.state.closedReason, 'revoked');
    expect(rig.aiSockets.length, 1);
    await rig.dispose();
  });

  test('session_revoked cũng không nối lại', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    rig.socket.emit({'type': 'ide_closed', 'reason': 'session_revoked'});
    await rig.settle(80);
    expect(rig.controller.state.link, IdeAiLink.closed);
    expect(rig.aiSockets.length, 1);
    await rig.dispose();
  });

  test(
    'mọi khung gửi đều có type, không bao giờ action; ping định kỳ',
    () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      rig.controller
        ..send('xin chào')
        ..interrupt()
        ..approvePlan(decisions: {'a': 'b'})
        ..deepenPlan()
        ..unqueue('q1')
        ..sendNow('q1')
        ..queueRun()
        ..reset()
        ..compact()
        ..restart(3)
        ..models()
        ..changeAccount('acc')
        ..load('h1')
        ..stopTask('t1')
        ..configure({'model': 'x'});
      unawaited(
        rig.controller.history().catchError((_) => <String, Object?>{}),
      );
      unawaited(
        rig.controller.search('abc').catchError((_) => <String, Object?>{}),
      );
      unawaited(
        rig.controller
            .rewind('m1', dry: true)
            .catchError((_) => <String, Object?>{}),
      );
      await rig.settle(120);
      for (final frame in rig.socket.sent) {
        expect(frame.containsKey('type'), true, reason: '$frame');
        expect(frame.containsKey('action'), false, reason: '$frame');
      }
      expect(rig.socket.sentOfType('ping'), isNotEmpty);
      expect(
        rig.socket.sentOfType('send').single['id'],
        matches(RegExp(r'^m-[0-9a-f-]{36}$')),
      );
      expect(() => rig.controller.command('action'), throwsA(anything));
      await rig.dispose();
    },
  );

  test('rewind trả lời theo id', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    final future = rig.controller.rewind('m1', dry: true);
    await rig.settle();
    final asked = rig.socket.sentOfType('rewind').single;
    expect(asked['dry'], true);
    rig.socket.emit({
      'type': 'rewind',
      'id': asked['id'],
      'files': ['/a/b'],
      'canRewind': true,
    });
    final reply = await future;
    expect(reply['files'], ['/a/b']);
    await rig.dispose();
  });

  test('IdeBusy hoặc HTTP 401 ở lúc mở: không nối lại mãi', () async {
    final rig = Rig()..failOpen = const IdeHandshakeException('unauthorized');
    rig.controller.start();
    await rig.settle(80);
    expect(rig.controller.state.link, IdeAiLink.closed);
    expect(rig.controller.state.closedReason, 'unauthorized');
    await rig.dispose();
  });

  test('forbidden / hết phiên ở lúc mở: đóng, không nối lại', () async {
    for (final reason in ['forbidden', 'session_expired']) {
      final rig = Rig()..failOpen = IdeHandshakeException(reason);
      rig.controller.start();
      await rig.settle(80);
      expect(rig.controller.state.link, IdeAiLink.closed);
      expect(rig.controller.state.closedReason, reason);
      await rig.dispose();
    }
  });

  group('ký xác nhận qua nhiều lượt', () {
    Future<void> need(Rig rig, String req, [String ch = 'Q0g=']) async {
      rig.socket.emit({'type': 'need_step', 'req': req, 'challenge': ch});
      await rig.settle();
    }

    test('duyệt kế hoạch 2 lần trong một phiên đều ký', () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      for (var i = 0; i < 2; i++) {
        rig.controller.approvePlan(decisions: [i]);
        await need(rig, 'plan', 'ch$i');
      }
      expect(rig.steps, hasLength(2));
      expect(rig.steps.last.args, {
        'decisions': [1],
      });
      expect(rig.socket.sentOfType('step'), hasLength(2));
      await rig.dispose();
    });

    test('huỷ vân tay rồi bấm duyệt lại thì ký được', () async {
      final rig = Rig()..stepSignature = null;
      rig.controller.start();
      await rig.settle();
      rig.controller.answer('ap1', allow: true);
      await need(rig, 'a_ap1', 'c1');
      expect(rig.socket.sentOfType('step'), isEmpty);
      rig.stepSignature = 'SIG';
      rig.controller.answer('ap1', allow: true);
      await need(rig, 'a_ap1', 'c2');
      expect(rig.steps, hasLength(2));
      expect(rig.socket.sentOfType('step'), hasLength(1));
      await rig.dispose();
    });

    test('need_step lặp sau khi đã ký không ký lần 2', () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      rig.controller.answer('ap1', allow: true);
      await need(rig, 'a_ap1');
      await need(rig, 'a_ap1');
      expect(rig.steps, hasLength(1));
      expect(rig.socket.sentOfType('step'), hasLength(1));
      await rig.dispose();
    });

    test('hai khung answer cùng id: chỉ khung mới nhất được ký', () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      rig.controller.answer('ap1', allow: false);
      rig.controller.answer('ap1', allow: true);
      await need(rig, 'a_ap1');
      expect(rig.steps, hasLength(1));
      expect(rig.steps.single.args, {'id': 'ap1', 'decision': 'allow'});
      await rig.dispose();
    });

    test('gửi send 10 lần không đẩy khung answer ra', () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      rig.controller.answer('ap1', allow: true);
      for (var i = 0; i < 10; i++) {
        rig.controller.send('xin chào $i');
      }
      await need(rig, 'a_ap1');
      expect(rig.steps, hasLength(1));
      await rig.dispose();
    });
  });
}
