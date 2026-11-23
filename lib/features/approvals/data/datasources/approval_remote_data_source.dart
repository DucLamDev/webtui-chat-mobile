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
  final externalKey = _text(map, const ['external_key']);
  final resultLabel = _text(map, const ['result_label']);
  // Lý do huỷ: đọc ở gốc phiếu, dự phòng trong `result` (máy chủ có thể để
  // cạnh kết quả thực hiện).
  final cancelReason = _text(map, const [
    'cancel_reason',
    'cancelled_reason',
    'cancellation_reason',
  ]).ifEmpty(() => _text(result, const ['cancel_reason', 'reason']));
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
            userEmail: _text(vote, const ['user_email', 'email']),
            decision: ApprovalDecisionKind.fromApi(
              stringField(vote, const ['decision']),
            ),
            comment: _text(vote, const ['comment', 'note']),
            createdAt: _time(field(vote, const ['created_at', 'decided_at'])),
          ),
        )
        .toList(growable: false),
    content: approvalContentFromJson(field(map, const ['display'])),
    externalKey: externalKey.isEmpty ? null : externalKey,
    cancelReason: cancelReason.isEmpty ? null : cancelReason,
    resultLabel: resultLabel.isEmpty
        ? null
        : resultLabel.length > approvalResultLabelMaxLength
        ? resultLabel.substring(0, approvalResultLabelMaxLength)
        : resultLabel,
  );
}

/// Giới hạn khi đọc khối `display` (khớp giới hạn máy chủ nhận vào), để dữ
/// liệu lạ không làm màn hình quá dài.
const approvalContentMaxTextLength = 4000;
const approvalContentMaxFields = 8;
const approvalResultLabelMaxLength = 40;

/// Đọc khối `display`. Thiếu / sai kiểu / rỗng thì trả `null` (hiện như cũ).
/// Ảnh và liên kết không phải `https://` bị bỏ.
ApprovalContent? approvalContentFromJson(Object? value) {
  final map = jsonMapOrNull(value);
  if (map == null) return null;
  final rawText = _text(map, const ['text'], trim: false);
  final text = rawText.length > approvalContentMaxTextLength
      ? rawText.substring(0, approvalContentMaxTextLength)
      : rawText;
  final image = approvalHttpsUri(_text(map, const ['image_url', 'imageUrl']));
  final fields = <ApprovalContentField>[];
  for (final item in jsonMapList(field(map, const ['fields']))) {
    final label = _text(item, const ['label']);
    final fieldValue = _text(item, const ['value']);
    if (label.isEmpty || fieldValue.isEmpty) continue;
    fields.add(ApprovalContentField(label: label, value: fieldValue));
    if (fields.length >= approvalContentMaxFields) break;
  }
  final rawLink = jsonMapOrNull(field(map, const ['link']));
  ApprovalContentLink? link;
  if (rawLink != null) {
    final url = _text(rawLink, const ['url']);
    if (approvalHttpsUri(url) != null) {
      link = ApprovalContentLink(
        label: _text(rawLink, const ['label']),
        url: url,
      );
    }
  }
  final content = ApprovalContent(
    text: text.trim().isEmpty ? '' : text,
    imageUrl: image?.toString(),
    fields: List.unmodifiable(fields),
    link: link,
  );
  return content.isEmpty ? null : content;
}

/// Chỉ nhận giá trị chuỗi (không biến map / list thành chữ).
String _text(JsonMap map, Iterable<String> keys, {bool trim = true}) {
  final value = field(map, keys);
  if (value is! String) return '';
  return trim ? value.trim() : value.replaceAll('\r\n', '\n');
}

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}

DateTime? _time(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : DateTime.tryParse(text)?.toLocal();
}
