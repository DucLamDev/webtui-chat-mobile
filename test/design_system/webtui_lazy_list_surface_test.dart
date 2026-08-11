import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_list_items.dart';

void main() {
  testWidgets('sliver surface only builds the visible window', (tester) async {
    final builtIndexes = <int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              WebTuiSliverListSurface(
                itemCount: 1000,
                itemBuilder: (context, index) {
                  builtIndexes.add(index);
                  return SizedBox(height: 72, child: Text('row-$index'));
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(builtIndexes.length, lessThan(50));
    expect(find.text('row-999'), findsNothing);
  });

  testWidgets('bounded nested surface does not eagerly build all members', (
    tester,
  ) async {
    final builtIndexes = <int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: WebTuiLazyListSurface(
              itemCount: 1000,
              maxHeight: 300,
              itemBuilder: (context, index) {
                builtIndexes.add(index);
                return SizedBox(height: 72, child: Text('member-$index'));
              },
            ),
          ),
        ),
      ),
    );

    expect(builtIndexes.length, lessThan(50));
    expect(find.text('member-999'), findsNothing);
  });

  testWidgets('bounded grid does not eagerly build all media thumbnails', (
    tester,
  ) async {
    final builtIndexes = <int>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebTuiLazyGridSurface(
            itemCount: 500,
            maxHeight: 320,
            itemBuilder: (context, index) {
              builtIndexes.add(index);
              return ColoredBox(
                color: Colors.blue,
                child: Text('media-$index'),
              );
            },
          ),
        ),
      ),
    );

    expect(builtIndexes.length, lessThan(50));
    expect(find.text('media-499'), findsNothing);
  });
}
