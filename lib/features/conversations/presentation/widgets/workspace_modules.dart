import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../my_notes/presentation/controllers/my_notes_access_provider.dart';

/// Mô tả một tiện ích hiện trong tab Công việc. Thêm tiện ích mới = thêm một
/// mục vào [workspaceModulesProvider]; mục `enabled == false` không hiện.
final class WorkspaceModule {
  const WorkspaceModule({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.routeFor,
    required this.enabled,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;

  /// Đường dẫn route mở tiện ích cho một workspace.
  final String Function(String workspaceId) routeFor;
  final bool enabled;
}

/// Danh sách tiện ích đã đăng ký. Hiện chỉ có My Note (bật theo máy chủ);
/// tiện ích khác (IDE, mini app...) đăng ký thêm ở đây khi sẵn sàng.
final workspaceModulesProvider = Provider<List<WorkspaceModule>>((ref) {
  return [
    WorkspaceModule(
      id: 'my_notes',
      title: 'My Note',
      description: 'Ghi chú riêng, chỉ mình bạn xem',
      icon: WebTuiIcons.note,
      routeFor: (workspaceId) => Uri(
        path: '/my-notes',
        queryParameters: {'workspaceId': workspaceId},
      ).toString(),
      enabled: ref.watch(myNotesEnabledProvider),
    ),
  ];
});
