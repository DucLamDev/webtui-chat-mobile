import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/qr_scanner_screen.dart';

// iPhone 14 Pro: 393 x 852, tai thỏ 59, thanh home 34.
const _phone = Size(393, 852);
const _phonePadding = EdgeInsets.only(top: 59, bottom: 34);

void main() {
  group('qrScanFrameRect', () {
    test('khung lớn, vuông, nằm giữa màn điện thoại', () {
      final frame = qrScanFrameRect(_phone, _phonePadding);

      expect(frame.width, frame.height);
      expect(frame.width, greaterThanOrEqualTo(_phone.width * 0.7));
      expect(frame.center.dx, closeTo(_phone.width / 2, 0.01));
      expect(frame.top, greaterThanOrEqualTo(_phonePadding.top + 64));
      final centerRatio = frame.center.dy / _phone.height;
      expect(centerRatio, inInclusiveRange(0.38, 0.52));
    });

    test('máy nhỏ (iPhone SE) vẫn có khung đủ lớn và nằm trong màn', () {
      const size = Size(375, 667);
      const padding = EdgeInsets.only(top: 20);
      final frame = qrScanFrameRect(size, padding);

      expect(frame.width, greaterThanOrEqualTo(240));
      expect(frame.top, greaterThanOrEqualTo(padding.top + 64));
      expect(frame.bottom, lessThan(size.height - 132));
    });

    test('máy tính bảng: khung không quá 320', () {
      final frame = qrScanFrameRect(
        const Size(820, 1180),
        const EdgeInsets.only(top: 24, bottom: 20),
      );
      expect(frame.width, 320);
      expect(frame.center.dx, 410);
    });
  });

  test('lời báo lỗi quyền camera chỉ cách bật trong Cài đặt', () {
    expect(
      qrScannerErrorMessage(MobileScannerErrorCode.permissionDenied),
      contains('Cài đặt'),
    );
    expect(
      qrScannerErrorMessage(MobileScannerErrorCode.unsupported),
      contains('không hỗ trợ'),
    );
    expect(
      qrScannerErrorMessage(MobileScannerErrorCode.genericError),
      isNotEmpty,
    );
  });

  group('QrScannerLayout', () {
    testWidgets('camera và khung quét phủ cả màn hình, không dồn lên đỉnh', (
      tester,
    ) async {
      _usePhone(tester);
      var closed = 0;
      var toggled = 0;
      await tester.pumpWidget(
        _host(
          QrScannerLayout(
            preview: const ColoredBox(
              key: Key('preview'),
              color: Colors.blueGrey,
            ),
            title: 'Quét mã đăng nhập',
            hint: 'Hướng camera vào mã QR.',
            torchState: TorchState.off,
            onClose: () => closed++,
            onToggleTorch: () => toggled++,
            onRetry: () {},
          ),
        ),
      );
      await tester.pump();

      final preview = tester.getRect(find.byKey(const Key('preview')));
      expect(preview.size, _phone);

      final frame = tester.getRect(find.byKey(const Key('qr_scanner_frame')));
      expect(
        frame,
        rectMoreOrLessEquals(qrScanFrameRect(_phone, _phonePadding)),
      );
      expect(frame.center.dy, greaterThan(_phone.height * 0.38));

      final title = tester.getRect(find.byKey(const Key('qr_scanner_title')));
      expect(title.top, greaterThanOrEqualTo(_phonePadding.top));
      expect(title.bottom, lessThan(frame.top));

      final hint = tester.getRect(find.byKey(const Key('qr_scanner_hint')));
      expect(hint.top, greaterThan(frame.bottom));

      final torch = tester.getRect(find.byKey(const Key('qr_scanner_torch')));
      expect(torch.top, greaterThan(hint.bottom));
      expect(torch.bottom, lessThan(_phone.height - _phonePadding.bottom));
      expect(find.text('Đèn pin'), findsOneWidget);

      await tester.tap(find.byKey(const Key('qr_scanner_torch')));
      await tester.tap(find.byKey(const Key('qr_scanner_close')));
      expect(toggled, 1);
      expect(closed, 1);
    });

    testWidgets('đèn đang bật thì nút ghi Tắt đèn', (tester) async {
      _usePhone(tester);
      await tester.pumpWidget(_host(_layout(torchState: TorchState.on)));
      await tester.pump();

      expect(find.text('Tắt đèn'), findsOneWidget);
      expect(find.byTooltip('Tắt đèn pin'), findsOneWidget);
    });

    testWidgets('máy không có đèn thì nút đèn không bấm được', (tester) async {
      _usePhone(tester);
      var toggled = 0;
      await tester.pumpWidget(
        _host(
          _layout(
            torchState: TorchState.unavailable,
            onToggleTorch: () => toggled++,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('qr_scanner_torch')));
      expect(toggled, 0);
    });

    testWidgets('lỗi camera: hiện lời báo + Thử lại, ẩn khung quét', (
      tester,
    ) async {
      _usePhone(tester);
      var retried = 0;
      await tester.pumpWidget(
        _host(
          _layout(
            errorMessage: 'Ứng dụng chưa được phép dùng camera.',
            onRetry: () => retried++,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Không mở được camera'), findsOneWidget);
      expect(find.text('Ứng dụng chưa được phép dùng camera.'), findsOneWidget);
      expect(find.byKey(const Key('qr_scanner_frame')), findsNothing);
      expect(find.byKey(const Key('qr_scanner_close')), findsOneWidget);

      await tester.tap(find.byKey(const Key('qr_scanner_retry')));
      expect(retried, 1);
    });

    testWidgets('tắt hiệu ứng chuyển động thì không chạy vạch quét', (
      tester,
    ) async {
      _usePhone(tester);
      await tester.pumpWidget(_host(_layout(), disableAnimations: true));
      await tester.pump();

      expect(find.byKey(const Key('qr_scanner_sweep')), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}

void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = _phone * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(
    top: _phonePadding.top * 3,
    bottom: _phonePadding.bottom * 3,
  );
  addTearDown(tester.view.reset);
}

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: app!,
    ),
    home: Scaffold(backgroundColor: Colors.black, body: child),
  );
}

QrScannerLayout _layout({
  TorchState torchState = TorchState.off,
  String? errorMessage,
  VoidCallback? onToggleTorch,
  VoidCallback? onRetry,
}) {
  return QrScannerLayout(
    preview: const ColoredBox(color: Colors.blueGrey),
    title: 'Quét mã QR',
    hint: 'Đưa mã vào khung.',
    torchState: torchState,
    errorMessage: errorMessage,
    onClose: () {},
    onToggleTorch: onToggleTorch ?? () {},
    onRetry: onRetry ?? () {},
  );
}
