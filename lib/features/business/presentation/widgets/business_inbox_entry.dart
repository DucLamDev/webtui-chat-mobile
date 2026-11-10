import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';

/// Ô "Nghiệp vụ" ở tab Nghiệp vụ: mở bảng tổng quan `/business`. Chỉ được
/// dựng khi máy chủ bật automation (tab chỉ có khi đó).
class BusinessInboxEntry extends StatelessWidget {
  const BusinessInboxEntry({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final id = workspaceId.trim();
    if (id.isEmpty) return const SizedBox.shrink();
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
          key: const Key('business_entry'),
          leading: const Icon(Icons.dashboard_customize_outlined),
          title: const Text('Tổng quan nghiệp vụ'),
          subtitle: const Text('Số liệu và việc cần xử lý'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.push(
            Uri(
              path: '/business',
              queryParameters: {'workspaceId': id},
            ).toString(),
          ),
        ),
      ),
    );
  }
}
