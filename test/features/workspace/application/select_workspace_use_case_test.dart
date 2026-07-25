import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/workspace/application/use_cases/select_workspace_use_case.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace_permission.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/permission_repository.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

void main() {
  test('does not persist workspace when RBAC lookup fails', () async {
    final sessionRepository = _FakeWorkspaceSessionRepository(activeId: 'w1');
    final permissionRepository = _FakePermissionRepository(
      result: const FailureResult(
        Failure(
          kind: FailureKind.forbidden,
          message: 'Bạn không có quyền truy cập workspace này.',
          code: 'WORKSPACE_FORBIDDEN',
        ),
      ),
    );
    final useCase = SelectWorkspaceUseCase(
      permissionRepository: permissionRepository,
      sessionRepository: sessionRepository,
    );

    final result = await useCase.execute(
      workspace: _workspaceB,
      allWorkspaces: const [_workspaceA, _workspaceB],
    );

    expect(result.isFailure, isTrue);
    expect(await sessionRepository.readActiveWorkspaceId(), 'w1');
    expect(sessionRepository.resetCalls, 0);
    expect(sessionRepository.savedIds, isEmpty);
  });

  test('resets scoped runtime after permissions are loaded', () async {
    final sessionRepository = _FakeWorkspaceSessionRepository(activeId: 'w1');
    final permissionRepository = _FakePermissionRepository(
      result: const Success([
        WorkspacePermission(
          id: 'p1',
          code: 'message.read',
          module: 'message',
          action: 'read',
          name: 'Đọc tin nhắn',
        ),
      ]),
    );
    final useCase = SelectWorkspaceUseCase(
      permissionRepository: permissionRepository,
      sessionRepository: sessionRepository,
    );

    final result = await useCase.execute(
      workspace: _workspaceB,
      allWorkspaces: const [_workspaceA, _workspaceB],
    );

    expect(result.valueOrNull?.activeWorkspace?.id, 'w2');
    expect(permissionRepository.requestedWorkspaceIds, ['w2']);
    expect(sessionRepository.previousResetId, 'w1');
    expect(sessionRepository.nextResetId, 'w2');
    expect(sessionRepository.savedIds, ['w2']);
  });
}

const _workspaceA = Workspace(
  id: 'w1',
  slug: 'cong-ty-a',
  name: 'Công ty A',
  plan: 'free',
  status: 'active',
);

const _workspaceB = Workspace(
  id: 'w2',
  slug: 'cong-ty-b',
  name: 'Công ty B',
  plan: 'pro',
  status: 'active',
);

final class _FakePermissionRepository implements PermissionRepository {
  _FakePermissionRepository({required this.result});

  final Result<List<WorkspacePermission>> result;
  final List<String> requestedWorkspaceIds = [];

  @override
  Future<Result<List<WorkspacePermission>>> listForWorkspace(
    String workspaceId,
  ) async {
    requestedWorkspaceIds.add(workspaceId);
    return result;
  }
}

final class _FakeWorkspaceSessionRepository
    implements WorkspaceSessionRepository {
  _FakeWorkspaceSessionRepository({this.activeId});

  String? activeId;
  String? previousResetId;
  String? nextResetId;
  int resetCalls = 0;
  final List<String> savedIds = [];

  @override
  Future<String?> readActiveWorkspaceId() async => activeId;

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {
    resetCalls += 1;
    previousResetId = previousWorkspaceId;
    nextResetId = nextWorkspaceId;
  }

  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) async {
    savedIds.add(workspaceId);
    activeId = workspaceId;
  }
}
