import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

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
      title: tr('Hộp thư khách', 'Customer inbox'),
      preview: tr(
        'Tin khách từ email, Messenger, Zalo...',
        'Customer messages from email, Messenger, Zalo...',
      ),
      timeLabel: '',
      avatarLabel: tr('Hộp thư khách', 'Customer inbox'),
      avatarIcon: WebTuiIcons.messages,
      trailing: Icon(
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
