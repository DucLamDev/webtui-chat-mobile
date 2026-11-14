import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../controllers/inbox_access_provider.dart';

/// Dòng "Hộp thư khách" (cùng kiểu dòng hội thoại). Chỉ hiện khi máy chủ báo
/// `capabilities.omnichannel_inbox` và người dùng có quyền xem.
class InboxEntry extends ConsumerWidget {
  const InboxEntry({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(inboxAccessProvider(workspaceId));
    final id = workspaceId.trim();
    if (!access.canView || id.isEmpty) return const SizedBox.shrink();
    return WebTuiConversationListItem(
      key: const Key('inbox_entry'),
      title: 'Hộp thư khách',
      preview: 'Tin khách từ email, Messenger, Zalo...',
      timeLabel: '',
      avatarLabel: 'Hộp thư khách',
      avatarIcon: WebTuiIcons.messages,
      trailing: const Icon(
        CupertinoIcons.chevron_right,
        size: 18,
        color: WebTuiColors.textMuted,
      ),
      onTap: () => context.push(
        Uri(path: '/inbox', queryParameters: {'workspaceId': id}).toString(),
      ),
    );
  }
}
