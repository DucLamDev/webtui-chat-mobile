import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../application/inbox_access_policy.dart';

/// Quyền vào Hộp thư khách của một workspace (`null` / rỗng = workspace đang
/// mở). Xem [inboxAccessFor].
final inboxAccessProvider = Provider.autoDispose.family<InboxAccess, String?>((
  ref,
  workspaceId,
) {
  final workspace = ref.watch(
    workspaceControllerProvider.select(
      (state) => (
        permissions: state.permissions,
        loading: state.isLoading,
        activeId: state.activeWorkspace?.id,
      ),
    ),
  );
  return inboxAccessFor(
    serverSupported: inboxServerSupported(
      ref.watch(activeServerDiscoveryProvider),
    ),
    permissions: workspace.permissions,
    permissionsLoading: workspace.loading,
    activeWorkspaceId: workspace.activeId,
    requestedWorkspaceId: workspaceId,
  );
});

/// Mã người dùng đang đăng nhập (để nhận / lọc "của tôi"); `null` khi chưa rõ.
final inboxCurrentUserIdProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final result = await ref.watch(loadProfileUseCaseProvider).execute();
  return result.valueOrNull?.id;
});
