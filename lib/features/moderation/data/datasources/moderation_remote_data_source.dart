import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/moderation.dart';

final class ModerationRemoteDataSource {
  const ModerationRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<ModerationReport> createReport({
    required String workspaceId,
    required ModerationTargetType targetType,
    required String targetId,
    required ModerationReportReason reason,
    String? details,
  }) async {
    final cleanDetails = details?.trim();
    final response = await _api.post<Object>(
      '${_moderationBase(workspaceId)}/reports',
      data: {
        'target_type': targetType.apiValue,
        'target_id': targetId.trim(),
        'reason': reason.apiValue,
        if (cleanDetails != null && cleanDetails.isNotEmpty)
          'details': cleanDetails,
      },
    );
    return _reportFromMap(
      envelopeItem(response.data, 'report'),
      fallbackWorkspaceId: workspaceId,
      fallbackTargetType: targetType,
      fallbackTargetId: targetId,
      fallbackReason: reason,
      fallbackDetails: cleanDetails,
    );
  }

  Future<List<BlockedUser>> listBlockedUsers({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '${_workspaceBase(workspaceId)}/blocks',
    );
    return envelopeList(
      response.data,
      'blocks',
    ).map(_blockedUserFromMap).toList(growable: false);
  }

  Future<BlockedUser> blockUser({
    required String workspaceId,
    required String blockedUserId,
    String? reason,
  }) async {
    final cleanReason = reason?.trim();
    final response = await _api.post<Object>(
      '${_workspaceBase(workspaceId)}/blocks',
      data: {
        'blocked_user_id': blockedUserId.trim(),
        if (cleanReason != null && cleanReason.isNotEmpty)
          'reason': cleanReason,
      },
    );
    final block = _blockedUserFromMap(
      envelopeItem(response.data, 'block'),
      fallbackBlockedUserId: blockedUserId,
      fallbackReason: cleanReason,
    );
    return block;
  }

  Future<void> unblockUser({
    required String workspaceId,
    required String blockedUserId,
  }) async {
    await _api.delete<Object>(
      '${_workspaceBase(workspaceId)}/blocks/${_e(blockedUserId)}',
    );
  }
}

ModerationReport _reportFromMap(
  JsonMap map, {
  required String fallbackWorkspaceId,
  required ModerationTargetType fallbackTargetType,
  required String fallbackTargetId,
  required ModerationReportReason fallbackReason,
  String? fallbackDetails,
}) {
  return ModerationReport(
    id: stringField(map, const ['id', 'report_id', 'reportId']),
    workspaceId: stringField(map, const [
      'workspace_id',
      'workspaceId',
    ], fallback: fallbackWorkspaceId),
    targetType: map.containsKey('target_type') || map.containsKey('targetType')
        ? moderationTargetTypeFromApi(
            stringField(map, const ['target_type', 'targetType']),
          )
        : fallbackTargetType,
    targetId: stringField(map, const [
      'target_id',
      'targetId',
    ], fallback: fallbackTargetId),
    reason: map.containsKey('reason')
        ? moderationReportReasonFromApi(stringField(map, const ['reason']))
        : fallbackReason,
    details: nullableStringField(map, const ['details']) ?? fallbackDetails,
    status: stringField(map, const ['status'], fallback: 'pending'),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

BlockedUser _blockedUserFromMap(
  JsonMap map, {
  String? fallbackBlockedUserId,
  String? fallbackReason,
}) {
  final user = jsonMap(
    field(map, const ['user', 'blocked_user', 'blockedUser']),
  );
  return BlockedUser(
    blockedUserId: stringField(
      map,
      const ['blocked_user_id', 'blockedUserId', 'user_id', 'userId'],
      fallback: stringField(user, const [
        'id',
      ], fallback: fallbackBlockedUserId ?? ''),
    ),
    displayName:
        nullableStringField(map, const [
          'blocked_display_name',
          'display_name',
          'displayName',
        ]) ??
        nullableStringField(user, const [
          'display_name',
          'displayName',
          'name',
        ]),
    username:
        nullableStringField(map, const ['blocked_username', 'username']) ??
        nullableStringField(user, const ['username']),
    avatarUrl:
        nullableStringField(map, const [
          'blocked_avatar_url',
          'avatar_url',
          'avatarUrl',
        ]) ??
        nullableStringField(user, const ['avatar_url', 'avatarUrl']),
    reason: nullableStringField(map, const ['reason']) ?? fallbackReason,
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

String _workspaceBase(String workspaceId) =>
    '/api/v1/workspaces/${_e(workspaceId)}';

String _moderationBase(String workspaceId) =>
    '${_workspaceBase(workspaceId)}/moderation';

String _e(String value) => Uri.encodeComponent(value.trim());
