import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../moderation/presentation/controllers/moderation_controller.dart';
import 'conversation_home_controller.dart';

/// Số đỏ trên tab Tin nhắn (thanh dưới) của một workspace.
///
/// Tính bằng [ConversationHomeState.unreadBadgeCount] trên toàn bộ hộp thư,
/// không theo chip lọc / ô tìm đang chọn; bỏ người đã chặn và chat tắt tiếng.
final messagesTabUnreadCountProvider = Provider.autoDispose.family<int, String>(
  (ref, workspaceId) {
    final blockedUsers = ref.watch(
      moderationControllerProvider(
        workspaceId,
      ).select((state) => state.blockedUsers),
    );
    final blockedUserIds = {
      for (final user in blockedUsers)
        if (user.blockedUserId.trim().isNotEmpty) user.blockedUserId.trim(),
    };
    return ref.watch(
      conversationHomeControllerProvider(workspaceId).select(
        (state) => state.unreadBadgeCount(blockedUserIds: blockedUserIds),
      ),
    );
  },
);
