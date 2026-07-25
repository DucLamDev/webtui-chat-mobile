abstract interface class WorkspaceSessionRepository {
  Future<String?> readActiveWorkspaceId();

  Future<void> saveActiveWorkspaceId(String workspaceId);

  Future<void> resetRuntimeForSwitch({
    required String? previousWorkspaceId,
    required String nextWorkspaceId,
  });
}
