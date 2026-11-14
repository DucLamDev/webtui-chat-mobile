import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';

/// Dòng "Tổng quan nghiệp vụ" ở tab Nghiệp vụ (cùng kiểu dòng hội thoại): mở
/// bảng tổng quan `/business`. Chỉ được dựng khi máy chủ bật automation.
class BusinessInboxEntry extends StatelessWidget {
  const BusinessInboxEntry({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final id = workspaceId.trim();
    if (id.isEmpty) return const SizedBox.shrink();
    return WebTuiConversationListItem(
      key: const Key('business_entry'),
      title: 'Tổng quan nghiệp vụ',
      preview: 'Số liệu và việc cần xử lý',
      timeLabel: '',
      avatarLabel: 'Tổng quan nghiệp vụ',
      avatarIcon: WebTuiIcons.work,
      trailing: const Icon(
        CupertinoIcons.chevron_right,
        size: 18,
        color: WebTuiColors.textMuted,
      ),
      onTap: () => context.push(
        Uri(path: '/business', queryParameters: {'workspaceId': id}).toString(),
      ),
    );
  }
}
