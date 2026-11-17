import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/conversations/domain/entities/call_session.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/message_sender_directory.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/peer_presence.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/chat_greeting_empty_state.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/colleague_profile_sheet.dart';
import 'package:webtui_chat/features/profile/domain/entities/user_profile.dart';

import 'chat_room_body_harness.dart';

final _groupDirectory = MessageSenderDirectory.fromMembers([
  ChannelMember(
    channelId: 'ch',
    userId: 'peer',
    email: '',
    username: '',
    displayName: 'An Nguyễn',
    status: 'active',
    joinedAt: DateTime.utc(2026),
  ),
  ChannelMember(
    channelId: 'ch',
    userId: 'me',
    email: '',
    username: '',
    displayName: 'Tôi',
    status: 'active',
    joinedAt: DateTime.utc(2026),
  ),
]);

const _profileKey = (workspaceId: 'ws', userId: 'peer');

UserProfile _profile({WorkProfile work = const WorkProfile()}) => UserProfile(
  id: 'peer',
  email: 'an.nguyen@congty.vn',
  username: 'an',
  displayName: 'An Nguyễn',
  status: 'active',
  locale: 'vi',
  timezone: 'Asia/Saigon',
  phoneNumber: '0901234567',
  work: work,
);

/// Nút mở bảng hồ sơ; [result] là kết quả tải hồ sơ giả.
Future<void> _pumpProfileOpener(
  WidgetTester tester, {
  required Future<UserProfile> Function() result,
  ValueChanged<CallMode>? onCall,
  VoidCallback? onMessage,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        colleagueProfileProvider(_profileKey).overrideWith((ref) => result()),
      ],
      child: MaterialApp(
        theme: WebTuiTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showColleagueProfileSheet(
                  context,
                  workspaceId: 'ws',
                  userId: 'peer',
                  fallbackName: 'An Nguyễn',
                  presence: const PeerPresenceLabel(
                    text: 'Đang hoạt động',
                    online: true,
                  ),
                  onCall: onCall,
                  onMessage: onMessage,
                ),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('mở'));
  await tester.pumpAndSettle();
}

