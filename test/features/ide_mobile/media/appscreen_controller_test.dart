import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_appscreen_controller.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_media_service.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_project_service.dart';

import '../support/rpc_env.dart';

const _ms = Duration(milliseconds: 30);
final _okFrame = {
  'w': 10,
  'h': 20,
  'mime': 'image/png',
  'data': base64Encode([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
    0, 0, 0, 10, 0, 0, 0, 20, 1,
  ]),
};
Map<String, Object?> _status({String state = 'running'}) => {
  'sessions': [
    {'project': 'web', 'status': state, 'device': 'iphone', 'dark': false},
  ],
  'max': 2,
  'devices': {
    'iphone': {'label': 'iPhone', 'platform': 'ios'},
  },
};

Future<void> _wait(int n) => Future<void>.delayed(_ms * n);

void main() {
  late IdeRpcEnv env;
  late IdeAppScreenController c;
  var active = true;

  Future<void> setup(IdeFakeHandler h) async {
    active = true;
    env = IdeRpcEnv(h, ops: const ['jobs.tail']);
    await env.up();
    c = IdeAppScreenController(
      media: IdeMediaService(env.rpc),
      jobs: IdeProjectService(env.rpc),
      project: 'web',
      canRun: () => true,
      isActive: () => active,
      frameInterval: _ms,
      jobPoll: const Duration(milliseconds: 5),
    );
  }

  tearDown(() async {
    c.dispose();
    await env.dispose();
  });

  int frames() => env.calls.where((o) => o == 'appscreen.frame').length;

  test('hỏi khung theo nhịp và giữ khung', () async {
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => _status(),
        'appscreen.frame' => _okFrame,
        _ => null,
      },
    );
    await c.load();
    await _wait(6);
    expect(frames(), greaterThanOrEqualTo(3));
    expect(c.frame, isNotNull);
  });

  test('không gửi yêu cầu thứ hai khi yêu cầu trước chưa xong', () async {
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => _status(),
        'appscreen.frame' => ideFakeSilent,
        _ => null,
      },
    );
    await c.load();
    await _wait(8);
    expect(frames(), 1);
  });

  test('dừng khi ở nền / màn bị che, tiếp khi quay lại', () async {
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => _status(),
        'appscreen.frame' => _okFrame,
        _ => null,
      },
    );
    active = false;
    await c.load();
    await _wait(6);
    expect(frames(), 0);
    active = true;
    c.resume();
    await _wait(2);
    expect(frames(), greaterThan(0));
  });

  test('rời màn (dispose) thì không hỏi nữa', () async {
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => _status(),
        'appscreen.frame' => _okFrame,
        _ => null,
      },
    );
    await c.load();
    await _wait(3);
    c.dispose();
    await _wait(1);
    final n = frames();
    await _wait(6);
    expect(frames(), n);
  });

  test('not_found: chưa mở, thôi hỏi khung', () async {
    var gone = false;
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => gone ? {'sessions': []} : _status(),
        'appscreen.frame' => () {
          gone = true;
          return const IdeFakeError('not_found', 'Chưa mở màn hình app');
        }(),
        _ => null,
      },
    );
    await c.load();
    await _wait(4);
    expect(c.session, isNull);
    expect(c.notOpen, isTrue);
    final n = frames();
    await _wait(5);
    expect(frames(), n);
  });

  test('busy: đang dựng và hỏi tiếp', () async {
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => _status(state: 'starting'),
        'appscreen.frame' => const IdeFakeError('busy', 'đang dựng'),
        _ => null,
      },
    );
    await c.load();
    await _wait(6);
    expect(c.building, isTrue);
    expect(frames(), greaterThanOrEqualTo(2));
  });

  test('khung hỏng bị bỏ, giữ khung cũ', () async {
    var n = 0;
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => _status(),
        'appscreen.frame' =>
          ++n == 1 ? _okFrame : {..._okFrame, 'data': '@@@@'},
        _ => null,
      },
    );
    await c.load();
    await _wait(6);
    expect(frames(), greaterThan(2));
    expect(c.frame, isNotNull);
  });

  test('check run:false: máy chưa cài công cụ', () async {
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': false},
        _ => null,
      },
    );
    await c.load();
    expect(c.phase, IdeAppPhase.noTool);
    expect(env.calls, isNot(contains('appscreen.status')));
  });

  test('run đi qua việc nền, giữ ≤ 14 dòng cuối, chống bấm đôi', () async {
    var started = false;
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => started ? _status() : {'sessions': []},
        'appscreen.run' => () {
          started = true;
          return {'job': 'j1'};
        }(),
        'jobs.tail' => {
          'done': true,
          'status': 'done',
          'next': 1,
          'text': [for (var i = 1; i <= 30; i++) 'dòng $i'].join('\n'),
          'result': {'ok': true, 'message': 'đã mở'},
        },
        'appscreen.frame' => _okFrame,
        _ => null,
      },
    );
    await c.load();
    expect(c.session, isNull);
    unawaited(c.run(device: 'iphone', dark: true));
    unawaited(c.run(device: 'iphone', dark: true)); // bấm đôi
    await _wait(4);
    expect(env.calls.where((o) => o == 'appscreen.run'), hasLength(1));
    expect(env.calls, contains('jobs.tail'));
    expect(c.log.length, ideAppLogLines);
    expect(c.log.last, 'dòng 30');
    expect(c.runMessage, 'đã mở');
    expect(c.session, isNotNull);
    expect(c.running, isFalse);
  });

  test('kết nối IDE không ready thì không hỏi khung', () async {
    await setup(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => _status(),
        'appscreen.frame' => _okFrame,
        _ => null,
      },
    );
    c.dispose();
    var ready = false;
    c = IdeAppScreenController(
      media: IdeMediaService(env.rpc),
      jobs: IdeProjectService(env.rpc),
      project: 'web',
      canRun: () => true,
      isActive: () => true,
      linkReady: () => ready,
      frameInterval: _ms,
    );
    await c.load();
    await _wait(5);
    expect(frames(), 0);
    ready = true;
    c.resume();
    await _wait(5);
    expect(frames(), greaterThan(0));
  });

  test('huỷ vân tay khi mở phiên thì nhả nút, không kẹt "Đang mở…"', () async {
    var steps = 0;
    env = IdeRpcEnv(
      (op, a) => switch (op) {
        'appscreen.check' => {'ok': true, 'run': true},
        'appscreen.status' => _status(state: 'stopped'),
        'appscreen.run' => ideFakeSilent,
        _ => null,
      },
      ops: const ['jobs.tail'],
      step: (r) async {
        steps++;
        return null; // người dùng bấm Huỷ ở bảng vân tay
      },
    );
    await env.up();
    c = IdeAppScreenController(
      media: IdeMediaService(env.rpc),
      jobs: IdeProjectService(env.rpc),
      project: 'web',
      canRun: () => true,
      isActive: () => true,
      frameInterval: _ms,
      jobPoll: const Duration(milliseconds: 5),
    );
    await c.load();
    final done = c.run(device: 'iphone', dark: false);
    await _wait(2);
    expect(c.running, isTrue);
    final req = env.lastSocket!
        .sentOfType('op')
        .lastWhere((f) => f['op'] == 'appscreen.run')['req'];
    env.lastSocket!.emit({
      'type': 'need_step',
      'req': req,
      'challenge': 'Y2g=',
      'summary': 'Mở màn hình app',
    });
    await done;
    expect(steps, 1);
    expect(c.running, isFalse);
  });
}
