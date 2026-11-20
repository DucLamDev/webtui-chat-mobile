import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_session_state.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/ai/ide_ai_workbar.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ideAiTurnTokens (giống IDE web)', () {
    test('Codex: lấy total.totalTokens', () {
      expect(
        ideAiTurnTokens({
          'total': {'totalTokens': 369500},
          'input': 1,
        }),
        369500,
      );
    });

    test('Claude: vào + ra + tạo bộ nhớ đệm, bỏ phần đọc lại', () {
      expect(
        ideAiTurnTokens({
          'input': 1000,
          'output': 200,
          'created': 50,
          'read': 99999,
        }),
        1250,
      );
    });

    test('thiếu số thì null', () {
      expect(ideAiTurnTokens({}), isNull);
      expect(ideAiTurnTokens({'total': <String, Object?>{}}), isNull);
    });
  });

  group('ideAiContextPercent', () {
    test('tính theo used / window, kẹp 0..100', () {
      expect(ideAiContextPercent({'used': 32000, 'window': 200000}), 16);
      expect(ideAiContextPercent({'used': 300000, 'window': 200000}), 100);
    });

    test('dự phòng percent, không có gì thì null', () {
      expect(ideAiContextPercent({'percent': 41.6}), 42);
      expect(ideAiContextPercent({'used': 10, 'window': 0}), isNull);
      expect(ideAiContextPercent({}), isNull);
    });
  });

  test('ideTokenShort: gọn, dấu phẩy thập phân', () {
    expect(ideTokenShort(950), '950');
    expect(ideTokenShort(12400), '12,4K');
    expect(ideTokenShort(369500), '370K');
    expect(ideTokenShort(2000), '2K');
    expect(ideTokenShort(1200000), '1,2M');
  });

  test('ideAiModeLabel: nhãn như chip chế độ trên web', () {
    expect(ideAiModeLabel('auto'), 'Tự làm (không hỏi)');
    expect(ideAiModeLabel('plan'), 'Lập kế hoạch');
    expect(ideAiModeLabel('plan', team: true), 'Đội AI');
    expect(ideAiModeLabel('lạ'), 'Hỏi trước');
  });

  test('IdeSessionView: startedAt / finishedAt chỉ nhận số dương', () {
    final v = IdeSessionView({'startedAt': 100, 'finishedAt': 0});
    expect(v.startedAt, 100);
    expect(v.finishedAt, isNull);
    expect(IdeSessionView({'startedAt': 'x'}).startedAt, isNull);
  });

  group('IdeAiWorkbar', () {
    testWidgets('chưa chạy lượt nào thì ẩn', (tester) async {
      await tester.pumpWidget(
        _host(const IdeAiWorkbar(busy: false, waiting: false)),
      );
      expect(find.byKey(const Key('ide_ai_workbar')), findsNothing);
    });

    testWidgets('xong: ✓ Đã làm, thời gian m:ss, số token', (tester) async {
      await tester.pumpWidget(
        _host(
          const IdeAiWorkbar(
            busy: false,
            waiting: false,
            startedAt: 1000,
            finishedAt: 1000 + 24 * 60 + 53,
            tokens: 369500,
          ),
        ),
      );
      expect(find.text('Đã làm'), findsOneWidget);
      expect(find.text('24:53'), findsOneWidget);
      expect(find.text('370K token'), findsOneWidget);
    });

    testWidgets('đang chạy: đồng hồ tự tăng, chờ duyệt thì đổi nhãn', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const IdeAiWorkbar(busy: true, waiting: false)),
      );
      expect(find.text('Đang xử lý…'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      // Không có hiệu ứng vô hạn: màn có thể "yên" để test / tiết kiệm pin.
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _host(const IdeAiWorkbar(busy: true, waiting: true)),
      );
      expect(find.text('Chờ bạn xác nhận'), findsOneWidget);
      // Token chỉ hiện khi lượt xong.
      expect(find.textContaining('token'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
