import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../app/providers/foundation_providers.dart';
import '../../../design_system/components/webtui_components.dart';
import '../../../design_system/icons/webtui_icons.dart';

/// Nút "Gọi cả nhóm": chỉ hiện khi máy chủ báo `capabilities.group_calls`.
/// Quyền thật vẫn do máy chủ kiểm khi gọi API.
class GroupCallButton extends ConsumerWidget {
  const GroupCallButton({required this.onStart, this.busy = false, super.key});

  /// Nhận `audio` hoặc `video`.
  final void Function(String kind) onStart;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled =
        ref.watch(activeServerDiscoveryProvider)?.capabilities.groupCalls ==
        true;
    if (!enabled) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const Key('group-call-button'),
      onPressed: busy ? null : () => _choose(context),
      icon: const Icon(Icons.notifications_active_outlined),
      label: Text(tr('Gọi cả nhóm', 'Call the whole group')),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final kind = await showWebTuiSheet<String>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebTuiSheetHeader(
            title: tr('Gọi cả nhóm', 'Call the whole group'),
            subtitle: tr('Đổ chuông tới mọi thành viên', 'Ring every member'),
          ),
          WebTuiSheetActionTile(
            key: const Key('group-call-audio'),
            icon: WebTuiIcons.phoneCall,
            title: tr('Gọi thoại', 'Voice call'),
            subtitle: tr(
              'Gọi thoại: đổ chuông tới mọi thành viên',
              'Voice call: ring every member',
            ),
            onTap: () => Navigator.of(sheetContext).pop('audio'),
          ),
          WebTuiSheetActionTile(
            key: const Key('group-call-video'),
            icon: WebTuiIcons.video,
            title: tr('Gọi video', 'Video call'),
            subtitle: tr(
              'Gọi video: đổ chuông tới mọi thành viên',
              'Video call: ring every member',
            ),
            onTap: () => Navigator.of(sheetContext).pop('video'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (kind != null) onStart(kind);
  }
}
