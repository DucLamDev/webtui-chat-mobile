import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../controllers/inbox_access_provider.dart';

/// Ô "Hộp thư khách" trên màn chính. Chỉ hiện khi máy chủ báo
/// `capabilities.omnichannel_inbox` và người dùng có quyền xem.
class InboxEntry extends ConsumerWidget {
  const InboxEntry({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(inboxAccessProvider(workspaceId));
    final id = workspaceId.trim();
    if (!access.canView || id.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.sm,
        WebTuiSpacing.lg,
        0,
      ),
      child: Material(
        color: WebTuiColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          side: const BorderSide(color: WebTuiColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: const Key('inbox_entry'),
          leading: const Icon(Icons.forum_outlined),
          title: const Text('Hộp thư khách'),
          subtitle: const Text('Tin khách từ email, Messenger, Zalo...'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(
            Uri(
              path: '/inbox',
              queryParameters: {'workspaceId': id},
            ).toString(),
          ),
        ),
      ),
    );
  }
}
