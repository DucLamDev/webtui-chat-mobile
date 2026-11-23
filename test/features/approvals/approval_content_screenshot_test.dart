import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_avatar.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/approvals/data/datasources/approval_remote_data_source.dart';
import 'package:webtui_chat/features/approvals/presentation/screens/approval_detail_screen.dart';

import '../../support/system_font.dart';

/// Ảnh chụp màn chi tiết phê duyệt có khối nội dung (sáng / tối, cỡ chữ 1.0 /
/// 1.6) để xem bằng mắt. Ảnh ghi vào `build/approval_shots/` (không commit);
/// test chỉ kiểm không có lỗi vẽ / tràn chữ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadSystemRobotoForTests();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  const size = Size(390, 1500);
  late final Uint8List logo;
  setUpAll(() async {
    logo = await File('assets/branding/logo_webtui.png').readAsBytes();
  });
  const dir = 'build/approval_shots';

  final approval = approvalFromMap({
    'id': 'a1',
    'status': 'pending',
    'title': 'Duyệt bài Facebook · Khuyến mãi tháng 12',
    'action': 'post.publish',
    'source': 'bot',
    'required_approvals': 1,
    'approvals_count': 0,
    'can_decide': true,
    'created_at': '2026-11-23T02:00:00Z',
    'expires_at': '2026-11-30T02:00:00Z',
    'display': {
      'text':
          'Tháng 12 rộn ràng, giảm 30% cho mọi gói VPS!\n\n'
          'Đăng ký trước ngày 31/12 để nhận thêm 1 tháng sử dụng miễn phí.\n'
          '#khuyenmai #vps',
      'image_url': 'https://media.example.com/a.jpg',
      'fields': [
        {'label': 'Kênh', 'value': 'Facebook'},
        {'label': 'Tài khoản', 'value': 'Trang chính thức'},
        {'label': 'Giờ đăng', 'value': 'Ngay khi duyệt'},
        {'label': 'AI duyệt', 'value': 'Đạt'},
      ],
      'link': {'label': 'Mở trang gốc', 'url': 'https://app.example.com/p/1'},
    },
  });

  Future<void> save(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  for (final b in Brightness.values) {
    for (final scale in const [1.0, 1.6]) {
      final tag = '${b.name}-${scale == 1.0 ? '1x' : '1_6x'}';
      testWidgets('chụp chi tiết phê duyệt có nội dung ($tag)', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        WebTuiColors.apply(b);
        final key = GlobalKey();
        final base = b == Brightness.dark
            ? WebTuiTheme.dark()
            : WebTuiTheme.light();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: _withRoboto(base),
              builder: (context, inner) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: inner!,
              ),
              home: Scaffold(
                backgroundColor: WebTuiColors.background,
                appBar: AppBar(title: const Text('Chi tiết phê duyệt')),
                body: WebTuiAvatarNetworkScope(
                  apiBaseUri: Uri.parse('https://chat.example'),
                  // Cỡ chữ 1.0: ảnh tải được; 1.6: ảnh lỗi (xem ô báo lỗi).
                  loadBytes:
                      (uri, {required maxBytes, required allowPublicRequest}) =>
                          Future<Uint8List?>.value(scale == 1.0 ? logo : null),
                  child: ApprovalDetailView(
                    approval: approval,
                    onOpenLink: (_) async => true,
                    onDecide: (_, _) async {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();
        await save(tester, key, 'approval-content-$tag');
        expect(tester.takeException(), isNull);
        WebTuiColors.apply(Brightness.light);
      });
    }
  }
}

/// Nút Material lấy `labelLarge` (app không đặt) nên trong test rơi về phông
/// thử nghiệm; gán Roboto cho cả bộ chữ và các nút để ảnh chụp đọc được.
ThemeData _withRoboto(ThemeData base) {
  ButtonStyle fix(ButtonStyle? style) {
    if (style == null) return _roboto;
    return style.copyWith(
      textStyle: WidgetStateProperty.resolveWith(
        (states) => (style.textStyle?.resolve(states) ?? const TextStyle())
            .copyWith(fontFamily: 'Roboto'),
      ),
    );
  }

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: fix(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: fix(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: fix(base.textButtonTheme.style),
    ),
  );
}

const _roboto = ButtonStyle(
  textStyle: WidgetStatePropertyAll(TextStyle(fontFamily: 'Roboto')),
);
