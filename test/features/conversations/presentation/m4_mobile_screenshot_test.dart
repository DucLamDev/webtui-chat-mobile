import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/design_system/tokens/webtui_spacing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadBundledFonts);

  testWidgets('chụp màn phone M4 Tin nhắn', (tester) async {
    await _capture(
      tester: tester,
      size: const Size(390, 844),
      outputPath: 'test/screenshots/phase_m4_phone.png',
      child: const _PhoneMessagesPreview(),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('chụp màn tablet M4 list-detail', (tester) async {
    await _capture(
      tester: tester,
      size: const Size(1024, 768),
      outputPath: 'test/screenshots/phase_m4_tablet.png',
      child: const _TabletListDetailPreview(),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('chụp màn phone M4 chat box', (tester) async {
    await _capture(
      tester: tester,
      size: const Size(390, 844),
      outputPath: 'test/screenshots/phase_m4_chat_phone.png',
      child: const _PhoneChatPreview(),
    );

    expect(tester.takeException(), isNull);
  });
}

Future<void> _loadBundledFonts() async {
  final textLoader = FontLoader('WebTuiRoboto');
  for (final path in const [
    'assets/fonts/roboto-regular.ttf',
    'assets/fonts/roboto-medium.ttf',
    'assets/fonts/roboto-bold.ttf',
  ]) {
    textLoader.addFont(rootBundle.load(path));
  }
  final iconLoader = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  final cupertinoIconLoader =
      FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
  await Future.wait([
    textLoader.load(),
    iconLoader.load(),
    cupertinoIconLoader.load(),
  ]);
}

Future<void> _capture({
  required WidgetTester tester,
  required Size size,
  required String outputPath,
  required Widget child,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: WebTuiTheme.light(),
        home: child,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 250));

  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(outputPath).parent.create(recursive: true);
    await File(outputPath).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

class _PhoneMessagesPreview extends StatelessWidget {
  const _PhoneMessagesPreview();

  @override
  Widget build(BuildContext context) {
    return WebTuiMobileScaffold(
      title: 'WebTui',
      selectedTab: 0,
      onTabSelected: (_) {},
      leading: const IconButton(
        tooltip: 'Tài khoản',
        onPressed: _noopAction,
        icon: Icon(CupertinoIcons.person),
      ),
      actions: const [
        IconButton(
          tooltip: 'Tạo hội thoại',
          onPressed: _noopAction,
          icon: Icon(CupertinoIcons.square_pencil),
        ),
      ],
      floatingActionButton: const FloatingActionButton(
        onPressed: _noopAction,
        child: Icon(CupertinoIcons.chat_bubble_2),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: WebTuiSpacing.lg),
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
            ),
            child: WebTuiSearchBar(hintText: 'Tìm hội thoại...'),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: WebTuiSegmentedTabs(
              tabs: ['Tất cả', 'Chưa đọc', 'Yêu thích'],
              selectedIndex: 0,
              onChanged: _noop,
            ),
          ),
          SizedBox(height: WebTuiSpacing.xs),
          WebTuiListSurface(
            children: [
              WebTuiConversationListItem(
                title: 'Lam Đức',
                preview: 'Báo cáo hôm nay đã sẵn sàng',
                timeLabel: '16:09',
                avatarLabel: 'Lam Đức',
                unreadCount: 3,
                status: WebTuiPresenceStatus.online,
              ),
              WebTuiConversationListItem(
                title: 'Hoang Nguyen',
                preview: 'xin',
                timeLabel: '12:21',
                avatarLabel: 'Hoang Nguyen',
                unreadCount: 1,
              ),
              WebTuiConversationListItem(
                title: 'Bao Tran',
                preview: 'Hen gap luc 15:00',
                timeLabel: 'Hôm qua',
                avatarLabel: 'Bao Tran',
                muted: true,
              ),
              WebTuiConversationListItem(
                title: 'Minh Anh',
                preview: 'Chua co tin nhan',
                timeLabel: '2 ngày',
                avatarLabel: 'Minh Anh',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabletListDetailPreview extends StatelessWidget {
  const _TabletListDetailPreview();

  @override
  Widget build(BuildContext context) {
    return WebTuiMobileScaffold(
      title: 'WebTui',
      selectedTab: 0,
      onTabSelected: (_) {},
      body: Row(
        children: [
          SizedBox(
            width: 360,
            child: ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    WebTuiSpacing.lg,
                    WebTuiSpacing.sm,
                    WebTuiSpacing.lg,
                    WebTuiSpacing.sm,
                  ),
                  child: WebTuiSearchBar(hintText: 'Tìm hội thoại...'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
                  child: WebTuiSegmentedTabs(
                    tabs: ['Tất cả', 'Chưa đọc', 'Yêu thích'],
                    selectedIndex: 0,
                    onChanged: _noop,
                  ),
                ),
                SizedBox(height: WebTuiSpacing.xs),
                WebTuiListSurface(
                  children: [
                    WebTuiConversationListItem(
                      title: 'Kênh & Bot',
                      preview: 'Bot hỗ trợ đang theo dõi yêu cầu',
                      timeLabel: '16:09',
                      avatarLabel: 'Kênh Bot',
                      unreadCount: 2,
                    ),
                    WebTuiConversationListItem(
                      title: 'Kỹ thuật',
                      preview: 'Đã ghim lịch bảo trì tối nay',
                      timeLabel: '12:21',
                      avatarLabel: 'Kỹ thuật',
                    ),
                    WebTuiConversationListItem(
                      title: 'Bàn giao cao',
                      preview: 'Cập nhật biên bản bàn giao',
                      timeLabel: '10:39',
                      avatarLabel: 'Bàn giao cao',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ColoredBox(
              color: WebTuiColors.backgroundMuted,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(WebTuiSpacing.lg),
                    child: Row(
                      children: [
                        WebTuiAvatar(
                          label: 'Kênh Bot',
                          icon: Icons.smart_toy_outlined,
                        ),
                        SizedBox(width: WebTuiSpacing.md),
                        Expanded(
                          child: Text(
                            'Kênh & Bot',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(WebTuiSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          WebTuiMessageBubble(
                            text: 'Bot đã ghi nhận yêu cầu hỗ trợ mới.',
                            timeLabel: '09:41',
                            reactions: ['👍 2'],
                          ),
                          SizedBox(height: WebTuiSpacing.sm),
                          WebTuiMessageBubble(
                            text: 'Mình sẽ kiểm tra và phản hồi trong kênh.',
                            timeLabel: '09:42',
                            outgoing: true,
                            statusLabel: 'Đã gửi',
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    height: 56,
                    color: WebTuiColors.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: WebTuiSpacing.lg,
                      vertical: WebTuiSpacing.sm,
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.sentiment_satisfied_alt_rounded,
                          color: WebTuiColors.primary,
                        ),
                        SizedBox(width: WebTuiSpacing.sm),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: WebTuiColors.backgroundMuted,
                              borderRadius: BorderRadius.all(
                                Radius.circular(24),
                              ),
                              border: Border.fromBorderSide(
                                BorderSide(color: WebTuiColors.border),
                              ),
                            ),
                            child: SizedBox(
                              height: 40,
                              child: Row(
                                children: [
                                  SizedBox(width: WebTuiSpacing.md),
                                  Text(
                                    'Nhập tin nhắn...',
                                    style: TextStyle(
                                      color: WebTuiColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: WebTuiSpacing.sm),
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: WebTuiColors.primary,
                          child: Icon(
                            Icons.send_rounded,
                            size: 19,
                            color: WebTuiColors.textOnPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneChatPreview extends StatelessWidget {
  const _PhoneChatPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTuiColors.chatBackground,
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 0,
        title: const Row(
          children: [
            WebTuiAvatar(label: 'Lâm Đức', size: 34),
            SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Text(
                'Lâm Đức',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: const [
          IconButton(
            onPressed: _noopAction,
            tooltip: 'Chi tiết',
            icon: Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(WebTuiSpacing.lg),
                children: const [
                  Center(
                    child: Text(
                      'Hôm nay',
                      style: TextStyle(
                        color: WebTuiColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  SizedBox(height: WebTuiSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      WebTuiAvatar(label: 'Lâm Đức', size: 30),
                      SizedBox(width: WebTuiSpacing.sm),
                      Expanded(
                        child: WebTuiMessageBubble(
                          text: 'Chào bạn, báo cáo hôm nay đã sẵn sàng.',
                          timeLabel: '16:08',
                          reactions: ['👍'],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: WebTuiSpacing.md),
                  WebTuiMessageBubble(
                    text: 'Mình đã nhận được, cảm ơn bạn nhé.',
                    timeLabel: '16:09',
                    outgoing: true,
                    statusLabel: 'Đã gửi',
                  ),
                ],
              ),
            ),
            const _ComposerPreview(),
          ],
        ),
      ),
    );
  }
}

class _ComposerPreview extends StatelessWidget {
  const _ComposerPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WebTuiColors.surface,
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.md,
        WebTuiSpacing.sm,
        WebTuiSpacing.md,
        WebTuiSpacing.md,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.sentiment_satisfied_alt_rounded,
            color: WebTuiColors.primary,
          ),
          const SizedBox(width: WebTuiSpacing.sm),
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
              decoration: BoxDecoration(
                color: WebTuiColors.backgroundMuted,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: WebTuiColors.border),
              ),
              child: const Row(
                children: [
                  Text(
                    'Nhập tin nhắn...',
                    style: TextStyle(color: WebTuiColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: WebTuiSpacing.sm),
          const CircleAvatar(
            radius: 21,
            backgroundColor: WebTuiColors.primary,
            child: Icon(
              Icons.send_rounded,
              size: 19,
              color: WebTuiColors.textOnPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

void _noop(int _) {}

void _noopAction() {}
