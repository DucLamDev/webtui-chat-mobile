import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_ai_session_controller.dart';
import 'package:webtui_chat/features/ide_mobile/data/ide_channel.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_errors.dart';

import 'ai_session_controller_test.dart' show Rig, stateFrame;

void main() {
  group('chế độ quyền AI điện thoại không được bật', () {
    test('nhận ra configure đổi permissions.mode sang auto', () {
      expect(
        ideAiConfigureBlocked({
          'permissions': {'mode': 'auto'},
        }),
        isTrue,
      );
      expect(
        ideAiConfigureBlocked({
          'permissions': {'mode': ' AUTO '},
        }),
        isTrue,
      );
      for (final ok in [
        null,
        'auto',
        {'model': 'auto'},
        {'permissions': 'auto'},
        {
          'permissions': {'mode': 'ask'},
        },
        {
          'permissions': {'mode': 'plan', 'team': true},
        },
      ]) {
        expect(ideAiConfigureBlocked(ok), isFalse, reason: '$ok');
      }
    });

    test('lớp gửi bỏ khung configure sang auto, khung khác vẫn gửi', () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      rig.socket.emit(stateFrame());
      await rig.settle();

      final blocked = rig.controller.command('configure', {
        'settings': {
          'permissions': {
            'mode': 'auto',
            'tools': <Object?>[],
            'commands': <Object?>[],
          },
        },
      });
      expect(blocked, isFalse);
      rig.controller.configure({
        'permissions': {'mode': 'auto'},
      });
      expect(rig.socket.sentOfType('configure'), isEmpty);

      rig.controller.configure({
        'permissions': {'mode': 'ask'},
      });
      rig.controller.configure({'model': 'opus'});
      expect(rig.socket.sentOfType('configure').length, 2);
      await rig.dispose();
    });
  });

  group('cổng trả not_allowed', () {
    test('mã lỗi riêng, lời cố định', () {
      final e = IdeException.fromCode('not_allowed', 'raw gateway text');
      expect(e, isA<IdeNotAllowed>());
      expect(e.message, 'Thao tác này chưa được mở cho điện thoại.');
    });

    test('stream ai bị từ chối not_allowed thì không tự nối lại', () async {
      final rig = Rig()
        ..failOpen = const IdeHandshakeException(ideNotAllowedReason);
      rig.controller.start();
      await rig.settle(80);
      final snap = rig.controller.state;
      expect(snap.link, IdeAiLink.closed);
      expect(snap.closedReason, 'not_allowed');
      await rig.dispose();
    });

    test('khung error not_allowed hiện lời cố định', () async {
      final rig = Rig();
      rig.controller.start();
      await rig.settle();
      rig.socket.emit(stateFrame());
      rig.socket.emit({
        'type': 'error',
        'code': 'not_allowed',
        'message': 'op blocked',
      });
      await rig.settle();
      expect(
        rig.controller.state.problem?.message,
        'Thao tác này chưa được mở cho điện thoại.',
      );
      await rig.dispose();
    });
  });

  test('trạm đóng stream ai lý do disabled: dừng, không tự nối lại', () async {
    final rig = Rig();
    rig.controller.start();
    await rig.settle();
    rig.socket.emit(stateFrame());
    await rig.settle();
    final before = rig.aiSockets.length;
    rig.socket.emit({'type': 'ide_closed', 'reason': 'disabled'});
    await rig.settle(80);
    expect(rig.controller.state.link, IdeAiLink.closed);
    expect(rig.controller.state.closedReason, 'disabled');
    expect(rig.aiSockets.length, before);
    await rig.dispose();
  });
}
