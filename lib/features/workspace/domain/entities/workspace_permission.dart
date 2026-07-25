final class WorkspacePermission {
  const WorkspacePermission({
    required this.id,
    required this.code,
    required this.module,
    required this.action,
    required this.name,
    this.description,
  });

  final String id;
  final String code;
  final String module;
  final String action;
  final String name;
  final String? description;
}

final class PermissionSet {
  PermissionSet(Iterable<WorkspacePermission> permissions)
    : _codes = {
        for (final permission in permissions)
          permission.code.trim().toLowerCase(),
      };

  final Set<String> _codes;

  bool allows(String permissionCode) {
    return _codes.contains(permissionCode.trim().toLowerCase());
  }

  bool allowsAny(Iterable<String> permissionCodes) {
    return permissionCodes.any(allows);
  }

  bool allowsAll(Iterable<String> permissionCodes) {
    return permissionCodes.every(allows);
  }

  Set<String> get codes => Set.unmodifiable(_codes);
}
