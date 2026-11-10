import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/device_approval.dart';

/// `/api/v1/auth/device-approvals*` (Lõi 2.3).
final class DeviceApprovalRemoteDataSource {
  const DeviceApprovalRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<MyDeviceApproval> mine() async {
    final response = await _api.get<Object>('/api/v1/auth/device-approvals/me');
    final map = envelopeItem(response.data, 'approval');
    return MyDeviceApproval(
      sessionId: stringField(map, const ['session_id']),
      approvalStatus: stringField(map, const [
        'approval_status',
      ], fallback: 'pending').trim().toLowerCase(),
      approvalExpiresAt: nullableDateTimeField(map, const [
        'approval_expires_at',
      ]),
      mode: stringField(map, const ['mode'], fallback: 'off').toLowerCase(),
      requiredRoles: _stringList(field(map, const ['required_roles'])),
      decisions: _decisions(field(map, const ['decisions'])),
      hasTrustedDevice: boolField(map, const ['has_trusted_device']),
    );
  }

  Future<List<DeviceApprovalRequest>> listPending(
    DeviceApprovalScope scope,
  ) async {
    final response = await _api.get<Object>(
      '/api/v1/auth/device-approvals',
      queryParameters: {'scope': scope.value},
    );
    // Hợp đồng chưa chốt tên khoá danh sách: nhận mảng trực tiếp hoặc
    // `approvals` / `items` / `sessions`.
    final items = [
      for (final key in const ['approvals', 'items', 'sessions'])
        envelopeList(response.data, key),
    ].firstWhere((list) => list.isNotEmpty, orElse: () => const []);
    return items
        .map(deviceApprovalRequestFromMap)
        .where((item) => item.sessionId.isNotEmpty)
        .toList(growable: false);
  }

  Future<DeviceApprovalResult> approve(String sessionId) {
    return _decide(sessionId, 'approve');
  }

  Future<DeviceApprovalResult> reject(String sessionId) {
    return _decide(sessionId, 'reject');
  }

  Future<DeviceApprovalResult> _decide(String sessionId, String action) async {
    final id = Uri.encodeComponent(sessionId.trim());
    final response = await _api.post<Object>(
      '/api/v1/auth/device-approvals/$id/$action',
      data: const <String, Object?>{},
    );
    final map = envelopeItem(response.data, 'approval');
    return DeviceApprovalResult(
      sessionId: stringField(map, const ['session_id'], fallback: sessionId),
      approvalStatus: stringField(map, const [
        'approval_status',
      ], fallback: action == 'reject' ? 'rejected' : 'pending').toLowerCase(),
    );
  }
}

/// Dùng cho phần tử danh sách lẫn payload WebSocket `DeviceApprovalRequested`
/// (`user_id`, `user_display_name` nằm phẳng).
DeviceApprovalRequest deviceApprovalRequestFromMap(JsonMap map) {
  final user = jsonMap(field(map, const ['user']));
  return DeviceApprovalRequest(
    sessionId: stringField(map, const ['session_id']).trim(),
    myRole: stringField(map, const ['my_role'], fallback: 'self').toLowerCase(),
    userId:
        nullableStringField(user, const ['id']) ??
        nullableStringField(map, const ['user_id']),
    userDisplayName:
        nullableStringField(user, const ['display_name']) ??
        nullableStringField(map, const ['user_display_name']),
    userEmail: nullableStringField(user, const ['email']),
    userAvatarUrl: nullableStringField(user, const ['avatar_url']),
    deviceName: nullableStringField(map, const ['device_name']),
    ipAddress: nullableStringField(map, const ['ip_address']),
    userAgent: nullableStringField(map, const ['user_agent']),
    authMethod: nullableStringField(map, const ['auth_method']),
    createdAt: nullableDateTimeField(map, const ['created_at']),
    approvalExpiresAt: nullableDateTimeField(map, const [
      'approval_expires_at',
    ]),
    decisions: _decisions(field(map, const ['decisions'])),
  );
}

List<DeviceApprovalDecision> _decisions(Object? value) {
  return jsonMapList(value)
      .map(
        (item) => DeviceApprovalDecision(
          approverRole: stringField(item, const ['approver_role']),
          decision: stringField(item, const ['decision']),
          createdAt: nullableDateTimeField(item, const ['created_at']),
        ),
      )
      .toList(growable: false);
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
