import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('avatar-heavy conversation contact and member lists stay lazy', () {
    final home = File(
      'lib/features/conversations/presentation/widgets/conversation_home_views.dart',
    ).readAsStringSync();
    final details = File(
      'lib/features/conversations/presentation/screens/channel_detail_screen.dart',
    ).readAsStringSync();
    final components = File(
      'lib/design_system/components/webtui_list_items.dart',
    ).readAsStringSync();

    expect(home, contains('WebTuiSliverListSurface('));
    expect(home, isNot(contains('for (final contact in contacts)')));
    expect(details, contains('WebTuiLazyListSurface('));
    expect(details, contains('WebTuiLazyGridSurface('));
    expect(details, isNot(contains('shrinkWrap: true')));
    expect(details, isNot(contains('for (final member in state.members)')));
    expect(components, contains('SliverChildBuilderDelegate('));
    expect(components, contains('ListView.builder('));
  });
}
