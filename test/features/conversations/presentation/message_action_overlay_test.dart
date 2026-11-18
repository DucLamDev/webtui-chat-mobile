import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/icons/webtui_icons.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_action_overlay.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_media_widgets.dart';

class _Harness extends StatelessWidget {
  const _Harness({required this.onOpen});

  final void Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              key: const ValueKey('open'),
              onPressed: () => onOpen(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }
}

MessageAttachment _attachment(String name, String mime) {
  final createdAt = DateTime.utc(2026, 11, 18);
  return MessageAttachment(
    id: 'a-$name',
    workspaceId: 'w1',
    messageId: 'm1',
    fileId: 'f-$name',
    createdAt: createdAt,
    file: UploadedMessageFile(
      id: 'f-$name',
      name: name,
      mimeType: mime,
      byteSize: 10,
      downloadPath: '/api/v1/workspaces/w1/files/f-$name/download',
      createdAt: createdAt,
    ),
  );
}

void main() {
  late List<String> selected;
  late List<String> reacted;

  List<MessageActionItem> actions() => [
    for (final id in ['reply', 'forward', 'copy', 'pin', 'unsend'])
      MessageActionItem(
        id: id,
        label: 'Nhãn $id',
        icon: WebTuiIcons.reply,
        color: Colors.blue,
        onSelected: () => selected.add(id),
      ),
  ];

  Future<void> open(WidgetTester tester, {bool reactions = true}) async {
    await tester.pumpWidget(
      _Harness(
        onOpen: (context) => showMessageActionOverlay(
          context,
          anchor: const Offset(200, 400),
          isMine: true,
          previewText: 'Xin chào cả nhóm',
          actions: actions(),
          selectedReactions: const {'\u{1F44D}'},
          onReact: reactions ? reacted.add : null,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
  }

  setUp(() {
    selected = [];
    reacted = [];
  });

  testWidgets('hiện thanh cảm xúc, bản xem tin nhắn và lưới thao tác', (
    tester,
  ) async {
    await open(tester);

    expect(find.byKey(const ValueKey('message-quick-reactions')), findsOne);
    for (final emoji in messageQuickReactions) {
      expect(
        find.byKey(ValueKey('message-quick-reaction-$emoji')),
        findsOneWidget,
      );
    }
    expect(find.byKey(const ValueKey('message-action-preview')), findsOne);
    expect(find.text('Xin chào cả nhóm'), findsOneWidget);
    expect(find.byKey(const ValueKey('message-action-grid')), findsOne);
    for (final id in ['reply', 'forward', 'copy', 'pin', 'unsend']) {
      expect(find.byKey(ValueKey('message-action-$id')), findsOneWidget);
      expect(find.text('Nhãn $id'), findsOneWidget);
    }
  });

  testWidgets('nền tối (có viền) vẫn đủ 4 ô trên một hàng', (tester) async {
    WebTuiColors.apply(Brightness.dark);
    addTearDown(() => WebTuiColors.apply(Brightness.light));
    await open(tester);

    final rows = {
      for (final id in ['reply', 'forward', 'copy', 'pin'])
        tester.getTopLeft(find.byKey(ValueKey('message-action-$id'))).dy,
    };
    expect(rows, hasLength(1));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('message-action-unsend'))).dy,
      greaterThan(rows.single),
    );
  });

  testWidgets('máy hẹp 320 pt: thanh cảm xúc thu nhỏ, không tràn', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _Harness(
        onOpen: (context) => showMessageActionOverlay(
          context,
          anchor: const Offset(160, 300),
          isMine: false,
          previewText: 'Xin chào',
          actions: actions(),
          onReact: reacted.add,
          onMoreReactions: () {},
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final bar = tester.getRect(
      find.byKey(const ValueKey('message-quick-reactions')),
    );
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(320));
  });

  testWidgets('bàn phím đang mở thì khối thao tác nằm trên bàn phím', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _Harness(
        onOpen: (context) => showMessageActionOverlay(
          context,
          anchor: const Offset(200, 760),
          isMine: true,
          previewText: 'Tin cuối, sát ô gõ',
          actions: actions(),
          onReact: reacted.add,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    final grid = tester.getRect(
      find.byKey(const ValueKey('message-action-grid')),
    );
    expect(grid.bottom, lessThanOrEqualTo(844 - 336));
  });

  testWidgets('bấm thao tác thì đóng lớp rồi mới chạy thao tác', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('message-action-copy')));
    await tester.pumpAndSettle();

    expect(selected, ['copy']);
    expect(find.byKey(const ValueKey('message-action-grid')), findsNothing);
  });

  testWidgets('bấm cảm xúc thì gửi cảm xúc và đóng', (tester) async {
    await open(tester);
    await tester.tap(
      find.byKey(const ValueKey('message-quick-reaction-\u{1F606}')),
    );
    await tester.pumpAndSettle();

    expect(reacted, ['\u{1F606}']);
    expect(find.byKey(const ValueKey('message-quick-reactions')), findsNothing);
  });

  testWidgets('chạm nền mờ thì đóng, không chạy thao tác nào', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-action-grid')), findsNothing);
    expect(selected, isEmpty);
    expect(reacted, isEmpty);
  });

  testWidgets('kênh chặn chia sẻ (không có onReact) thì ẩn thanh cảm xúc', (
    tester,
  ) async {
    await open(tester, reactions: false);

    expect(find.byKey(const ValueKey('message-quick-reactions')), findsNothing);
    expect(find.byKey(const ValueKey('message-action-grid')), findsOne);
  });

  test('chỉ ảnh (trừ SVG) và video được lưu vào thư viện ảnh', () {
    expect(isGallerySaveable(_attachment('a.jpg', 'image/jpeg')), isTrue);
    expect(isGallerySaveable(_attachment('b.mp4', 'video/mp4')), isTrue);
    expect(isGallerySaveable(_attachment('c.svg', 'image/svg+xml')), isFalse);
    expect(isGallerySaveable(_attachment('d.pdf', 'application/pdf')), isFalse);
  });

  test('tên tệp lưu có đuôi theo loại khi tên gốc thiếu đuôi', () {
    expect(galleryFileName(_attachment('anh', 'image/png')), endsWith('.png'));
    expect(galleryFileName(_attachment('clip', 'video/mp4')), endsWith('.mp4'));
    expect(galleryFileName(_attachment('x.jpeg', 'image/jpeg')), 'x.jpeg');
  });
}
