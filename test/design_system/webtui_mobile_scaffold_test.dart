import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_mobile_scaffold.dart';

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
}
