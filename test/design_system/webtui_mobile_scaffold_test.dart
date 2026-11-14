import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_mobile_scaffold.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';

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
    final bar = tester.getRect(find.byType(WebTuiFloatingTabBar));
    final pill = tester.getRect(
      find
          .descendant(
            of: find.byType(WebTuiFloatingTabBar),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(844 - pill.bottom, greaterThanOrEqualTo(12), reason: 'nổi cách mép');
    expect(pill.left, greaterThanOrEqualTo(12));
    // Thân kết thúc phía trên thanh: nội dung cuối cuộn tới không bị che.
    final list = tester.getRect(find.byType(ListView));
    expect(list.bottom, lessThanOrEqualTo(bar.top + 0.5));

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
}
