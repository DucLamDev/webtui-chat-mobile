import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_mobile_scaffold.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/design_system/tokens/webtui_density.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool showAppBar}) {
    return tester.pumpWidget(
      MaterialApp(
        home: WebTuiMobileScaffold(
          title: 'WebTui Chat · Tin nhắn',
          showAppBar: showAppBar,
          selectedTab: 0,
          onTabSelected: (_) {},
          body: const Text('than'),
        ),
      ),
    );
  }

  testWidgets('mặc định có thanh tiêu đề', (tester) async {
    await pump(tester, showAppBar: true);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('WebTui Chat · Tin nhắn'), findsOneWidget);
  });

  testWidgets('showAppBar false: bỏ thanh tiêu đề, giữ thanh tab dưới', (
    tester,
  ) async {
    await pump(tester, showAppBar: false);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('WebTui Chat · Tin nhắn'), findsNothing);
    expect(find.byType(WebTuiFloatingTabBar), findsOneWidget);
    expect(find.text('than'), findsOneWidget);
  });

  testWidgets('thanh tab nổi: 4 tab, đổi tab, nổi cách mép và không che thân', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => WebTuiMobileScaffold(
            title: 't',
            selectedTab: selected,
            onTabSelected: (index) => setState(() => selected = index),
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 60, child: Text('dong $i')),
              ],
            ),
          ),
        ),
      ),
    );
    for (final label in ['Tin nhắn', 'Bạn bè', 'Công việc', 'Cài đặt']) {
      expect(find.text(label), findsOneWidget);
    }
    final pill = tester.getRect(
      find.byKey(const ValueKey('floating-tab-bar-pill')),
    );
    expect(844 - pill.bottom, greaterThanOrEqualTo(12), reason: 'nổi cách mép');
    expect(pill.left, greaterThanOrEqualTo(12));
    expect(390 - pill.right, greaterThanOrEqualTo(12));
    // Thanh nổi đè lên thân (extendBody): danh sách chạy tới đáy màn hình,
    // nội dung cuộn ra phía sau thanh mờ.
    final list = tester.getRect(find.byType(ListView));
    expect(list.bottom, 844);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isTrue);
    // Cuộn tới cuối: dòng cuối vẫn nằm trên thanh, không bị che.
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('dong 39')).bottom,
      lessThanOrEqualTo(pill.top),
    );

    await tester.tap(find.text('Công việc'));
    await tester.pump();
    expect(selected, 2);
    await tester.tap(find.byKey(const ValueKey('tab-Cài đặt')));
    await tester.pump();
    expect(selected, 3);
  });

  testWidgets('chữ lớn 1.3 và nền tối: thanh tab không tràn', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: WebTuiMobileScaffold(
          title: 't',
          selectedTab: 1,
          onTabSelected: (_) {},
          body: const SizedBox.shrink(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'biểu tượng Lucide, mục chọn nền xanh nhạt, số chưa đỏ ở Tin nhắn',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: WebTuiTheme.light(),
          home: WebTuiMobileScaffold(
            title: 't',
            selectedTab: 2,
            tabBadges: const {0: 5, 1: 120},
            onTabSelected: (_) {},
            body: const SizedBox.shrink(),
          ),
        ),
      );
      for (final icon in [
        WebTuiIcons.messages,
        WebTuiIcons.friends,
        WebTuiIcons.work,
        WebTuiIcons.settings,
      ]) {
        expect(find.byIcon(icon), findsOneWidget);
      }
      // Số chưa đọc nằm ở góc biểu tượng, màu đỏ; quá 99 thì rút gọn.
      final badges = find.byKey(const ValueKey('tab-badge'));
      expect(badges, findsNWidgets(2));
      expect(find.text('5'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      final decoration =
          tester.widget<Container>(badges.first).decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFE5484D));
      // Mục đang chọn: nền xanh nhạt, chữ và biểu tượng xanh.
      final selected = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('tab-Công việc')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        (selected.decoration! as BoxDecoration).color,
        WebTuiColors.primarySoft,
      );
      final text = tester.widget<Text>(find.text('Công việc'));
      expect(text.style!.color, WebTuiColors.primary);
      // Không có số thì không hiện chấm.
      await tester.pumpWidget(
        MaterialApp(
          home: WebTuiMobileScaffold(
            title: 't',
            selectedTab: 0,
            onTabSelected: (_) {},
            body: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('tab-badge')), findsNothing);
    },
  );

  testWidgets('kiểu Telegram: kính mờ bo 30, nền sáng / tối, vùng bấm ≥ 44', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<BoxDecoration> pumpTheme(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: WebTuiMobileScaffold(
            title: 't',
            selectedTab: 0,
            tabBadges: const {0: 3},
            onTabSelected: (_) {},
            body: const SizedBox.shrink(),
          ),
        ),
      );
      // Đổi theme có hiệu ứng chuyển màu: chờ xong.
      await tester.pumpAndSettle();
      final pill = find.byKey(const ValueKey('floating-tab-bar-pill'));
      expect(
        find.descendant(of: pill, matching: find.byType(BackdropFilter)),
        findsOneWidget,
      );
      final clip = tester.widget<ClipRRect>(
        find.descendant(of: pill, matching: find.byType(ClipRRect)),
      );
      expect(
        clip.borderRadius,
        BorderRadius.circular(WebTuiBottomTabTokens.radius),
      );
      // Bóng nằm ngoài lớp cắt bo góc.
      final shadow =
          tester.widget<DecoratedBox>(pill).decoration as BoxDecoration;
      expect(shadow.boxShadow, isNotEmpty);
      // Nền trong suốt một phần để thấy nội dung mờ phía sau.
      final fill =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(BackdropFilter),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(fill.color!.a, lessThan(0.9));
      expect(fill.border, isNotNull);
      // Mỗi mục bấm được trong ô ≥ 44 điểm.
      for (final label in ['Tin nhắn', 'Bạn bè', 'Công việc', 'Cài đặt']) {
        final size = tester.getSize(find.byKey(ValueKey('tab-$label')));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      expect(find.byKey(const ValueKey('tab-badge')), findsOneWidget);
      return fill;
    }

    final light = await pumpTheme(WebTuiTheme.light());
    expect(light.color, WebTuiColors.surface.withValues(alpha: 0.85));
    final dark = await pumpTheme(ThemeData.dark());
    // Nền tối: xám đen mờ, không dùng nền trắng của nền sáng.
    expect(dark.color!.a, lessThan(0.9));
    expect(dark.color!.computeLuminance(), lessThan(0.05));
    final darkLabel = tester.widget<Text>(find.text('Tin nhắn'));
    final darkOther = tester.widget<Text>(find.text('Bạn bè'));
    expect(darkLabel.style!.color, isNot(darkOther.style!.color));
  });

  for (final (name, platform, inset, gap) in [
    ('iPhone thanh home 34', TargetPlatform.iOS, 34.0, 22.0),
    ('Android cử chỉ 24', TargetPlatform.android, 24.0, 24.0),
    ('Android 3 nút 48', TargetPlatform.android, 48.0, 48.0),
    ('không vùng an toàn', TargetPlatform.android, 0.0, 14.0),
  ]) {
    testWidgets('$name: thanh nằm trên vùng an toàn, thân đệm đáy đủ', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(bottom: inset);
      tester.view.viewPadding = FakeViewPadding(bottom: inset);
      addTearDown(tester.view.reset);
      late double bodyBottomPadding;
      await tester.pumpWidget(
        MaterialApp(
          theme: WebTuiTheme.light().copyWith(platform: platform),
          home: WebTuiMobileScaffold(
            title: 't',
            selectedTab: 0,
            onTabSelected: (_) {},
            body: Builder(
              builder: (context) {
                bodyBottomPadding = WebTuiFloatingTabBar.contentBottomPadding(
                  context,
                );
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      final pill = tester.getRect(
        find.byKey(const ValueKey('floating-tab-bar-pill')),
      );
      // Khoảng dưới thanh chỉ vừa vùng an toàn (iPhone bớt phần thừa trên
      // thanh home), không đè thanh home / nút hệ thống.
      expect(844 - pill.bottom, gap);
      expect(pill.height, WebTuiBottomTabTokens.height);
      // Thân biết thanh chiếm bao nhiêu: hằng chiều cao thanh + khoảng dưới.
      expect(bodyBottomPadding, WebTuiBottomTabTokens.reservedHeight(gap));
      expect(bodyBottomPadding, greaterThanOrEqualTo(844 - pill.top));
    });
  }
}
