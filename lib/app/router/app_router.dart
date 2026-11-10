import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/email_verification.dart';
import '../../features/auth/presentation/screens/device_approval_pending_screen.dart';
import '../../features/auth/presentation/screens/device_approval_review_screen.dart';
import '../../features/auth/presentation/screens/email_verification_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/qr_login_screen.dart';
import '../../features/conversations/domain/entities/conversation_summary.dart';
import '../../features/conversations/presentation/screens/channel_create_screen.dart';
import '../../features/conversations/presentation/screens/channel_detail_screen.dart';
import '../../features/conversations/presentation/screens/chat_room_screen.dart';
import '../../features/customer_tickets/presentation/screens/customer_ticket_detail_screen.dart';
import '../../features/customer_tickets/presentation/screens/customer_ticket_list_screen.dart';
import '../../features/home/presentation/screens/home_shell_screen.dart';
import '../../features/my_notes/presentation/screens/my_note_editor_screen.dart';
import '../../features/my_notes/presentation/screens/my_notes_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/settings/presentation/screens/app_settings_screen.dart';
import '../../features/settings/presentation/screens/feedback_screen.dart';
import '../../features/settings/presentation/screens/privacy_sessions_screen.dart';
import '../../features/workspace/presentation/screens/invite_screen.dart';
import '../../features/workspace/presentation/screens/workspace_selector_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((_) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) {
          return LoginScreen(
            onLoginSuccess: () => context.go(workspacePickerAfterLoginPath),
            onDeviceApprovalRequired: () =>
                context.go(deviceApprovalPendingPath),
            onEmailVerificationRequired: (ticket) =>
                context.push(emailVerificationLocation(ticket)),
          );
        },
      ),
      GoRoute(
        path: '/workspaces',
        name: 'workspaces',
        builder: (context, state) {
          return WorkspaceSelectorScreen(
            firstLogin: state.uri.queryParameters['first'] == '1',
            onWorkspaceSelected: () => context.go('/'),
          );
        },
      ),
      GoRoute(
        path: '/qr-login',
        name: 'qr-login',
        builder: (context, state) => const QrLoginScreen(),
      ),
      GoRoute(
        path: deviceApprovalPendingPath,
        name: 'device-approval-pending',
        builder: (context, state) => const DeviceApprovalPendingScreen(),
      ),
      GoRoute(
        path: '/device-approvals/:session_id',
        name: 'device-approval-review',
        builder: (context, state) => DeviceApprovalReviewScreen(
          sessionId: state.pathParameters['session_id'] ?? '',
        ),
      ),
      GoRoute(
        path: emailVerificationPath,
        name: 'verify-email',
        builder: (context, state) => EmailVerificationScreen(
          ticket: EmailVerificationTicket.fromQuery(state.uri.queryParameters),
        ),
      ),
      GoRoute(
        path: '/invite/:token',
        name: 'invite',
        builder: (context, state) =>
            InviteScreen(token: state.pathParameters['token'] ?? ''),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) {
          return HomeShellScreen(
            initialTabIndex: _homeInitialTabIndex(
              state.uri.queryParameters['tab'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/conversations/:channel_id',
        name: 'conversation',
        builder: (context, state) {
          final participantIds = state.uri.queryParameters['participantIds']
              ?.split(',')
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toList(growable: false);
          return ChatRoomScreen(
            channelId: state.pathParameters['channel_id'] ?? '',
            workspaceId: state.uri.queryParameters['workspaceId'],
            avatarUrl: state.uri.queryParameters['avatarUrl'],
            title: state.uri.queryParameters['title'] ?? 'Hội thoại',
            initialMessageId: state.uri.queryParameters['messageId'],
            conversation: state.extra is ConversationSummary
                ? state.extra! as ConversationSummary
                : null,
            peerUserId: state.uri.queryParameters['peerUserId'],
            participantIds: participantIds ?? const [],
            initialTool: state.uri.queryParameters['tool'],
            initialTaskId: state.uri.queryParameters['taskId'],
          );
        },
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) {
          return NotificationsScreen(
            workspaceId: state.uri.queryParameters['workspaceId'],
          );
        },
      ),
      GoRoute(
        path: '/channels/new',
        name: 'channel-create',
        builder: (context, state) => const ChannelCreateScreen(),
      ),
      GoRoute(
        path: '/channels/:channel_id',
        name: 'channel-detail',
        builder: (context, state) {
          return ChannelDetailScreen(
            channelId: state.pathParameters['channel_id'] ?? '',
            initialTitle: state.uri.queryParameters['title'] ?? 'Kênh',
          );
        },
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const AppSettingsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        name: 'privacy',
        builder: (context, state) => const PrivacySessionsScreen(),
      ),
      GoRoute(
        path: '/feedback',
        name: 'feedback',
        builder: (context, state) => const FeedbackScreen(),
      ),
      // Ticket khách (máy chủ nội bộ): màn tự kiểm discovery + quyền.
      GoRoute(
        path: '/customer-tickets',
        name: 'customer-tickets',
        builder: (context, state) => CustomerTicketListScreen(
          workspaceId: state.uri.queryParameters['workspaceId'],
        ),
      ),
      GoRoute(
        path: '/customer-tickets/:ticket_id',
        name: 'customer-ticket',
        builder: (context, state) => CustomerTicketDetailScreen(
          ticketId: state.pathParameters['ticket_id'] ?? '',
          workspaceId: state.uri.queryParameters['workspaceId'],
        ),
      ),
      // My Note: màn tự kiểm capabilities.my_notes; `new` = ghi chú mới.
      GoRoute(
        path: '/my-notes',
        name: 'my-notes',
        builder: (context, state) => MyNotesScreen(
          workspaceId: state.uri.queryParameters['workspaceId'],
        ),
      ),
      GoRoute(
        path: '/my-notes/:note_id',
        name: 'my-note',
        builder: (context, state) => MyNoteEditorScreen(
          noteId: state.pathParameters['note_id'] ?? 'new',
          workspaceId: state.uri.queryParameters['workspaceId'],
          initialFolderId: state.uri.queryParameters['folderId'],
        ),
      ),
    ],
  );
});

int _homeInitialTabIndex(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'contacts':
      return 1;
    // Kênh đã gộp vào hộp thư Tin nhắn.
    case 'channels':
      return 0;
    case 'tools':
      return 2;
    case 'settings':
      return 3;
    default:
      return 0;
  }
}
