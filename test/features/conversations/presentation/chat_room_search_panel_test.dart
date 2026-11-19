import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/chat_room_controller.dart';

import 'chat_room_body_harness.dart';

void main() {
  testWidgets('tìm trên máy không thấy: báo rõ và có nút tìm trên máy chủ', (
    tester,
  ) async {
    var serverSearches = 0;
    await pumpChatRoom(
      tester,
      messages: [harnessText('m1', 'chào', mine: false, at: harnessTime(8, 0))],
      editState: (state) => state.copyWith(
        searchQuery: 'họp',
        searchSource: MessageSearchSource.device,
      ),
      onSearchOnServer: () => serverSearches++,
    );

    expect(find.text('Không thấy trong tin đã lưu trên máy.'), findsOneWidget);
    await tester.tap(find.text('Tìm thêm trên máy chủ'));
    expect(serverSearches, 1);
  });

  testWidgets('có kết quả trên máy: vẫn có nút tìm thêm, không báo rỗng', (
    tester,
  ) async {
    final hit = harnessText(
      'm1',
      'Họp sáng',
      mine: false,
      at: harnessTime(8, 0),
    );
    await pumpChatRoom(
      tester,
      messages: [hit],
      editState: (state) => state.copyWith(
        searchQuery: 'họp',
        searchResults: [hit],
        searchSource: MessageSearchSource.device,
      ),
      onSearchOnServer: () {},
    );

    expect(find.text('Tìm thêm trên máy chủ'), findsOneWidget);
    expect(find.text('Không thấy trong tin đã lưu trên máy.'), findsNothing);
  });

  testWidgets('đang tìm trên máy chủ: hiện trạng thái, ẩn nút', (tester) async {
    await pumpChatRoom(
      tester,
      messages: const [],
      editState: (state) => state.copyWith(
        searchQuery: 'họp',
        searchSource: MessageSearchSource.device,
        isSearchingServer: true,
      ),
      onSearchOnServer: () {},
    );

    expect(find.text('Đang tìm trên máy chủ...'), findsOneWidget);
    expect(find.text('Tìm thêm trên máy chủ'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('tìm trên máy chủ lỗi: hiện lỗi và nút thử lại', (tester) async {
    await pumpChatRoom(
      tester,
      messages: const [],
      editState: (state) => state.copyWith(
        searchQuery: 'họp',
        searchSource: MessageSearchSource.device,
        searchServerError: 'Không kết nối được máy chủ.',
      ),
      onSearchOnServer: () {},
    );

    expect(find.text('Không kết nối được máy chủ.'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('đã gộp kết quả máy chủ: không còn nút tìm thêm', (tester) async {
    await pumpChatRoom(
      tester,
      messages: const [],
      editState: (state) => state.copyWith(
        searchQuery: 'họp',
        searchSource: MessageSearchSource.deviceAndServer,
      ),
      onSearchOnServer: () {},
    );

    expect(find.text('Tìm thêm trên máy chủ'), findsNothing);
  });

  testWidgets('chưa kết nối được máy chủ: báo nhẹ, vẫn hiện tin', (
    tester,
  ) async {
    await pumpChatRoom(
      tester,
      messages: [
        harnessText('m1', 'tin đã lưu', mine: false, at: harnessTime(8, 0)),
      ],
      editState: (state) => state.copyWith(
        syncNotice: 'Chưa kết nối được máy chủ, đang hiện tin đã lưu trên máy.',
      ),
    );

    expect(
      find.text('Chưa kết nối được máy chủ, đang hiện tin đã lưu trên máy.'),
      findsOneWidget,
    );
    expect(find.text('tin đã lưu', findRichText: true), findsOneWidget);
  });
}
