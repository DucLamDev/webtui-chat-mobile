import '../../domain/entities/workspace.dart';
import '../../domain/entities/workspace_permission.dart';

final class WorkspaceDto {
  const WorkspaceDto({
    required this.id,
    required this.slug,
    required this.name,
    required this.plan,
    required this.status,
    this.description,
    this.ownerId,
  });

  final String id;
  final String slug;
  final String name;
  final String plan;
  final String status;
  final String? description;
  final String? ownerId;

  factory WorkspaceDto.fromJson(Map<String, dynamic> json) {
    return WorkspaceDto(
      id: _string(json['id']),
      slug: _string(json['slug']),
      name: _string(json['name']),
      plan: _string(json['plan'], fallback: 'free'),
      status: _string(json['status'], fallback: 'active'),
      description: _nullableString(json['description']),
      ownerId: _nullableString(json['owner_id']),
    );
  }

  Workspace toDomain() {
    return Workspace(
      id: id,
      slug: slug,
      name: name,
      plan: plan,
      status: status,
      description: description,
      ownerId: ownerId,
    );
  }
}

final class WorkspacePermissionDto {
  const WorkspacePermissionDto({
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

  factory WorkspacePermissionDto.fromJson(Map<String, dynamic> json) {
    return WorkspacePermissionDto(
      id: _string(json['id']),
      code: _string(json['code']),
      module: _string(json['module']),
      action: _string(json['action']),
      name: _string(json['name']),
      description: _nullableString(json['description']),
    );
  }

  WorkspacePermission toDomain() {
    return WorkspacePermission(
      id: id,
      code: code,
      module: module,
      action: action,
      name: name,
      description: description,
    );
  }
}

List<WorkspaceDto> workspacesFromEnvelope(Object? envelope) {
  final json = _unwrapDataMap(envelope);
  final workspaces = json['workspaces'];
  if (workspaces is! List) {
    throw const FormatException('Workspace response missing workspaces list.');
  }
  return workspaces
      .map((workspace) => WorkspaceDto.fromJson(_mapOf(workspace)))
      .toList(growable: false);
}

List<WorkspacePermissionDto> permissionsFromEnvelope(Object? envelope) {
  final json = _unwrapDataMap(envelope);
  final permissions = json['permissions'];
  if (permissions is! List) {
    throw const FormatException(
      'Permission response missing permissions list.',
    );
  }
  return permissions
      .map((permission) => WorkspacePermissionDto.fromJson(_mapOf(permission)))
      .toList(growable: false);
}

Map<String, dynamic> _unwrapDataMap(Object? envelope) {
  final root = _mapOf(envelope);
  final data = root.containsKey('data') ? root['data'] : root;
  return _mapOf(data);
}

Map<String, dynamic> _mapOf(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw const FormatException('Expected JSON object.');
}

String _string(Object? value, {String fallback = ''}) {
  return value?.toString() ?? fallback;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}
