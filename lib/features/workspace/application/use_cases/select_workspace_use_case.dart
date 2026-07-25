import '../../../../core/result/result.dart';
import '../../domain/entities/workspace.dart';
import '../../domain/entities/workspace_permission.dart';
import '../../domain/entities/workspace_session.dart';
import '../../domain/repositories/permission_repository.dart';
import '../../domain/repositories/workspace_session_repository.dart';

final class SelectWorkspaceUseCase {
  const SelectWorkspaceUseCase({
    required PermissionRepository permissionRepository,
    required WorkspaceSessionRepository sessionRepository,
  }) : _permissionRepository = permissionRepository,
       _sessionRepository = sessionRepository;

  final PermissionRepository _permissionRepository;
  final WorkspaceSessionRepository _sessionRepository;

  Future<Result<WorkspaceSession>> execute({
    required Workspace workspace,
    required List<Workspace> allWorkspaces,
  }) async {
    final previousWorkspaceId = await _sessionRepository
        .readActiveWorkspaceId();
    final permissionsResult = await _permissionRepository.listForWorkspace(
      workspace.id,
    );
    switch (permissionsResult) {
      case Success<List<WorkspacePermission>>(value: final permissions):
        if (previousWorkspaceId != workspace.id) {
          await _sessionRepository.resetRuntimeForSwitch(
            previousWorkspaceId: previousWorkspaceId,
            nextWorkspaceId: workspace.id,
          );
          await _sessionRepository.saveActiveWorkspaceId(workspace.id);
        }
        return Success(
          WorkspaceSession(
            workspaces: allWorkspaces,
            activeWorkspace: workspace,
            permissions: PermissionSet(permissions),
          ),
        );
      case FailureResult<List<WorkspacePermission>>(failure: final failure):
        return FailureResult(failure);
    }
  }
}
