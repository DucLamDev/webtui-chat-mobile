import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/workspace/application/use_cases/load_workspace_session_use_case.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace_permission.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/permission_repository.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_repository.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

void main() {
  test(
    'auto-loads the account workspace without requiring a switch screen',
    () async {
      final sessionRepository = _FakeWorkspaceSessionRepository();
      final workspaceRepository = _FakeWorkspaceRepository();
      final permissionRepository = _FakePermissionRepository();
      final useCase = LoadWorkspaceSessionUseCase(
        workspaceRepository: workspaceRepository,
        permissionRepository: permissionRepository,
        sessionRepository: sessionRepository,
      );

      final result = await useCase.execute();

      expect(result.valueOrNull?.activeWorkspace?.id, 'w1');
      expect(await sessionRepository.readActiveWorkspaceId(), 'w1');
      expect(sessionRepository.previousResetId, isNull);
      expect(sessionRepository.nextResetId, isNull);
    },
  );
}

const _workspaces = [
  Workspace(
    id: 'w1',
    slug: 'cong-ty-a',
    name: 'Cong ty A',
    plan: 'free',
    status: 'active',
  ),
];

final class _FakeWorkspaceRepository implements WorkspaceRepository {
  @override
  Future<Result<Workspace>> get(String workspaceId) async {
    return Success(_workspaces.firstWhere((item) => item.id == workspaceId));
  }

  @override
  Future<Result<List<Workspace>>> listMine() async {
    return const Success(_workspaces);
  }
}

final class _FakePermissionRepository implements PermissionRepository {
  @override
  Future<Result<List<WorkspacePermission>>> listForWorkspace(
    String workspaceId,
  ) async {
    return const Success([
      WorkspacePermission(
        id: 'p1',
        code: 'workspace.view_members',
        module: 'workspace',
        action: 'view_members',
        name: 'Xem thanh vien',
      ),
    ]);
  }
}

final class _FakeWorkspaceSessionRepository
    implements WorkspaceSessionRepository {
  String? activeId;
  String? previousResetId;
  String? nextResetId;

  @override
  Future<String?> readActiveWorkspaceId() async => activeId;

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {
    previousResetId = previousWorkspaceId;
    nextResetId = nextWorkspaceId;
  }

  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) async {
    activeId = workspaceId;
  }
}
