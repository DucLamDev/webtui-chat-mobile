import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_session.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/chat_room_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/message_sender_directory.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/peer_presence.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/chat_room_screen.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/chat_room_app_bar.dart';

const harnessScope = ChatRoomScope(
  workspaceId: 'ws',
  channelId: 'ch',
  title: 'Hồ Đức Lâm',
);

/// Tạo ảnh PNG đơn sắc / chuyển màu trong thư mục tạm, trả đường dẫn.
Future<String> writeFakePng(
  Directory dir,
  String name, {
  required int width,
  required int height,
  required Color top,
  required Color bottom,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()
    ..shader = ui.Gradient.linear(Offset.zero, Offset(0, height.toDouble()), [
      top,
      bottom,
    ]);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    paint,
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/$name.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file.path;
}

DateTime harnessTime(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

ChatMessage harnessText(
  String id,
  String body, {
  required bool mine,
  required DateTime at,
  Map<String, Object?> metadata = const {},
}) {
  return ChatMessage(
    id: id,
    workspaceId: 'ws',
    channelId: 'ch',
    kind: 'text',
    body: body,
    createdAt: at,
    senderId: mine ? 'me' : 'peer',
    isMine: mine,
    metadata: metadata,
  );
}

ChatMessage harnessCall(
  String id, {
  required bool mine,
  required DateTime at,
  required String status,
  int seconds = 0,
  String mode = 'audio',
}) {
  return ChatMessage(
    id: id,
    workspaceId: 'ws',
    channelId: 'ch',
    kind: 'event',
    body: 'Cuộc gọi',
    createdAt: at,
    senderId: mine ? 'me' : 'peer',
    isMine: mine,
    metadata: {
      'message_type': 'call',
      'call_status': status,
      'call_mode': mode,
      'duration_seconds': seconds,
    },
  );
}

ChatMessage harnessMedia(
  String id, {
  required bool mine,
  required DateTime at,
  required String mime,
  required String name,
  String body = '',
  String? localPath,
  Map<String, Object?> metadata = const {},
}) {
  return ChatMessage(
    id: id,
    workspaceId: 'ws',
    channelId: 'ch',
    kind: 'text',
    body: body,
    createdAt: at,
    senderId: mine ? 'me' : 'peer',
    isMine: mine,
    metadata: metadata,
    attachments: [
      MessageAttachment(
        id: 'att-$id',
        workspaceId: 'ws',
        messageId: id,
        fileId: 'file-$id',
        createdAt: at,
        file: UploadedMessageFile(
          id: 'file-$id',
          name: name,
          mimeType: mime,
          byteSize: 1000,
          downloadPath: '/files/$id',
          createdAt: at,
          localPath: localPath,
        ),
      ),
    ],
  );
}

/// Dựng thân phòng chat (+ đầu trang nếu [withAppBar]) với dữ liệu giả.
Future<void> pumpChatRoom(
  WidgetTester tester, {
  required List<ChatMessage> messages,
  String draft = '',
  String? seenMessageId,
  bool withAppBar = false,
  bool callsEnabled = true,
  bool directChat = true,
  PeerPresenceLabel? presence = const PeerPresenceLabel(
    text: 'Đang hoạt động',
    online: true,
  ),
  bool noticeBot = false,
  void Function(CallMode mode)? onCall,
  GlobalKey? boundaryKey,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Trình phát âm thanh gọi kênh nền tảng: trả rỗng cho khỏi lỗi trong test.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (call) async => null,
      );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        (call) async => null,
      );
  final controller = TextEditingController(text: draft);
  final focusNode = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focusNode.dispose);
  void noop() {}
  void noop1(Object? _) {}
  void noop2(Object? a, Object? b) {}
  final state = ChatRoomState(
    scope: harnessScope,
    messages: messages,
    currentUserId: 'me',
    draft: draft,
  );
  final body = ChatRoomBody(
    workspaceId: 'ws',
    state: state,
    senderDirectory: const MessageSenderDirectory.empty(),
    showSenderNames: false,
    directAvatarUrl: null,
    seenMessageId: seenMessageId,
    draftController: controller,
    draftFocusNode: focusNode,
    onDraftChanged: noop1,
    onThreadDraftChanged: noop1,
    onPickAttachment: noop1,
    onScanQrCode: noop,
    onStartVoiceRecording: noop,
    onStopVoiceRecording: noop,
    onCancelVoiceRecording: noop,
    onRetryAttachment: noop1,
    onRemoveAttachment: noop1,
    onRetry: noop,
    onRetryOutbox: noop,
    onLoadOlder: noop,
    onClearSearch: noop,
    onSend: noop1,
    onSchedule: noop,
    onCreatePoll: noop,
    onOpenLink: noop1,
    onSendThread: noop,
    onReply: noop1,
    onCardReply: null,
    onReplyPrivately: noop1,
    blockedUserIds: const {},
    interactionBlocked: false,
    noticeBot: noticeBot,
    onManageBlockedConversation: null,
    onReportMessage: noop1,
    onReportUser: noop1,
    onToggleBlockUser: noop1,
    onConvertToTask: noop1,
    onEdit: noop1,
    onDelete: noop1,
    onReact: noop2,
    onPin: noop1,
    onThread: noop1,
    onForward: noop2,
    onClearThread: noop,
    onFocusMessage: noop1,
    onCancelComposerContext: noop,
    onRetryCall: (mode) => onCall?.call(mode),
  );
  Widget app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: WebTuiTheme.light(),
    home: Scaffold(
      backgroundColor: const Color(0xFFE8F0F7),
      appBar: withAppBar
          ? ChatRoomAppBar(
              title: 'Hồ Đức Lâm',
              noticeBot: noticeBot,
              directChat: directChat,
              presence: presence,
              memberCount: 2,
              callsEnabled: callsEnabled,
              onCall: (mode) => onCall?.call(mode),
              onSearch: noop,
              onSafety: noop,
              onTools: noop,
              onDetails: noop,
            )
          : null,
      body: SafeArea(top: false, child: body),
    ),
  );
  if (boundaryKey != null) {
    app = RepaintBoundary(key: boundaryKey, child: app);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [activeServerDiscoveryProvider.overrideWithValue(null)],
      child: app,
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Chờ ảnh tệp cục bộ đọc + giải mã xong (IO thật nằm ngoài đồng hồ giả).
Future<void> settleImages(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
