import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/peer_presence.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/chat_room_app_bar.dart';

/// Đầu phòng chat đo bằng phông chữ thật của app (Roboto đóng gói kèm) để biết
/// tên người có bị cắt "…" trên các khổ điện thoại thường gặp hay không.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final roboto = FontLoader('WebTuiRoboto');
    for (final path in const [
      'assets/fonts/roboto-regular.ttf',
      'assets/fonts/roboto-medium.ttf',
      'assets/fonts/roboto-bold.ttf',
    ]) {
      roboto.addFont(rootBundle.load(path));
    }
    await roboto.load();
  });

  Future<void> pumpHeader(
    WidgetTester tester, {
    required double width,
    required String title,
    bool directChat = true,
  }) async {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: WebTuiTheme.light(),
        home: Scaffold(
          appBar: ChatRoomAppBar(
            title: title,
            noticeBot: false,
            directChat: directChat,
            presence: directChat
                ? const PeerPresenceLabel(text: 'Đang hoạt động', online: true)
                : null,
            memberCount: 12,
            callsEnabled: true,
            onCall: (_) {},
            onSearch: () {},
            onSafety: () {},
            onTools: () {},
            onDetails: () {},
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );
  }

  RenderParagraph titleOf(WidgetTester tester, String title) =>
      tester.renderObject<RenderParagraph>(find.text(title));

  for (final width in const [360.0, 375.0, 390.0]) {
    testWidgets('khổ ${width.toInt()}: tên ba chữ hiện đủ, không bị cắt', (
      tester,
    ) async {
      await pumpHeader(tester, width: width, title: 'Nguyễn Thanh Tiền');

      expect(titleOf(tester, 'Nguyễn Thanh Tiền').didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('đủ chỗ thì giữ chữ 17, thiếu chỗ mới nhỏ dần', (tester) async {
    await pumpHeader(tester, width: 390, title: 'Nguyễn Thanh Tiền');
    expect(titleOf(tester, 'Nguyễn Thanh Tiền').text.style?.fontSize, 17);

    await pumpHeader(tester, width: 360, title: 'Nguyễn Thanh Tiền');
    final narrow = titleOf(tester, 'Nguyễn Thanh Tiền').text.style?.fontSize;
    expect(narrow, lessThan(17));
    expect(narrow, greaterThanOrEqualTo(15));

    await pumpHeader(tester, width: 360, title: 'Hồ Đức Lâm');
    expect(titleOf(tester, 'Hồ Đức Lâm').text.style?.fontSize, 17);
  });

  testWidgets('tên nhóm quá dài: nhỏ tới 15 rồi mới cắt bằng "…"', (
    tester,
  ) async {
    const longName = 'Phòng Kinh doanh và Chăm sóc khách hàng miền Nam';
    await pumpHeader(tester, width: 360, title: longName, directChat: false);

    final paragraph = titleOf(tester, longName);
    expect(paragraph.text.style?.fontSize, 15);
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(find.text('12 thành viên'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chỉ còn hai nút gọi và nút ba gạch, mỗi nút 44 điểm', (
    tester,
  ) async {
    await pumpHeader(tester, width: 375, title: 'Hồ Đức Lâm');

    // Quay lại, gọi thoại, gọi video, ba gạch. Tìm tin, báo cáo / chặn, công
    // cụ làm việc nằm trong menu ba gạch, không còn là nút riêng.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      ),
      findsNWidgets(4),
    );
    expect(find.byIcon(WebTuiIcons.menu), findsOneWidget);
    expect(find.byIcon(WebTuiIcons.more), findsNothing);
    expect(find.byIcon(WebTuiIcons.search), findsNothing);
    expect(find.byIcon(WebTuiIcons.shieldCheck), findsNothing);
    expect(find.byIcon(WebTuiIcons.work), findsNothing);
    for (final key in const [
      'chat_room_back',
      'chat_room_call_audio',
      'chat_room_call_video',
      'chat_room_more_menu',
    ]) {
      expect(
        tester.getSize(find.byKey(Key(key))),
        const Size.square(44),
        reason: key,
      );
    }
  });

  testWidgets('nền sáng: thanh trắng liền mạch, không phải thanh xanh đặc', (
    tester,
  ) async {
    await pumpHeader(tester, width: 375, title: 'Hồ Đức Lâm');

    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.backgroundColor, WebTuiColors.surface);
    expect(bar.backgroundColor, isNot(WebTuiColors.primary));
    expect(bar.flexibleSpace, isNull);
    // Chữ / nút quay lại màu chữ chính, nút gọi / ≡ màu xanh chính; icon thanh
    // trạng thái hệ thống tối để thấy trên nền trắng.
    expect(bar.foregroundColor, WebTuiColors.textPrimary);
    expect(bar.actionsIconTheme?.color, WebTuiColors.primary);
    expect(bar.systemOverlayStyle?.statusBarIconBrightness, Brightness.dark);
  });
}
