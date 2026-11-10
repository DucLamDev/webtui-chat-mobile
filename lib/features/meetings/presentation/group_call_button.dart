import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/foundation_providers.dart';

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
      label: const Text('Gọi cả nhóm'),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final kind = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Gọi cả nhóm'),
        children: [
          SimpleDialogOption(
            key: const Key('group-call-audio'),
            onPressed: () => Navigator.of(dialogContext).pop('audio'),
            child: const Text('Gọi thoại: đổ chuông tới mọi thành viên'),
          ),
          SimpleDialogOption(
            key: const Key('group-call-video'),
            onPressed: () => Navigator.of(dialogContext).pop('video'),
            child: const Text('Gọi video: đổ chuông tới mọi thành viên'),
          ),
        ],
      ),
    );
    if (kind != null) onStart(kind);
  }
}
