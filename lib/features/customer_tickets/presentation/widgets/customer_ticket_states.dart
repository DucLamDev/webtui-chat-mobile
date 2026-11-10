import 'package:flutter/material.dart';

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
      title: 'Không có quyền xem ticket',
      message: text == null || text.isEmpty
          ? 'Bạn cần quyền xem đơn hàng trong workspace này để xem ticket khách.'
          : text,
      icon: Icons.lock_outline_rounded,
    );
  }
}

/// Chặn trước khi tải: máy chủ không hỗ trợ / đang tải quyền / thiếu quyền.
/// Trả `null` khi được vào.
Widget? customerTicketAccessGate(CustomerTicketAccess access) {
  if (!access.serverSupported) {
    return const CustomerTicketNoAccessState(
      message: 'Máy chủ này không có hộp thư ticket khách.',
    );
  }
  if (access.isPending) {
    return const WebTuiLoadingState(message: 'Đang kiểm tra quyền...');
  }
  if (!access.canView) return const CustomerTicketNoAccessState();
  return null;
}
