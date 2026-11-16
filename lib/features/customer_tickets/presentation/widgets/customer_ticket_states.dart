import 'package:flutter/material.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../application/customer_ticket_access_policy.dart';

/// Trạng thái "không có quyền" chung cho danh sách và chi tiết ticket.
class CustomerTicketNoAccessState extends StatelessWidget {
  const CustomerTicketNoAccessState({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message?.trim();
    return WebTuiEmptyState(
      key: const Key('customer_ticket_no_access'),
      title: tr('Không có quyền xem ticket', 'No permission to view tickets'),
      message: text == null || text.isEmpty
          ? tr(
              'Bạn cần quyền xem đơn hàng trong workspace này để xem ticket khách.',
              'You need permission to view orders in this workspace to see customer tickets.',
            )
          : text,
      icon: Icons.lock_outline_rounded,
    );
  }
}

/// Chặn trước khi tải: máy chủ không hỗ trợ / đang tải quyền / thiếu quyền.
/// Trả `null` khi được vào.
Widget? customerTicketAccessGate(CustomerTicketAccess access) {
  if (!access.serverSupported) {
    return CustomerTicketNoAccessState(
      message: tr(
        'Máy chủ này không có hộp thư ticket khách.',
        'This server has no customer ticket inbox.',
      ),
    );
  }
  if (access.isPending) {
    return WebTuiLoadingState(
      message: tr('Đang kiểm tra quyền...', 'Checking permissions...'),
    );
  }
  if (!access.canView) return const CustomerTicketNoAccessState();
  return null;
}
