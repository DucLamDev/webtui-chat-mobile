import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../application/approval_access_policy.dart';

/// Quyền vào mục Phê duyệt của một workspace (`null` / rỗng = workspace đang
/// mở). Xem [approvalAccessFor].
final approvalAccessProvider = Provider.autoDispose
    .family<ApprovalAccess, String?>((ref, workspaceId) {
      final workspace = ref.watch(
        workspaceControllerProvider.select(
          (state) => (
            permissions: state.permissions,
            loading: state.isLoading,
            activeId: state.activeWorkspace?.id,
          ),
        ),
      );
      return approvalAccessFor(
        serverSupported: approvalServerSupported(
          ref.watch(activeServerDiscoveryProvider),
        ),
        permissions: workspace.permissions,
        permissionsLoading: workspace.loading,
        activeWorkspaceId: workspace.activeId,
        requestedWorkspaceId: workspaceId,
      );
    });
