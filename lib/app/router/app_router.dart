import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/conversations/domain/entities/conversation_summary.dart';
import '../../features/conversations/presentation/screens/channel_create_screen.dart';
import '../../features/conversations/presentation/screens/channel_detail_screen.dart';
import '../../features/conversations/presentation/screens/chat_room_screen.dart';
import '../../features/home/presentation/screens/home_shell_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/settings/presentation/screens/app_settings_screen.dart';
import '../../features/settings/presentation/screens/privacy_sessions_screen.dart';

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
          return LoginScreen(onLoginSuccess: () => context.go('/'));
        },
      ),
      GoRoute(
        path: '/workspaces',
        name: 'workspaces',
        redirect: (context, state) => '/',
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeShellScreen(),
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
    ],
  );
});
