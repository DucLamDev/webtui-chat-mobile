import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_badges.dart';

void main() {
  testWidgets('huy hiệu không bị giãn trong Row cao 72', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 72,
            child: Row(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [WebTuiUnreadBadge(count: 1)],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(WebTuiUnreadBadge));
    expect(size.height, lessThanOrEqualTo(24));
    expect(size.width, greaterThanOrEqualTo(18));
  });
}
