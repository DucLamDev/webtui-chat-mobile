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

  testWidgets('thanh tab nổi: 4 tab, đổi tab, cách mép, không che thân', (
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
    final bar = tester.getRect(find.byKey(const ValueKey('bottom-tab-bar')));
    // Viên thuốc nổi kiểu Telegram: cách hai mép và cách đáy (máy không có
    // vùng an toàn đáy thì cách [WebTuiBottomTabTokens.margin]).
    expect(bar.left, WebTuiBottomTabTokens.sideMargin);
    expect(bar.right, 390 - WebTuiBottomTabTokens.sideMargin);
    expect(bar.bottom, 844 - WebTuiBottomTabTokens.margin);
    expect(bar.height, WebTuiBottomTabTokens.height);
    // Thanh đè lên thân (extendBody): danh sách chạy tới đáy màn hình, nội dung
    // cuộn ra phía sau lớp kính mờ và chạy hai bên viên thuốc.
    final list = tester.getRect(find.byType(ListView));
    expect(list.bottom, 844);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isTrue);
    // Cuộn tới cuối: dòng cuối vẫn nằm trên viên thuốc, không bị che.
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('dong 39')).bottom,
      lessThanOrEqualTo(bar.top),
    );

    await tester.tap(find.text('Công việc'));
    await tester.pump();
    expect(selected, 2);
    await tester.tap(find.byKey(const ValueKey('tab-Cài đặt')));
    await tester.pump();
    expect(selected, 3);
  });

  testWidgets('vùng trong suốt quanh viên thuốc không chặn chạm nội dung', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var bodyTaps = 0;
    var tabTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WebTuiMobileScaffold(
          title: 't',
          selectedTab: 0,
          onTabSelected: (_) => tabTaps++,
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => bodyTaps++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final bar = tester.getRect(find.byKey(const ValueKey('bottom-tab-bar')));
    // Lề trái cạnh viên thuốc và khoảng trống phía dưới: chạm xuống nội dung.
    await tester.tapAt(Offset(bar.left / 2, bar.center.dy));
    await tester.tapAt(Offset(bar.center.dx, (bar.bottom + 844) / 2));
    expect(bodyTaps, 2);
    expect(tabTaps, 0);
  });

  testWidgets('màn rộng: viên thuốc tối đa 520, nằm giữa', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    final bar = tester.getRect(find.byKey(const ValueKey('bottom-tab-bar')));
    expect(bar.width, WebTuiBottomTabTokens.maxWidth);
    expect(bar.center.dx, 512);
  });

  testWidgets('chữ hệ thống ×2 và nền tối: thanh tab không tràn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
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
    'biểu tượng nét khi chưa chọn, đặc + chữ xanh khi chọn, nền viên thuốc dưới '
    'mục chọn, số đỏ',
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
        WebTuiIcons.workActive,
        WebTuiIcons.settings,
      ]) {
        expect(find.byIcon(icon), findsOneWidget);
      }
      expect(find.byIcon(WebTuiIcons.work), findsNothing);
      // Số chưa đọc nằm ở góc biểu tượng, màu đỏ; quá 99 thì rút gọn.
      final badges = find.byKey(const ValueKey('tab-badge'));
      expect(badges, findsNWidgets(2));
      expect(find.text('5'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      final decoration =
          tester.widget<Container>(badges.first).decoration! as BoxDecoration;
      expect(decoration.color, WebTuiColors.badge);
      // Mục đang chọn: chữ xanh nhấn, nền viên thuốc nằm đúng dưới mục đó;
      // mục khác chữ màu chính (đọc rõ trên lớp kính như Telegram).
      final text = tester.widget<Text>(find.text('Công việc'));
      expect(text.style!.color, WebTuiColors.primary);
      expect(
        tester.widget<Text>(find.text('Cài đặt')).style!.color,
        WebTuiColors.textPrimary,
      );
      await tester.pumpAndSettle();
      final pill = tester.getRect(
        find.byKey(const ValueKey('tab-selection-pill')),
      );
      final item = tester.getRect(find.byKey(const ValueKey('tab-Công việc')));
      expect(pill.center.dx, closeTo(item.center.dx, 0.5));
      expect(pill.height, greaterThanOrEqualTo(48));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tab-Công việc')),
          matching: find.byType(AnimatedContainer),
        ),
        findsNothing,
      );
      expect(
        tester.widget<Icon>(find.byIcon(WebTuiIcons.workActive)).size,
        WebTuiBottomTabTokens.iconSize,
      );
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

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  testWidgets('đổi tab: chỉ nút mới có màu, không còn mực / splash', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: WebTuiTheme.light(),
        home: StatefulBuilder(
          builder: (context, setState) => WebTuiMobileScaffold(
            title: 't',
            selectedTab: selected,
            onTabSelected: (index) => setState(() => selected = index),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    final bar = find.byType(WebTuiFloatingTabBar);
    expect(
      find.descendant(of: bar, matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(
      find.descendant(of: bar, matching: find.byType(InkResponse)),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('tab-Tin nhắn')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tab-Bạn bè')));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('tab-Bạn bè'))),
      matchesSemantics(
        label: 'Bạn bè',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        hasEnabledState: false,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('tab-Tin nhắn'))),
      matchesSemantics(
        label: 'Tin nhắn',
        isButton: true,
        isSelected: false,
        hasSelectedState: true,
        hasTapAction: true,
        hasEnabledState: false,
      ),
    );
    // Nền viên thuốc trượt sang tab mới.
    final pill = tester.getRect(
      find.byKey(const ValueKey('tab-selection-pill')),
    );
    final item = tester.getRect(find.byKey(const ValueKey('tab-Bạn bè')));
    expect(pill.center.dx, closeTo(item.center.dx, 0.5));
    // Nút cũ về dạng nét màu chưa chọn; nút mới thành dạng đặc màu nhấn.
    final oldIcon = tester.widget<Icon>(find.byIcon(WebTuiIcons.messages));
    final newIcon = tester.widget<Icon>(find.byIcon(WebTuiIcons.friendsActive));
    expect(oldIcon.color, isNot(newIcon.color));
    expect(find.byIcon(WebTuiIcons.messagesActive), findsNothing);
    expect(
      contrast(oldIcon.color!, Colors.white),
      greaterThanOrEqualTo(4.5),
      reason: 'nhãn chưa chọn đọc rõ trên lớp kính sáng',
    );
    // Vùng bấm đủ lớn.
    expect(
      tester.getSize(find.byKey(const ValueKey('tab-Bạn bè'))).height,
      greaterThanOrEqualTo(48),
    );
    handle.dispose();
  });

  testWidgets('nền tối: nhãn chưa chọn và đang chọn đủ tương phản', (
    tester,
  ) async {
    WebTuiColors.apply(Brightness.dark);
    addTearDown(() => WebTuiColors.apply(Brightness.light));
    await tester.pumpWidget(
      MaterialApp(
        theme: WebTuiTheme.dark(),
        home: WebTuiMobileScaffold(
          title: 't',
          selectedTab: 0,
          onTabSelected: (_) {},
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Đo trên màu kính thật của viên thuốc (kính phủ lên nền trang tối).
    final fill =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('bottom-tab-bar')),
                )
                .decoration
            as BoxDecoration;
    final background = Color.alphaBlend(fill.color!, WebTuiColors.page);
    final idle = tester.widget<Text>(find.text('Bạn bè')).style!.color!;
    expect(contrast(idle, background), greaterThanOrEqualTo(4.5));
    final active = tester.widget<Text>(find.text('Tin nhắn')).style!.color!;
    expect(contrast(active, background), greaterThanOrEqualTo(4.5));
  });

  testWidgets('extendBody: thân chạy xuống sau thanh và nhận đệm đáy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late EdgeInsets bodyPadding;
    await tester.pumpWidget(
      MaterialApp(
        home: WebTuiMobileScaffold(
          title: 't',
          selectedTab: 0,
          onTabSelected: (_) {},
          body: Builder(
            builder: (context) {
              bodyPadding = MediaQuery.paddingOf(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBody, isTrue);
    final bar = tester.getRect(find.byType(WebTuiFloatingTabBar));
    expect(bodyPadding.bottom, greaterThanOrEqualTo(bar.height));
    // Thân phủ tới mép dưới màn hình (không có dải đáy riêng).
    final body = tester.getRect(find.byType(SizedBox).first);
    expect(body.bottom, 844);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets(
    'kiểu Telegram: viên thuốc kính mờ bo tròn, có bóng, kính trong, vùng bấm ≥ 44',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => WebTuiColors.apply(Brightness.light));
      Future<BoxDecoration> pumpTheme(Brightness brightness) async {
        WebTuiColors.apply(brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.dark
                ? WebTuiTheme.dark()
                : WebTuiTheme.light(),
            home: WebTuiMobileScaffold(
              title: 't',
              selectedTab: 0,
              tabBadges: const {0: 3},
              onTabSelected: (_) {},
              body: const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bar = find.byKey(const ValueKey('bottom-tab-bar'));
        expect(
          find.ancestor(of: bar, matching: find.byType(BackdropFilter)),
          findsOneWidget,
        );
        expect(
          find.ancestor(of: bar, matching: find.byType(ClipRRect)),
          findsOneWidget,
        );
        final fill =
            tester.widget<DecoratedBox>(bar).decoration as BoxDecoration;
        // Kính trong (thấy nội dung mờ phía sau), bo tròn hết cỡ.
        expect(fill.color!.a, lessThan(0.8));
        expect(
          fill.borderRadius,
          BorderRadius.circular(WebTuiBottomTabTokens.height / 2),
        );
        // Bóng mềm nằm ngoài lớp cắt bo tròn (không bị cắt mất).
        final shadowed = tester
            .widgetList<DecoratedBox>(
              find.ancestor(of: bar, matching: find.byType(DecoratedBox)),
            )
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .where((decoration) => decoration.boxShadow?.isNotEmpty ?? false);
        expect(shadowed, isNotEmpty);
        // Mỗi mục bấm được trong ô ≥ 44 điểm.
        for (final label in ['Tin nhắn', 'Bạn bè', 'Công việc', 'Cài đặt']) {
          final size = tester.getSize(find.byKey(ValueKey('tab-$label')));
          expect(size.height, greaterThanOrEqualTo(44));
          expect(size.width, greaterThanOrEqualTo(44));
        }
        expect(find.byKey(const ValueKey('tab-badge')), findsOneWidget);
        return fill;
      }

      final light = await pumpTheme(Brightness.light);
      expect(light.color, WebTuiColors.page.withValues(alpha: 0.62));
      final dark = await pumpTheme(Brightness.dark);
      // Nền tối: kính tối (sáng hơn nền trang một bậc), không dùng kính trắng.
      expect(dark.color!.a, lessThan(0.8));
      expect(dark.color!.computeLuminance(), lessThan(0.05));
      expect(
        Color.alphaBlend(dark.color!, WebTuiColors.page).computeLuminance(),
        greaterThan(WebTuiColors.page.computeLuminance()),
      );
      final darkLabel = tester.widget<Text>(find.text('Tin nhắn'));
      final darkOther = tester.widget<Text>(find.text('Bạn bè'));
      expect(darkLabel.style!.color, isNot(darkOther.style!.color));
    },
  );

  for (final (name, platform, inset, gap) in [
    ('iPhone thanh home 34', TargetPlatform.iOS, 34.0, 22.0),
    ('Android cử chỉ 24', TargetPlatform.android, 24.0, 24.0),
    ('Android 3 nút 48', TargetPlatform.android, 48.0, 48.0),
    ('không vùng an toàn', TargetPlatform.android, 0.0, 12.0),
  ]) {
    testWidgets('$name: viên thuốc nổi trên vùng an toàn, thân đệm đáy đủ', (
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
      final bar = tester.getRect(find.byKey(const ValueKey('bottom-tab-bar')));
      // Viên thuốc nổi ngay trên vùng an toàn (iPhone bớt phần thừa trên thanh
      // home), không đè thanh home / nút hệ thống.
      expect(bar.bottom, 844 - gap);
      expect(bar.height, WebTuiBottomTabTokens.height);
      // Thân biết thanh chiếm bao nhiêu: hằng chiều cao thanh + khoảng dưới.
      expect(bodyBottomPadding, WebTuiBottomTabTokens.reservedHeight(gap));
      expect(bodyBottomPadding, greaterThanOrEqualTo(844 - bar.top));
    });
  }
}
