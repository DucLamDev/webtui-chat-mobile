import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/incoming_call_view.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child,
    ),
  ),
);

/// Màn điện thoại thật (mặc định 390 × 844, như iPhone 14).
void _phone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('gọi 1-1: tên người gọi lớn, loại cuộc gọi, Trả lời / Từ chối', (
    tester,
  ) async {
    _phone(tester);
    var accepted = 0;
    var declined = 0;
    await tester.pumpWidget(
      _host(
        IncomingCallView(
          name: 'Trần Thu Hà',
          gender: 'female',
          isVideo: false,
          onAccept: () => accepted++,
          onDecline: () => declined++,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('incoming_call_name')), findsOneWidget);
    expect(find.text('Trần Thu Hà'), findsOneWidget);
    expect(find.text('Cuộc gọi thoại đến'), findsOneWidget);
    expect(find.text('đang gọi cho bạn'), findsOneWidget);
    expect(find.text('Trả lời'), findsOneWidget);
    expect(find.text('Từ chối'), findsOneWidget);
    // Không truyền Nhắn tin / Tắt chuông thì không hiện.
    expect(find.byKey(const Key('incoming_call_message')), findsNothing);
    expect(find.byKey(const Key('incoming_call_silence')), findsNothing);

    await tester.tap(find.byKey(const Key('incoming_call_accept')));
    await tester.tap(find.byKey(const Key('incoming_call_decline')));
    expect(accepted, 1);
    expect(declined, 1);
    // Vùng bấm nút chính đủ lớn (72).
    expect(
      tester.getSize(find.byKey(const Key('incoming_call_accept'))).height,
      greaterThanOrEqualTo(72),
    );
  });

  testWidgets(
    'chưa biết tên người gọi thì ghi "Cuộc gọi đến"; video có nhãn riêng',
    (tester) async {
      await tester.pumpWidget(
        _host(
          IncomingCallView(
            name: '  ',
            isVideo: true,
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Cuộc gọi đến'), findsOneWidget);
      expect(find.text('Cuộc gọi video đến'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'Nhắn tin và Tắt chuông; đã tắt chuông thì nút mờ, không bấm lại',
    (tester) async {
      var messages = 0;
      var silences = 0;
      Widget view({required bool silenced}) => _host(
        IncomingCallView(
          name: 'Nam',
          isVideo: false,
          onAccept: () {},
          onDecline: () {},
          onMessage: () => messages++,
          onSilence: () => silences++,
          silenced: silenced,
        ),
      );

      await tester.pumpWidget(view(silenced: false));
      await tester.pump();
      await tester.tap(find.byKey(const Key('incoming_call_message')));
      await tester.tap(find.byKey(const Key('incoming_call_silence')));
      expect(messages, 1);
      expect(silences, 1);
      expect(find.text('Tắt chuông'), findsOneWidget);

      await tester.pumpWidget(view(silenced: true));
      await tester.pump();
      expect(find.text('Đã tắt chuông'), findsOneWidget);
      await tester.tap(find.byKey(const Key('incoming_call_silence')));
      expect(silences, 1);
    },
  );

  testWidgets('gọi nhóm: tên nhóm, ai đang gọi, nhãn cuộc gọi nhóm', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _host(
        IncomingCallView(
          name: 'Nhóm dự án',
          isGroup: true,
          isVideo: false,
          subtitle: 'Nam đang gọi nhóm…',
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nhóm dự án'), findsOneWidget);
    // Dấu "…" cuối câu được thay bằng ba chấm chạy.
    expect(find.text('Nam đang gọi nhóm'), findsOneWidget);
    expect(find.text('Cuộc gọi nhóm thoại'), findsOneWidget);
  });

  testWidgets('máy bật giảm chuyển động: không có hiệu ứng lặp mãi', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _host(
        IncomingCallView(
          name: 'Nam',
          isVideo: false,
          onAccept: () {},
          onDecline: () {},
        ),
        reduceMotion: true,
      ),
    );
    // Có hiệu ứng lặp thì pumpAndSettle sẽ không bao giờ xong.
    await tester.pumpAndSettle();
    expect(find.text('Nam'), findsOneWidget);
  });

  testWidgets(
    'điện thoại màn nhỏ (320 × 568): thu gọn, không tràn, vẫn bấm được',
    (tester) async {
      _phone(tester, size: const Size(320, 568));
      var accepted = 0;
      await tester.pumpWidget(
        _host(
          IncomingCallView(
            name: 'Nguyễn Văn Bình An Khang Thịnh Vượng',
            isVideo: true,
            onAccept: () => accepted++,
            onDecline: () {},
            onMessage: () {},
            onSilence: () {},
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('incoming_call_accept')));
      await tester.tap(find.byKey(const Key('incoming_call_accept')));
      expect(accepted, 1);
    },
  );

  testWidgets('hiệu ứng: màn trượt hiện dần, nút Trả lời lắc như chuông reo', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _host(
        IncomingCallView(
          name: 'Nam',
          isVideo: false,
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );
    double nameOpacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(const Key('incoming_call_name')),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    expect(nameOpacity(), lessThan(1), reason: 'khung đầu còn đang hiện dần');
    await tester.pump(const Duration(milliseconds: 500));
    expect(nameOpacity(), 1);

    Matrix4 iconTransform() => tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.byIcon(Icons.call_rounded),
                matching: find.byType(Transform),
              )
              .first,
        )
        .transform;
    // Bắt đầu chu kỳ mới rồi lấy khung giữa nhịp lắc.
    await tester.pump(const Duration(milliseconds: 1600 - 500 + 70));
    expect(iconTransform().isIdentity(), isFalse, reason: 'đang lắc');
    // Cuối chu kỳ: nghỉ, không lắc.
    await tester.pump(const Duration(milliseconds: 900));
    expect(iconTransform().isIdentity(), isTrue, reason: 'đang nghỉ');
  });

  testWidgets('giảm chuyển động: hiện ngay, nút không lắc, ba chấm đứng yên', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _host(
        IncomingCallView(
          name: 'Nam',
          isVideo: false,
          onAccept: () {},
          onDecline: () {},
        ),
        reduceMotion: true,
      ),
    );
    await tester.pump();
    expect(
      find.ancestor(
        of: find.byIcon(Icons.call_rounded),
        matching: find.byWidgetPredicate(
          (widget) => widget is Transform && !widget.transform.isIdentity(),
        ),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Nam'), findsOneWidget);
  });
}
