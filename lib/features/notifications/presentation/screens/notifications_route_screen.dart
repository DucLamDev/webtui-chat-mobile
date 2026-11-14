import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../conversations/domain/entities/conversation_summary.dart';
import '../../../conversations/presentation/controllers/conversation_home_controller.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import 'notifications_screen.dart';

/// Tìm kênh chat bot thông báo trong hộp thư đã tải; `null` khi chưa có.
ConversationSummary? findNoticeBotConversation(ConversationHomeState state) {
  for (final item in [...state.conversations, ...state.channels]) {
    if (item.noticeBot) return item;
  }
  return null;
}

/// Đường dẫn mở chat bot của workspace.
String noticeBotLocation(ConversationSummary bot) {
  return Uri(
    path: '/conversations/${Uri.encodeComponent(bot.channelId)}',
    queryParameters: <String, String>{
      'workspaceId': bot.workspaceId,
      'title': bot.title,
    },
  ).toString();
}

/// Route `/notifications` (cả liên kết `webtui://chat/notifications`): máy chủ
/// có bot thông báo thì mở chat bot, máy chủ cũ vẫn dùng màn thông báo.
class NotificationsRouteScreen extends ConsumerWidget {
  const NotificationsRouteScreen({this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noticeBot = ref.watch(
      activeServerDiscoveryProvider.select(
        (discovery) => discovery?.capabilities.noticeBot ?? false,
      ),
    );
    if (!noticeBot) return NotificationsScreen(workspaceId: workspaceId);
    final activeId =
        workspaceId ??
        ref.watch(workspaceControllerProvider).activeWorkspace?.id;
    return NoticeBotRedirectScreen(workspaceId: activeId);
  }
}

class NoticeBotRedirectScreen extends ConsumerStatefulWidget {
  const NoticeBotRedirectScreen({this.workspaceId, super.key});

  final String? workspaceId;

  @override
  ConsumerState<NoticeBotRedirectScreen> createState() =>
      _NoticeBotRedirectScreenState();
}

class _NoticeBotRedirectScreenState
    extends ConsumerState<NoticeBotRedirectScreen> {
  bool _redirected = false;

  void _go(String location) {
    if (_redirected) return;
    _redirected = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(location);
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.workspaceId?.trim();
    if (id == null || id.isEmpty) {
      _go('/');
    } else {
      final state = ref.watch(conversationHomeControllerProvider(id));
      final bot = findNoticeBotConversation(state);
      if (bot != null) {
        _go(noticeBotLocation(bot));
      } else if (!state.isLoading) {
        // Chưa có chat bot (chưa có thông báo đầu tiên): về tab Tin nhắn.
        _go('/');
      }
    }
    return const Scaffold(
      body: SafeArea(
        child: WebTuiLoadingState(message: 'Đang mở thông báo...'),
      ),
    );
  }
}
