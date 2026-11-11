import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/approval.dart';

/// Yêu cầu phê duyệt: `/api/v1/workspaces/{ws}/approvals`.
final class ApprovalRemoteDataSource {
  const ApprovalRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<ApprovalPage> list({
    required String workspaceId,
    required ApprovalFilter filter,
    String? cursor,
    int limit = 50,
  }) async {
    final response = await _api.get<Object>(
      _base(workspaceId),
      queryParameters: {
        'status': filter.apiValue,
        'limit': limit,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    final data = jsonMap(envelopeData(response.data));
    final items = envelopeList(
      response.data,
      'approvals',
    ).map(approvalFromMap).where((item) => item.id.isNotEmpty).toList();
    final next = stringField(data, const ['next_cursor', 'nextCursor']);
    return ApprovalPage(items: items, nextCursor: next.isEmpty ? null : next);
  }

  Future<ApprovalRequest> get({
    required String workspaceId,
    required String approvalId,
  }) async {
    final response = await _api.get<Object>(_item(workspaceId, approvalId));
    return approvalFromMap(envelopeItem(response.data, 'approval'));
  }

  Future<ApprovalRequest> decide({
    required String workspaceId,
    required String approvalId,
    required ApprovalDecisionKind decision,
    String comment = '',
  }) async {
    final response = await _api.post<Object>(
      '${_item(workspaceId, approvalId)}/decisions',
      data: {'decision': decision.apiValue, 'comment': comment},
    );
    return approvalFromMap(envelopeItem(response.data, 'approval'));
  }

  String _base(String workspaceId) =>
      '/api/v1/workspaces/${Uri.encodeComponent(workspaceId.trim())}/approvals';

  String _item(String workspaceId, String approvalId) =>
      '${_base(workspaceId)}/${Uri.encodeComponent(approvalId.trim())}';
}

/// Đọc một `ApprovalRequest` theo hợp đồng; trường thiếu thì dùng giá trị an
/// toàn (`can_decide` thiếu = không được duyệt).
ApprovalRequest approvalFromMap(JsonMap map) {
  final rawChannel = stringField(map, const ['channel_id']);
  final requestedBy = stringField(map, const ['requested_by']);
  final rawMode = stringField(map, const ['execution_mode']);
  final result = jsonMap(field(map, const ['result']));
  final resultExecutor = stringField(result, const ['executor']);
  final resultError = stringField(result, const ['error']);
  return ApprovalRequest(
    id: stringField(map, const ['id', 'approval_id']),
    workspaceId: stringField(map, const ['workspace_id']),
    status: ApprovalStatus.fromApi(stringField(map, const ['status'])),
    title: stringField(map, const ['title']),
    action: stringField(map, const ['action']),
    resourceType: stringField(map, const ['resource_type']),
    resourceId: stringField(map, const ['resource_id']),
    payload: Map<String, Object?>.from(jsonMap(field(map, const ['payload']))),
    channelId: rawChannel.isEmpty ? null : rawChannel,
    source: stringField(map, const ['source'], fallback: 'user'),
    requestedBy: requestedBy.isEmpty ? null : requestedBy,
    requiredApprovals: intField(map, const ['required_approvals'], fallback: 1),
    approvalsCount: intField(map, const ['approvals_count']),
    expiresAt: _time(field(map, const ['expires_at'])),
    decidedAt: _time(field(map, const ['decided_at'])),
    createdAt: _time(field(map, const ['created_at'])),
    canDecide: boolField(map, const ['can_decide']),
    executionMode: rawMode.isEmpty
        ? null
        : ApprovalExecutionMode.fromApi(rawMode),
    executionStartedAt: _time(field(map, const ['execution_started_at'])),
    reportedAt: _time(field(map, const ['reported_at'])),
    resultExecutor: resultExecutor.isEmpty ? null : resultExecutor,
    resultError: resultError.isEmpty ? null : resultError,
    decisions: jsonMapList(field(map, const ['decisions']))
        .map(
          (vote) => ApprovalVote(
            userId: stringField(vote, const ['user_id']),
            decision: ApprovalDecisionKind.fromApi(
              stringField(vote, const ['decision']),
            ),
            comment: stringField(vote, const ['comment']),
            createdAt: _time(field(vote, const ['created_at'])),
          ),
        )
        .toList(growable: false),
  );
}

DateTime? _time(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
}
