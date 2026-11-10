import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../application/approval_access_policy.dart';

/// Quyền vào mục Phê duyệt của workspace đang mở.
final approvalAccessProvider = Provider.autoDispose<ApprovalAccess>((ref) {
  final discovery = ref.watch(activeServerDiscoveryProvider);
  if (!approvalServerSupported(discovery)) {
    return const ApprovalAccess.unavailable();
  }
  final workspace = ref.watch(
    workspaceControllerProvider.select(
      (state) => (permissions: state.permissions, loading: state.isLoading),
    ),
  );
  final access = ApprovalAccess.resolve(
    discovery: discovery,
    permissions: workspace.permissions,
  );
  if (access.isPending && !workspace.loading) {
    return const ApprovalAccess(
      serverSupported: true,
      permissionsLoaded: true,
      canView: false,
    );
  }
  return access;
});
