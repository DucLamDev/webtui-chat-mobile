import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_term_controller.dart';

import 'term_controller_test.dart' show TermRig;

void main() {
  test(
    'máy khác chiếm phiên: taken, KHÔNG tự nối lại; bấm mới gắn bằng name',
    () async {
      final rig = TermRig();
      await rig.live();
      rig.socket.emit({'type': 'ide_closed', 'reason': 'ide_error'});
      await rig.settle(200);
      expect(rig.controller.state.link, IdeTermLink.taken);
      // Không có luồng mới tự mở.
      expect(rig.termSockets, hasLength(1));
      rig.controller.reconnect();
      await rig.settle();
      expect(rig.termSockets, hasLength(2));
      expect(rig.socket.sent.firstWhere((f) => f['type'] == 'term'), {
        'type': 'term',
        'name': 't1',
      });
      await rig.dispose();
    },
  );

  test('đứt mạng (socket) vẫn là lost, không phải taken', () async {
    final rig = TermRig();
    await rig.live();
    await rig.socket.drop();
    await rig.settle(100);
    expect(rig.controller.state.link, IdeTermLink.lost);
    await rig.dispose();
  });
}
