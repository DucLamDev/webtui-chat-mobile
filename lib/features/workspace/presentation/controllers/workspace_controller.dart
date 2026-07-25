import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/load_workspace_session_use_case.dart';
import '../../application/use_cases/select_workspace_use_case.dart';
import '../../domain/entities/workspace.dart';
import '../../domain/entities/workspace_permission.dart';
import '../../domain/entities/workspace_session.dart';

final workspaceControllerProvider =
    StateNotifierProvider<WorkspaceController, WorkspaceState>((ref) {
      return WorkspaceController(
        loadWorkspaceSessionUseCase: ref.watch(
          loadWorkspaceSessionUseCaseProvider,
        ),
        selectWorkspaceUseCase: ref.watch(selectWorkspaceUseCaseProvider),
      )..load();
    });

final class WorkspaceState {
  const WorkspaceState({
    this.workspaces = const [],
    this.permissions,
    this.activeWorkspace,
    this.isLoading = false,
    this.isSwitching = false,
    this.errorMessage,
    this.generation = 0,
  });

  final List<Workspace> workspaces;
  final PermissionSet? permissions;
  final Workspace? activeWorkspace;
  final bool isLoading;
  final bool isSwitching;
  final String? errorMessage;
  final int generation;

  bool get hasActiveWorkspace => activeWorkspace != null;

  WorkspaceState copyWith({
    List<Workspace>? workspaces,
    PermissionSet? permissions,
    Workspace? activeWorkspace,
    bool? isLoading,
    bool? isSwitching,
    String? errorMessage,
    bool clearError = false,
    int? generation,
  }) {
    return WorkspaceState(
      workspaces: workspaces ?? this.workspaces,
      permissions: permissions ?? this.permissions,
      activeWorkspace: activeWorkspace ?? this.activeWorkspace,
      isLoading: isLoading ?? this.isLoading,
      isSwitching: isSwitching ?? this.isSwitching,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      generation: generation ?? this.generation,
    );
  }
}

final class WorkspaceController extends StateNotifier<WorkspaceState> {
  WorkspaceController({
    required LoadWorkspaceSessionUseCase loadWorkspaceSessionUseCase,
    required SelectWorkspaceUseCase selectWorkspaceUseCase,
  }) : _loadWorkspaceSessionUseCase = loadWorkspaceSessionUseCase,
       _selectWorkspaceUseCase = selectWorkspaceUseCase,
       super(const WorkspaceState());

  final LoadWorkspaceSessionUseCase _loadWorkspaceSessionUseCase;
  final SelectWorkspaceUseCase _selectWorkspaceUseCase;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _loadWorkspaceSessionUseCase.execute();
    _applyResult(result, isLoading: false, incrementGeneration: false);
  }

  Future<bool> select(Workspace workspace) async {
    state = state.copyWith(isSwitching: true, clearError: true);
    final previousId = state.activeWorkspace?.id;
    final result = await _selectWorkspaceUseCase.execute(
      workspace: workspace,
      allWorkspaces: state.workspaces,
    );
    final changed = previousId != workspace.id;
    _applyResult(result, isSwitching: false, incrementGeneration: changed);
    return result.isSuccess;
  }

  bool allows(String permissionCode) {
    return state.permissions?.allows(permissionCode) ?? false;
  }

  void _applyResult(
    Result<WorkspaceSession> result, {
    required bool incrementGeneration,
    bool? isLoading,
    bool? isSwitching,
  }) {
    switch (result) {
      case Success<WorkspaceSession>(value: final session):
        state = state.copyWith(
          workspaces: session.workspaces,
          activeWorkspace: session.activeWorkspace,
          permissions: session.permissions,
          isLoading: isLoading,
          isSwitching: isSwitching,
          clearError: true,
          generation: incrementGeneration
              ? state.generation + 1
              : state.generation,
        );
      case FailureResult<WorkspaceSession>(failure: final failure):
        state = state.copyWith(
          isLoading: isLoading,
          isSwitching: isSwitching,
          errorMessage: _workspaceMessage(failure),
        );
    }
  }
}

String _workspaceMessage(Failure failure) {
  if (failure.kind == FailureKind.forbidden) {
    return failure.message.isEmpty
        ? 'Bạn không có quyền truy cập workspace này.'
        : failure.message;
  }
  return failure.message;
}