void main() {
  group('đầu phòng chat', () {
    testWidgets('1-1: bấm ảnh / tên và mục "Xem hồ sơ" đều mở hồ sơ', (
      tester,
    ) async {
      var profileOpened = 0;
      var detailsOpened = 0;
      await pumpChatRoom(
        tester,
        messages: [
          harnessText('m1', 'Chào', mine: false, at: harnessTime(9, 0)),
        ],
        withAppBar: true,
        onViewProfile: () => profileOpened++,
        onDetails: () => detailsOpened++,
      );

      await tester.tap(find.byKey(const Key('chat_room_title_tap')));
      expect(profileOpened, 1);

      await tester.tap(find.byKey(const Key('chat_room_more_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết nhóm'), findsNothing);
      await tester.tap(find.text('Xem hồ sơ'));
      await tester.pumpAndSettle();
      expect(profileOpened, 2);
      expect(detailsOpened, 0);
    });

    testWidgets('nhóm: bấm tên mở chi tiết nhóm, menu không có "Xem hồ sơ"', (
      tester,
    ) async {
      var detailsOpened = 0;
      await pumpChatRoom(
        tester,
        messages: [
          harnessText('m1', 'Chào', mine: false, at: harnessTime(9, 0)),
        ],
        withAppBar: true,
        directChat: false,
        showSenderNames: true,
        senderDirectory: _groupDirectory,
        presence: null,
        onDetails: () => detailsOpened++,
      );

      await tester.tap(find.byKey(const Key('chat_room_title_tap')));
      expect(detailsOpened, 1);

      await tester.tap(find.byKey(const Key('chat_room_more_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Xem hồ sơ'), findsNothing);
      await tester.tap(find.text('Chi tiết nhóm'));
      await tester.pumpAndSettle();
      expect(detailsOpened, 2);
    });
  });

  group('màn chào khi chưa có tin', () {
    testWidgets('1-1: lời chào theo tên, vẫy tay gửi, gợi ý điền ô soạn', (
      tester,
    ) async {
      var waved = 0;
      String? suggested;
      await pumpChatRoom(
        tester,
        messages: const [],
        onGreetingWave: () => waved++,
        onGreetingSuggestion: (text) => suggested = text,
      );

      expect(
        find.byKey(const Key('chat_greeting_empty_state')),
        findsOneWidget,
      );
      expect(find.text('Gửi lời chào tới Hồ Đức Lâm'), findsOneWidget);
      expect(find.text('Bắt đầu cuộc trò chuyện'), findsNothing);

      await tester.tap(find.byKey(const Key('chat_greeting_wave')));
      expect(waved, 1);

      await tester.tap(find.byKey(const Key('chat_greeting_suggestion_1')));
      expect(suggested, chatGreetingSuggestions()[1]);
    });

    testWidgets('nhóm: lời mời mở đầu, nút chào cả nhóm, không có gợi ý', (
      tester,
    ) async {
      var waved = 0;
      await pumpChatRoom(
        tester,
        messages: const [],
        directChat: false,
        showSenderNames: true,
        onGreetingWave: () => waved++,
        onGreetingSuggestion: (_) {},
      );

      expect(find.text('Hãy là người mở đầu cuộc trò chuyện'), findsOneWidget);
      expect(find.byKey(const Key('chat_greeting_suggestion_0')), findsNothing);
      await tester.tap(find.text('Chào cả nhóm'));
      expect(waved, 1);
    });

    testWidgets(
      'chat bot tự động / phiên riêng: lời mời trung tính, không nhắc nhóm',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: WebTuiTheme.light(),
            home: const Scaffold(
              body: ChatGreetingEmptyState(
                directChat: false,
                groupChat: false,
                title: 'Trợ lý đơn hàng',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Hãy là người mở đầu cuộc trò chuyện'),
          findsOneWidget,
        );
        expect(find.text('Tin nhắn mới sẽ xuất hiện tại đây.'), findsOneWidget);
        expect(find.textContaining('Nhóm'), findsNothing);
        expect(find.byKey(const Key('chat_greeting_wave')), findsNothing);
      },
    );

    testWidgets('không gửi được (bị chặn, chat bot): ẩn nút và gợi ý', (
      tester,
    ) async {
      await pumpChatRoom(tester, messages: const []);

      expect(find.text('Gửi lời chào tới Hồ Đức Lâm'), findsOneWidget);
      expect(find.byKey(const Key('chat_greeting_wave')), findsNothing);
      expect(find.byKey(const Key('chat_greeting_suggestion_0')), findsNothing);
    });
  });

  group('ảnh người gửi trong nhóm', () {
    testWidgets('bấm ảnh người gửi mở hồ sơ; tin bot không bấm được', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpChatRoom(
        tester,
        messages: [
          harnessText('m1', 'Chào cả nhà', mine: false, at: harnessTime(9, 0)),
          ChatMessage(
            id: 'b1',
            workspaceId: 'ws',
            channelId: 'ch',
            kind: 'bot',
            body: 'Thông báo',
            createdAt: harnessTime(9, 1),
            senderId: 'bot-1',
            isMine: false,
          ),
        ],
        directChat: false,
        showSenderNames: true,
        senderDirectory: _groupDirectory,
        onOpenSenderProfile: opened.add,
      );

      await tester.tap(find.byKey(const ValueKey('sender_avatar_m1')));
      expect(opened, ['peer']);
      // Tin bot vẫn có ảnh nhưng không bấm mở hồ sơ.
      expect(find.byKey(const ValueKey('sender_avatar_b1')), findsNothing);
    });
  });

  group('bảng hồ sơ đồng nghiệp', () {
    testWidgets('hiện tên, chức danh, liên hệ; gọi thì đóng bảng rồi gọi', (
      tester,
    ) async {
      CallMode? called;
      await _pumpProfileOpener(
        tester,
        result: () async => _profile(
          work: WorkProfile(
            title: 'Kỹ sư',
            department: 'Kỹ thuật',
            location: 'Hà Nội',
            startDate: DateTime(2024, 3, 1),
          ),
        ),
        onCall: (mode) => called = mode,
      );

      expect(find.byKey(const Key('colleague_profile_sheet')), findsOneWidget);
      expect(find.text('An Nguyễn'), findsOneWidget);
      expect(find.text('Kỹ sư · Kỹ thuật'), findsOneWidget);
      expect(find.text('Đang hoạt động'), findsOneWidget);
      expect(find.text('an.nguyen@congty.vn'), findsOneWidget);
      expect(find.text('0901234567'), findsOneWidget);
      expect(find.text('Hà Nội'), findsOneWidget);
      expect(find.text('01/03/2024'), findsOneWidget);
      // Đang trong chat 1-1 với chính người này: không cần nút nhắn tin.
      expect(find.byKey(const Key('colleague_profile_message')), findsNothing);

      await tester.tap(find.byKey(const Key('colleague_profile_call_video')));
      await tester.pumpAndSettle();
      expect(called, CallMode.video);
      expect(find.byKey(const Key('colleague_profile_sheet')), findsNothing);
    });

    testWidgets('đang tải: hiện tên truyền sẵn và dòng đang tải', (
      tester,
    ) async {
      final pending = Completer<UserProfile>();
      addTearDown(() => pending.complete(_profile()));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            colleagueProfileProvider(
              _profileKey,
            ).overrideWith((ref) => pending.future),
          ],
          child: MaterialApp(
            theme: WebTuiTheme.light(),
            home: const Scaffold(
              body: ColleagueProfileSheet(
                profileKey: _profileKey,
                fallbackName: 'An Nguyễn',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('An Nguyễn'), findsOneWidget);
      expect(
        find.byKey(const Key('colleague_profile_loading')),
        findsOneWidget,
      );
    });

    Future<void> pumpSheet(WidgetTester tester, {String? avatarUrl}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            colleagueProfileProvider(
              _profileKey,
            ).overrideWith((ref) async => _profile()),
          ],
          child: MaterialApp(
            theme: WebTuiTheme.light(),
            home: Scaffold(
              body: ColleagueProfileSheet(
                profileKey: _profileKey,
                fallbackName: 'An Nguyễn',
                avatarUrl: avatarUrl,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('có ảnh: bấm ảnh mở xem toàn màn hình, nút đóng thì đóng', (
      tester,
    ) async {
      await pumpSheet(tester, avatarUrl: 'https://anh.vidu.vn/an.png');
      await tester.tap(find.byKey(const Key('colleague_profile_avatar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('avatar_viewer')), findsOneWidget);
      // Tên người hiện ở đầu màn xem ảnh.
      expect(
        find.descendant(
          of: find.byKey(const Key('avatar_viewer')),
          matching: find.text('An Nguyễn'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('avatar_viewer_close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('avatar_viewer')), findsNothing);
      expect(find.byKey(const Key('colleague_profile_sheet')), findsOneWidget);
    });

    testWidgets('chưa có ảnh: ảnh chữ cái không bấm được', (tester) async {
      await pumpSheet(tester);
      expect(find.byKey(const Key('colleague_profile_avatar')), findsNothing);
      expect(find.byKey(const Key('avatar_viewer')), findsNothing);
    });

    testWidgets('không có quyền xem (404): báo rõ, không có nút thử lại', (
      tester,
    ) async {
      await _pumpProfileOpener(
        tester,
        result: () async => throw DioException(
          requestOptions: RequestOptions(path: '/api/v1/users/peer'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/v1/users/peer'),
            statusCode: 404,
          ),
        ),
      );
      expect(
        find.text('Bạn không xem được hồ sơ của người này.'),
        findsOneWidget,
      );
      expect(find.text('Thử lại'), findsNothing);
      // Đầu bảng vẫn có tên truyền sẵn.
      expect(find.text('An Nguyễn'), findsOneWidget);
    });

    testWidgets('lỗi mạng: có nút thử lại; chưa có thông tin: báo trống', (
      tester,
    ) async {
      var attempts = 0;
      await _pumpProfileOpener(
        tester,
        result: () async {
          attempts++;
          if (attempts == 1) {
            throw DioException(
              requestOptions: RequestOptions(path: '/api/v1/users/peer'),
              type: DioExceptionType.connectionError,
            );
          }
          return const UserProfile(
            id: 'peer',
            email: '',
            username: 'an',
            displayName: 'An Nguyễn',
            status: 'active',
            locale: 'vi',
            timezone: 'Asia/Saigon',
          );
        },
        onMessage: () {},
      );
      expect(find.byKey(const Key('colleague_profile_error')), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byKey(const Key('colleague_profile_empty')), findsOneWidget);
      expect(
        find.byKey(const Key('colleague_profile_message')),
        findsOneWidget,
      );
    });
  });
}
