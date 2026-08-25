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

  testWidgets('chụp phone screenshots cho Google Play', (tester) async {
    const playSize = Size(360, 640);
    const playPixelRatio = 3.0;
    const outputDir = 'store/google-play/assets/en-US/phone-screenshots';

    await _capture(
      tester: tester,
      size: playSize,
      pixelRatio: playPixelRatio,
      outputPath: '$outputDir/01-conversations.png',
      child: const _PhoneMessagesPreview(),
    );
    await _capture(
      tester: tester,
      size: playSize,
      pixelRatio: playPixelRatio,
      outputPath: '$outputDir/02-chat-calls-files.png',
      child: const _PhoneCollaborationPreview(),
    );
    await _capture(
      tester: tester,
      size: playSize,
      pixelRatio: playPixelRatio,
      outputPath: '$outputDir/03-contacts.png',
      child: const _PhoneContactsPreview(),
    );
    await _capture(
      tester: tester,
      size: playSize,
      pixelRatio: playPixelRatio,
      outputPath: '$outputDir/04-privacy-settings.png',
      child: const _PhoneSettingsPreview(),
    );
    await _capture(
      tester: tester,
      size: playSize,
      pixelRatio: playPixelRatio,
      outputPath: '$outputDir/05-active-video-call.png',
      child: const _PhoneVideoCallPreview(),
    );
    await _capture(
      tester: tester,
      size: playSize,
      pixelRatio: playPixelRatio,
      outputPath: '$outputDir/06-incoming-call.png',
      child: const _PhoneIncomingCallPreview(),
    );
    await _capture(
      tester: tester,
      size: playSize,
      pixelRatio: playPixelRatio,
      outputPath: '$outputDir/07-channels-workspace.png',
      child: const _PhoneChannelsPreview(),
    );
    await _capture(
      tester: tester,
      size: playSize,
      pixelRatio: playPixelRatio,
      outputPath: '$outputDir/08-safety-controls.png',
      child: const _PhoneSafetyPreview(),
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
  double pixelRatio = 1,
}) async {
  tester.view.physicalSize = Size(
    size.width * pixelRatio,
    size.height * pixelRatio,
  );
  tester.view.devicePixelRatio = pixelRatio;
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
    final image = await boundary.toImage(pixelRatio: pixelRatio);
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

class _PhoneCollaborationPreview extends StatelessWidget {
  const _PhoneCollaborationPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTuiColors.chatBackground,
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 0,
        title: const Row(
          children: [
            WebTuiAvatar(label: 'Nhóm vận hành', size: 34),
            SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Text(
                'Nhóm vận hành',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: const [
          IconButton(
            onPressed: _noopAction,
            tooltip: 'Gọi thoại',
            icon: Icon(CupertinoIcons.phone),
          ),
          IconButton(
            onPressed: _noopAction,
            tooltip: 'Gọi video',
            icon: Icon(CupertinoIcons.video_camera),
          ),
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
                  WebTuiMessageBubble(
                    text: 'Mình đã gửi biên bản họp và lịch triển khai.',
                    timeLabel: '09:06',
                    outgoing: true,
                    statusLabel: 'Đã xem',
                  ),
                  SizedBox(height: WebTuiSpacing.md),
                  _FilePreviewCard(),
                  SizedBox(height: WebTuiSpacing.md),
                  _CallPreviewCard(),
                  SizedBox(height: WebTuiSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      WebTuiAvatar(label: 'Minh Anh', size: 30),
                      SizedBox(width: WebTuiSpacing.sm),
                      Expanded(
                        child: WebTuiMessageBubble(
                          text: 'Đã nhận file. Cả nhóm vào call lúc 10:30 nhé.',
                          timeLabel: '09:12',
                          reactions: ['👍 2'],
                        ),
                      ),
                    ],
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

class _FilePreviewCard extends StatelessWidget {
  const _FilePreviewCard();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 232,
        padding: const EdgeInsets.all(WebTuiSpacing.md),
        decoration: BoxDecoration(
          color: WebTuiColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WebTuiColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.description_outlined, color: WebTuiColors.primary),
            SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'bien-ban-hop.docx',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '36 KB • 09:06',
                    style: TextStyle(
                      color: WebTuiColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallPreviewCard extends StatelessWidget {
  const _CallPreviewCard();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 232,
        decoration: BoxDecoration(
          color: WebTuiColors.primarySoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: WebTuiColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                WebTuiSpacing.md,
                WebTuiSpacing.md,
                WebTuiSpacing.md,
                WebTuiSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cuộc gọi video',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.videocam_outlined,
                        size: 17,
                        color: WebTuiColors.accentGreen,
                      ),
                      SizedBox(width: WebTuiSpacing.xs),
                      Text(
                        '4 phút 37 giây',
                        style: TextStyle(color: WebTuiColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1),
            Padding(
              padding: EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
              child: Center(
                child: Text(
                  'Gọi lại',
                  style: TextStyle(
                    color: WebTuiColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneContactsPreview extends StatelessWidget {
  const _PhoneContactsPreview();

  @override
  Widget build(BuildContext context) {
    return WebTuiMobileScaffold(
      title: 'Bạn bè',
      selectedTab: 1,
      onTabSelected: (_) {},
      leading: const IconButton(
        tooltip: 'Hồ sơ',
        onPressed: _noopAction,
        icon: Icon(CupertinoIcons.person_crop_circle),
      ),
      actions: const [
        IconButton(
          tooltip: 'Thông báo',
          onPressed: _noopAction,
          icon: Icon(CupertinoIcons.bell),
        ),
      ],
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
            child: WebTuiSearchBar(hintText: 'Tìm bạn bè...'),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: WebTuiSegmentedTabs(
              tabs: ['Nội bộ', 'Bạn bè', 'Khám phá'],
              selectedIndex: 1,
              onChanged: _noop,
            ),
          ),
          WebTuiSectionLabel('DANH BẠ'),
          WebTuiListSurface(
            children: [
              WebTuiConversationListItem(
                title: 'Nguyễn Thanh Tiến',
                preview: 'Bạn bè • đang hoạt động',
                timeLabel: '',
                avatarLabel: 'Nguyễn Thanh Tiến',
                status: WebTuiPresenceStatus.online,
                trailing: WebTuiStatusPill(
                  label: 'Bạn bè',
                  color: WebTuiColors.accentGreen,
                ),
              ),
              WebTuiConversationListItem(
                title: 'reviewer1',
                preview: 'Đã gửi lời mời kết bạn',
                timeLabel: '',
                avatarLabel: 'reviewer1',
                trailing: WebTuiStatusPill(
                  label: 'Đang chờ',
                  color: WebTuiColors.accentAmber,
                ),
              ),
              WebTuiConversationListItem(
                title: 'Lam Đức',
                preview: 'Có thể kết bạn trong workspace',
                timeLabel: '',
                avatarLabel: 'Lam Đức',
                trailing: WebTuiStatusPill(
                  label: 'Gửi lời mời',
                  color: WebTuiColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhoneSettingsPreview extends StatelessWidget {
  const _PhoneSettingsPreview();

  @override
  Widget build(BuildContext context) {
    return WebTuiMobileScaffold(
      title: 'Cài đặt',
      selectedTab: 4,
      onTabSelected: (_) {},
      actions: const [
        IconButton(
          tooltip: 'Tìm kiếm',
          onPressed: _noopAction,
          icon: Icon(CupertinoIcons.search),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(bottom: WebTuiSpacing.lg),
        children: const [
          SizedBox(height: WebTuiSpacing.lg),
          Center(
            child: Column(
              children: [
                WebTuiAvatar(label: 'Hồ Đức Lâm', size: 72),
                SizedBox(height: WebTuiSpacing.sm),
                Text(
                  'Hồ Đức Lâm',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          SizedBox(height: WebTuiSpacing.lg),
          WebTuiListSurface(
            children: [
              WebTuiSettingRow(
                title: 'Hồ sơ cá nhân',
                subtitle: 'Cập nhật tên, ảnh đại diện và trạng thái',
                icon: CupertinoIcons.person,
              ),
              WebTuiSettingRow(
                title: 'Quyền riêng tư',
                subtitle: 'Chặn người dùng, báo cáo và xóa tài khoản',
                icon: CupertinoIcons.lock_shield,
              ),
              WebTuiSettingRow(
                title: 'Thông báo',
                subtitle: 'Tin nhắn, cuộc gọi và cảnh báo kênh',
                icon: CupertinoIcons.bell,
                trailing: WebTuiToggle(value: true, onChanged: _noopBool),
              ),
            ],
          ),
          WebTuiSectionLabel('THIẾT LẬP CHUNG'),
          WebTuiListSurface(
            children: [
              WebTuiSliderRow(
                icon: CupertinoIcons.speaker_2,
                value: 0.72,
                onChanged: _noopDouble,
              ),
              WebTuiSettingRow(
                title: 'Phiên đăng nhập',
                subtitle: 'Quản lý thiết bị và bảo mật tài khoản',
                icon: CupertinoIcons.device_phone_portrait,
              ),
              WebTuiSettingRow(
                title: 'Đăng xuất',
                icon: Icons.logout_rounded,
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhoneVideoCallPreview extends StatelessWidget {
  const _PhoneVideoCallPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: Column(
            children: [
              Container(
                height: 54,
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: const Row(
                  children: [
                    WebTuiAvatar(label: 'Nguyễn Thanh Tiến', size: 34),
                    SizedBox(width: WebTuiSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nguyễn Thanh Tiến',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Video call • 04:33',
                            style: TextStyle(
                              color: Color(0xFFB7C4D8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.lock_outline_rounded, color: Color(0xFFB7C4D8)),
                  ],
                ),
              ),
              const SizedBox(height: WebTuiSpacing.lg),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF132338),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              WebTuiAvatar(
                                label: 'Nguyễn Thanh Tiến',
                                size: 88,
                              ),
                              SizedBox(height: WebTuiSpacing.md),
                              Text(
                                'Camera của người nhận',
                                style: TextStyle(
                                  color: Color(0xFFCFD9EA),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: WebTuiSpacing.md,
                      top: WebTuiSpacing.md,
                      child: Container(
                        width: 112,
                        height: 148,
                        decoration: BoxDecoration(
                          color: const Color(0xFF21A875),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 42,
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Bạn',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: WebTuiSpacing.lg),
              const _CallControlsPreview(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneIncomingCallPreview extends StatelessWidget {
  const _PhoneIncomingCallPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              const WebTuiAvatar(label: 'Nhóm vận hành', size: 104),
              const SizedBox(height: WebTuiSpacing.lg),
              const Text(
                'Nhóm vận hành',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: WebTuiSpacing.xs),
              const Text(
                'Cuộc gọi video đến',
                style: TextStyle(color: Color(0xFFB7C4D8), fontSize: 16),
              ),
              const SizedBox(height: WebTuiSpacing.xl),
              Container(
                padding: const EdgeInsets.all(WebTuiSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      color: Colors.white,
                    ),
                    SizedBox(width: WebTuiSpacing.sm),
                    Expanded(
                      child: Text(
                        'Thông báo cuộc gọi vẫn hiển thị khi ứng dụng ở nền.',
                        style: TextStyle(color: Color(0xFFCFD9EA)),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
                  _RoundCallAction(
                    label: 'Từ chối',
                    icon: Icons.call_end_rounded,
                    color: WebTuiColors.danger,
                  ),
                  _RoundCallAction(
                    label: 'Trả lời',
                    icon: Icons.videocam_rounded,
                    color: WebTuiColors.accentGreen,
                  ),
                ],
              ),
              const SizedBox(height: WebTuiSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneChannelsPreview extends StatelessWidget {
  const _PhoneChannelsPreview();

  @override
  Widget build(BuildContext context) {
    return WebTuiMobileScaffold(
      title: 'Kênh',
      selectedTab: 2,
      onTabSelected: (_) {},
      actions: const [
        IconButton(
          tooltip: 'Tạo kênh',
          onPressed: _noopAction,
          icon: Icon(CupertinoIcons.plus_circle),
        ),
      ],
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
            child: WebTuiSearchBar(hintText: 'Tìm kênh...'),
          ),
          WebTuiSectionLabel('WORKSPACE'),
          WebTuiListSurface(
            children: [
              WebTuiChannelBotListItem(
                title: 'Thông báo chung',
                subtitle: 'Lịch bảo trì và cập nhật hệ thống',
                icon: Icons.campaign_outlined,
                color: WebTuiColors.primary,
                unreadCount: 2,
              ),
              WebTuiChannelBotListItem(
                title: 'Dự án WebTUI',
                subtitle: 'Tài liệu, checklist và trao đổi nhóm',
                icon: CupertinoIcons.number,
                color: WebTuiColors.accentGreen,
                trailingLabel: 'Đang mở',
              ),
              WebTuiChannelBotListItem(
                title: 'Bot hỗ trợ',
                subtitle: 'Tự động ghi nhận yêu cầu và nhắc việc',
                icon: Icons.smart_toy_outlined,
                color: WebTuiColors.accentAmber,
              ),
            ],
          ),
          WebTuiSectionLabel('GẦN ĐÂY'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: _WorkspaceSummaryPreview(),
          ),
        ],
      ),
    );
  }
}

class _PhoneSafetyPreview extends StatelessWidget {
  const _PhoneSafetyPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        toolbarHeight: 56,
        title: const Text('An toàn & riêng tư'),
        actions: const [
          IconButton(
            tooltip: 'Đóng',
            onPressed: _noopAction,
            icon: Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          children: [
            const Text(
              'Kiểm soát cuộc trò chuyện',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            const Text(
              'Báo cáo nội dung, chặn người dùng và quản lý phiên đăng nhập ngay trong ứng dụng.',
              style: TextStyle(color: WebTuiColors.textSecondary),
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            const WebTuiListSurface(
              children: [
                WebTuiSettingRow(
                  title: 'Báo cáo tin nhắn',
                  subtitle: 'Gửi bằng chứng cho đội kiểm duyệt workspace',
                  icon: Icons.flag_outlined,
                ),
                WebTuiSettingRow(
                  title: 'Chặn người dùng',
                  subtitle: 'Ngăn tin nhắn và cuộc gọi không mong muốn',
                  icon: Icons.block_rounded,
                ),
                WebTuiSettingRow(
                  title: 'Xóa tài khoản',
                  subtitle: 'Yêu cầu xóa dữ liệu từ cài đặt tài khoản',
                  icon: Icons.delete_outline_rounded,
                  destructive: true,
                ),
              ],
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            Container(
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              decoration: BoxDecoration(
                color: WebTuiColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: WebTuiColors.border),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: WebTuiColors.primary,
                      ),
                      SizedBox(width: WebTuiSpacing.sm),
                      Text(
                        'Bảo vệ workspace',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  SizedBox(height: WebTuiSpacing.sm),
                  Text(
                    'Quyền truy cập, lời mời kết bạn và trạng thái chặn được đồng bộ với máy chủ bạn chọn.',
                    style: TextStyle(color: WebTuiColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallControlsPreview extends StatelessWidget {
  const _CallControlsPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SmallCallButton(label: 'Mic', icon: Icons.mic_rounded),
          _SmallCallButton(label: 'Loa', icon: Icons.volume_up_rounded),
          _SmallCallButton(label: 'Camera', icon: Icons.videocam_rounded),
          _SmallCallButton(label: 'Đổi cam', icon: Icons.cameraswitch_rounded),
          _SmallCallButton(
            label: 'Kết thúc',
            icon: Icons.call_end_rounded,
            color: WebTuiColors.danger,
          ),
        ],
      ),
    );
  }
}

class _SmallCallButton extends StatelessWidget {
  const _SmallCallButton({
    required this.label,
    required this.icon,
    this.color = const Color(0xFF2F3D52),
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color,
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFCFD9EA), fontSize: 10),
        ),
      ],
    );
  }
}

class _RoundCallAction extends StatelessWidget {
  const _RoundCallAction({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: color,
          child: Icon(icon, color: Colors.white, size: 30),
        ),
        const SizedBox(height: WebTuiSpacing.sm),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _WorkspaceSummaryPreview extends StatelessWidget {
  const _WorkspaceSummaryPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WebTuiColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                color: WebTuiColors.primary,
              ),
              SizedBox(width: WebTuiSpacing.sm),
              Text(
                'Tổng quan hôm nay',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SizedBox(height: WebTuiSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MetricPreview(value: '3', label: 'tin mới'),
              ),
              SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: _MetricPreview(value: '2', label: 'tệp'),
              ),
              SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: _MetricPreview(value: '1', label: 'cuộc gọi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPreview extends StatelessWidget {
  const _MetricPreview({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.sm,
          vertical: WebTuiSpacing.md,
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: WebTuiColors.primary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WebTuiColors.textSecondary,
                fontSize: 11,
              ),
            ),
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

void _noopBool(bool _) {}

void _noopDouble(double _) {}

void _noopAction() {}
