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
    'nhiều workspace chưa chọn: tải lặp vẫn phải hỏi, không tự lưu',
    () async {
      final session = _Session();
      final useCase = LoadWorkspaceSessionUseCase(
        workspaceRepository: _Workspaces(const [_a, _b]),
        permissionRepository: _Permissions(),
        sessionRepository: session,
      );
      final first = await useCase.execute();
      final repeated = await useCase.execute();
      expect(first.valueOrNull?.needsInitialChoice, isTrue);
      expect(repeated.valueOrNull?.needsInitialChoice, isTrue);
      expect(session.id, isNull);
    },
  );

  test('một workspace tự chọn; lần sau dùng lựa chọn đã lưu', () async {
    final session = _Session();
    final useCase = LoadWorkspaceSessionUseCase(
      workspaceRepository: _Workspaces(const [_b]),
      permissionRepository: _Permissions(),
      sessionRepository: session,
    );
    expect((await useCase.execute()).valueOrNull?.needsInitialChoice, isFalse);
    expect(session.id, 'b');
    expect((await useCase.execute()).valueOrNull?.activeWasSaved, isTrue);
  });

  test('khôi phục đúng workspace đã chọn khi có nhiều tổ chức', () async {
    final session = _Session()..id = 'b';
    final useCase = LoadWorkspaceSessionUseCase(
      workspaceRepository: _Workspaces(const [_a, _b]),
      permissionRepository: _Permissions(),
      sessionRepository: session,
    );
    final value = (await useCase.execute()).valueOrNull!;
    expect(value.activeWorkspace?.id, 'b');
    expect(value.needsInitialChoice, isFalse);
  });
}

const _a = Workspace(
  id: 'a',
  slug: 'a',
  name: 'Công ty A',
  plan: 'free',
  status: 'active',
);
const _b = Workspace(
  id: 'b',
  slug: 'b',
  name: 'Công ty B',
  plan: 'free',
  status: 'active',
);

final class _Workspaces implements WorkspaceRepository {
  _Workspaces(this.items);
  final List<Workspace> items;
  @override
  Future<Result<List<Workspace>>> listMine() async => Success(items);
  @override
  Future<Result<Workspace>> get(String workspaceId) async =>
      Success(items.firstWhere((w) => w.id == workspaceId));
}

final class _Permissions implements PermissionRepository {
  @override
  Future<Result<List<WorkspacePermission>>> listForWorkspace(
    String workspaceId,
  ) async => const Success([]);
}

final class _Session implements WorkspaceSessionRepository {
  String? id;
  @override
  Future<String?> readActiveWorkspaceId() async => id;
  @override
  Future<void> saveActiveWorkspaceId(String workspaceId) async {
    id = workspaceId;
  }

  @override
  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  }) async {}
}
