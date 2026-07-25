import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/workspace.dart';
import '../../domain/entities/workspace_permission.dart';
import '../../domain/entities/workspace_session.dart';
import '../../domain/repositories/permission_repository.dart';
import '../../domain/repositories/workspace_repository.dart';
import '../../domain/repositories/workspace_session_repository.dart';

final class LoadWorkspaceSessionUseCase {
  const LoadWorkspaceSessionUseCase({
    required WorkspaceRepository workspaceRepository,
    required PermissionRepository permissionRepository,
    required WorkspaceSessionRepository sessionRepository,
  }) : _workspaceRepository = workspaceRepository,
       _permissionRepository = permissionRepository,
       _sessionRepository = sessionRepository;

  final WorkspaceRepository _workspaceRepository;
  final PermissionRepository _permissionRepository;
  final WorkspaceSessionRepository _sessionRepository;

  Future<Result<WorkspaceSession>> execute() async {
    final listResult = await _workspaceRepository.listMine();
    switch (listResult) {
      case FailureResult<List<Workspace>>(failure: final failure):
        return FailureResult(failure);
      case Success<List<Workspace>>(value: final workspaces):
        if (workspaces.isEmpty) {
          return Success(
            WorkspaceSession(
              workspaces: const [],
              permissions: PermissionSet(const []),
            ),
          );
        }

        final savedId = await _sessionRepository.readActiveWorkspaceId();
        final active = _pickActiveWorkspace(workspaces, savedId);
        if (active == null) {
          return FailureResult(
            Failure(
              kind: FailureKind.validation,
              message: 'Không tìm thấy workspace hợp lệ cho tài khoản này.',
              code: 'WORKSPACE_NOT_AVAILABLE',
            ),
          );
        }

        if (savedId != active.id) {
          await _sessionRepository.saveActiveWorkspaceId(active.id);
        }
        return _withPermissions(workspaces, active);
    }
  }

  Future<Result<WorkspaceSession>> _withPermissions(
    List<Workspace> workspaces,
    Workspace active,
  ) async {
    final permissionsResult = await _permissionRepository.listForWorkspace(
      active.id,
    );
    switch (permissionsResult) {
      case Success<List<WorkspacePermission>>(value: final permissions):
        return Success(
          WorkspaceSession(
            workspaces: workspaces,
            activeWorkspace: active,
            permissions: PermissionSet(permissions),
          ),
        );
      case FailureResult<List<WorkspacePermission>>(failure: final failure):
        return FailureResult(failure);
    }
  }
}

Workspace? _pickActiveWorkspace(List<Workspace> workspaces, String? savedId) {
  for (final workspace in workspaces) {
    if (workspace.id == savedId) {
      return workspace;
    }
  }
  for (final workspace in workspaces) {
    if (workspace.isActive) {
      return workspace;
    }
  }
  return workspaces.isEmpty ? null : workspaces.first;
}
