import 'package:dio/dio.dart';

import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/entities/conversation_summary.dart';

final class ConversationRemoteDataSource {
  const ConversationRemoteDataSource(this._api);

  final ApiTransport _api;

  String _collaborationPath(String workspaceId, String channelId) =>
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/collaboration';

  Future<CollaborationSettings> getCollaborationSettings({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      _collaborationPath(workspaceId, channelId),
    );
    return _collaborationSettingsFromMap(
      envelopeItem(response.data, 'settings'),
    );
  }

  Future<List<CollaborationUserGroup>> listCollaborationUserGroups({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/departments',
    );
    return envelopeList(response.data, 'departments')
        .map(
          (map) => CollaborationUserGroup(
            id: stringField(map, const ['id']),
            name: stringField(map, const ['name']),
            memberCount: intField(map, const ['member_count']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<String>> listCollaborationUserGroupMemberIds({
    required String workspaceId,
    required String groupId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/departments/${_e(groupId)}/members',
    );
    return envelopeList(response.data, 'members')
        .map((map) => map['user_id']?.toString().trim() ?? '')
        .where((userId) => userId.isNotEmpty)
        .toList(growable: false);
  }

  Future<CollaborationSettings> updateCollaborationSettings({
    required String workspaceId,
    required String channelId,
    required CollaborationRoomMode roomMode,
    required bool lobbyEnabled,
    required bool chatLocked,
    required bool guestMicrophoneEnabled,
    required bool guestCameraEnabled,
    required CollaborationParticipantRole defaultParticipantRole,
  }) async {
    final response = await _api.put<Object>(
      _collaborationPath(workspaceId, channelId),
      data: {
        'room_mode': roomMode.name,
        'meeting_provider': 'jitsi',
        'lobby_enabled': lobbyEnabled,
        'chat_locked': chatLocked,
        'guest_microphone_enabled': guestMicrophoneEnabled,
        'guest_camera_enabled': guestCameraEnabled,
        'default_participant_role': defaultParticipantRole.name,
      },
    );
    return _collaborationSettingsFromMap(
      envelopeItem(response.data, 'settings'),
    );
  }

  Future<CollaborationSettings> promoteConversation({
    required String workspaceId,
    required String channelId,
    required String name,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/promote',
      data: {'name': name},
    );
    return _collaborationSettingsFromMap(
      envelopeItem(response.data, 'settings'),
    );
  }

  Future<PublicConversationLink> createPublicConversationLink({
    required String workspaceId,
    required String channelId,
    required CollaborationRoomMode roomMode,
    required String password,
    required bool lobbyEnabled,
    required bool chatLocked,
    required bool guestMicrophoneEnabled,
    required bool guestCameraEnabled,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/public-link',
      data: {
        'room_mode': roomMode == CollaborationRoomMode.webinar
            ? 'webinar'
            : 'public',
        'password': password,
        'lobby_enabled': lobbyEnabled,
        'chat_locked': chatLocked,
        'guest_microphone_enabled': guestMicrophoneEnabled,
        'guest_camera_enabled': guestCameraEnabled,
      },
    );
    final map = envelopeItem(response.data, 'link');
    return PublicConversationLink(
      settings: _collaborationSettingsFromMap(map),
      token: stringField(map, const ['token']),
    );
  }

  Future<CollaborationSettings> disablePublicConversationLink({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.delete<Object>(
      '${_collaborationPath(workspaceId, channelId)}/public-link',
    );
    return _collaborationSettingsFromMap(
      envelopeItem(response.data, 'settings'),
    );
  }

  Future<List<CollaborationGuest>> listCollaborationGuests({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/guests',
    );
    return envelopeList(
      response.data,
      'guests',
    ).map(_collaborationGuestFromMap).toList(growable: false);
  }

  Future<CollaborationGuest> moderateCollaborationGuest({
    required String workspaceId,
    required String channelId,
    required String requestId,
    required bool approve,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/guests/${_e(requestId)}/${approve ? 'approve' : 'reject'}',
      data: const {},
    );
    return _collaborationGuestFromMap(envelopeItem(response.data, 'guest'));
  }

  Future<CollaborationDocument> getCollaborationDocument({
    required String workspaceId,
    required String channelId,
    required String kind,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/documents/${_e(kind)}',
    );
    return _collaborationDocumentFromMap(
      envelopeItem(response.data, 'document'),
    );
  }

  Future<CollaborationDocument> updateCollaborationDocument({
    required String workspaceId,
    required String channelId,
    required String kind,
    required Map<String, Object?> content,
    required int expectedVersion,
  }) async {
    final response = await _api.put<Object>(
      '${_collaborationPath(workspaceId, channelId)}/documents/${_e(kind)}',
      data: {'content': content, 'expected_version': expectedVersion},
    );
    return _collaborationDocumentFromMap(
      envelopeItem(response.data, 'document'),
    );
  }

  Future<List<CollaborationTask>> listCollaborationTasks({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/tasks',
    );
    return envelopeList(
      response.data,
      'tasks',
    ).map(_collaborationTaskFromMap).toList(growable: false);
  }

  Future<CollaborationTask> createCollaborationTask({
    required String workspaceId,
    required String channelId,
    required String title,
    String? sourceMessageId,
    String? assigneeUserId,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/tasks',
      data: compactMap({
        'title': title,
        'source_message_id': sourceMessageId,
        'assignee_user_id': assigneeUserId,
      }),
    );
    return _collaborationTaskFromMap(envelopeItem(response.data, 'task'));
  }

  Future<CollaborationTask> updateCollaborationTask({
    required String workspaceId,
    required String channelId,
    required String taskId,
    required String status,
  }) async {
    final response = await _api.patch<Object>(
      '${_collaborationPath(workspaceId, channelId)}/tasks/${_e(taskId)}',
      data: {'status': status},
    );
    return _collaborationTaskFromMap(envelopeItem(response.data, 'task'));
  }

  Future<List<CollaborationRole>> listCollaborationRoles({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/roles',
    );
    return envelopeList(
      response.data,
      'roles',
    ).map(_collaborationRoleFromMap).toList(growable: false);
  }

  Future<CollaborationRole> updateCollaborationRole({
    required String workspaceId,
    required String channelId,
    required String userId,
    required CollaborationParticipantRole role,
  }) async {
    final response = await _api.patch<Object>(
      '${_collaborationPath(workspaceId, channelId)}/roles/${_e(userId)}',
      data: {'role': role.name},
    );
    return _collaborationRoleFromMap(envelopeItem(response.data, 'role'));
  }

  Future<List<BreakoutRoom>> listBreakoutRooms({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/breakouts',
    );
    return envelopeList(
      response.data,
      'breakout_rooms',
    ).map(_breakoutRoomFromMap).toList(growable: false);
  }

  Future<BreakoutRoom> createBreakoutRoom({
    required String workspaceId,
    required String channelId,
    required String name,
    required List<String> assignedUserIds,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/breakouts',
      data: {'name': name, 'assigned_user_ids': assignedUserIds},
    );
    return _breakoutRoomFromMap(envelopeItem(response.data, 'breakout_room'));
  }

  Future<List<BreakoutRoom>> returnBreakoutRooms({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/breakouts/return',
      data: const {},
    );
    return envelopeList(
      response.data,
      'breakout_rooms',
    ).map(_breakoutRoomFromMap).toList(growable: false);
  }

  Future<List<BreakoutRoom>> setupBreakoutRooms({
    required String workspaceId,
    required String channelId,
    required String assignmentMode,
    required int roomCount,
    bool allowSelfSelect = false,
  }) async {
    final response = await _api.put<Object>(
      '${_collaborationPath(workspaceId, channelId)}/breakouts/setup',
      data: {
        'assignment_mode': assignmentMode,
        'room_count': roomCount,
        'allow_self_select': allowSelfSelect,
        'rooms': const [],
      },
    );
    return envelopeList(
      response.data,
      'breakout_rooms',
    ).map(_breakoutRoomFromMap).toList(growable: false);
  }

  Future<List<BreakoutRoom>> startBreakoutRooms({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/breakouts/start',
      data: const {},
    );
    return envelopeList(
      response.data,
      'breakout_rooms',
    ).map(_breakoutRoomFromMap).toList(growable: false);
  }

  Future<List<BreakoutRoom>> joinBreakoutRoom({
    required String workspaceId,
    required String channelId,
    required String roomId,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/breakouts/${_e(roomId)}/join',
      data: const {},
    );
    return envelopeList(
      response.data,
      'breakout_rooms',
    ).map(_breakoutRoomFromMap).toList(growable: false);
  }

  Future<void> broadcastToBreakouts({
    required String workspaceId,
    required String channelId,
    required String body,
  }) async {
    await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/breakouts/broadcast',
      data: {'body': body},
    );
  }

  Future<TalkHome> getTalkHome({required String workspaceId}) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/talk/home',
    );
    final map = envelopeItem(response.data, 'home');
    return TalkHome(
      upcomingMeetings: jsonMapList(
        map['upcoming_meetings'],
      ).map(_channelMeetingFromMap).toList(growable: false),
      activeVoiceRooms: jsonMapList(
        map['active_voice_rooms'],
      ).map(_voiceRoomFromMap).toList(growable: false),
      openTasks: jsonMapList(
        map['open_tasks'],
      ).map(_collaborationTaskFromMap).toList(growable: false),
      unreadMentions: intField(map, const ['unread_mentions']),
      pendingReminders: intField(map, const ['pending_reminders']),
      missedCalls: intField(map, const ['missed_calls']),
    );
  }

  Future<List<ChannelMeeting>> listMeetings({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/meetings',
    );
    return envelopeList(
      response.data,
      'meetings',
    ).map(_channelMeetingFromMap).toList(growable: false);
  }

  Future<ChannelMeeting> createMeeting({
    required String workspaceId,
    required String channelId,
    required String title,
    required DateTime startsAt,
    DateTime? endsAt,
    DateTime? lobbyOpensAt,
    DateTime? cleanupAfter,
    String description = '',
    String roomPolicy = 'keep',
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/meetings',
      data: compactMap({
        'title': title,
        'description': description,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'lobby_opens_at': lobbyOpensAt?.toUtc().toIso8601String(),
        'room_policy': roomPolicy,
        'cleanup_after': cleanupAfter?.toUtc().toIso8601String(),
      }),
    );
    return _channelMeetingFromMap(envelopeItem(response.data, 'meeting'));
  }

  Future<ChannelMeeting> transitionMeeting({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String action,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/meetings/${_e(meetingId)}/${_e(action)}',
      data: const {},
    );
    return _channelMeetingFromMap(envelopeItem(response.data, 'meeting'));
  }

  Future<VoiceRoom> getVoiceRoom({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/voice-room',
    );
    return _voiceRoomFromMap(envelopeItem(response.data, 'voice_room'));
  }

  Future<VoiceRoom> setVoiceRoom({
    required String workspaceId,
    required String channelId,
    required bool active,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/voice-room/${active ? 'start' : 'stop'}',
      data: const {},
    );
    return _voiceRoomFromMap(envelopeItem(response.data, 'voice_room'));
  }

  Future<List<SharedConversationItem>> listSharedItems({
    required String workspaceId,
    required String channelId,
    String? kind,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/shared-items',
      queryParameters: compactMap({'kind': kind, 'limit': 100}),
    );
    return envelopeList(
      response.data,
      'items',
    ).map(_sharedItemFromMap).toList(growable: false);
  }

  Future<RecordingPolicy> getRecordingPolicy({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/recording-policy',
    );
    return _recordingPolicyFromMap(
      envelopeItem(response.data, 'recording_policy'),
    );
  }

  Future<RecordingPolicy> updateRecordingPolicy({
    required String workspaceId,
    required String channelId,
    required RecordingPolicy policy,
  }) async {
    final response = await _api.put<Object>(
      '${_collaborationPath(workspaceId, channelId)}/recording-policy',
      data: {
        'enabled': policy.enabled,
        'consent_required': policy.consentRequired,
        'retention_days': policy.retentionDays,
        'transcription_enabled': policy.transcriptionEnabled,
        'summary_enabled': policy.summaryEnabled,
        'provider': policy.provider,
      },
    );
    return _recordingPolicyFromMap(
      envelopeItem(response.data, 'recording_policy'),
    );
  }

  Future<List<ChannelRecording>> listRecordings({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '${_collaborationPath(workspaceId, channelId)}/recordings',
    );
    return envelopeList(
      response.data,
      'recordings',
    ).map(_channelRecordingFromMap).toList(growable: false);
  }

  Future<ChannelRecording> startRecording({
    required String workspaceId,
    required String channelId,
    String? meetingId,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/recordings',
      data: compactMap({
        'meeting_id': meetingId,
        'participant_user_ids': const <String>[],
      }),
    );
    return _channelRecordingFromMap(envelopeItem(response.data, 'recording'));
  }

  Future<ChannelRecording> setRecordingConsent({
    required String workspaceId,
    required String channelId,
    required String recordingId,
    required bool consented,
  }) async {
    final response = await _api.put<Object>(
      '${_collaborationPath(workspaceId, channelId)}/recordings/${_e(recordingId)}/consent',
      data: {'consented': consented},
    );
    return _channelRecordingFromMap(envelopeItem(response.data, 'recording'));
  }

  Future<ChannelRecording> stopRecording({
    required String workspaceId,
    required String channelId,
    required String recordingId,
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/recordings/${_e(recordingId)}/stop',
      data: const {},
    );
    return _channelRecordingFromMap(envelopeItem(response.data, 'recording'));
  }

  Future<TalkIntegration> getTalkIntegration({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/talk/integrations',
    );
    return _talkIntegrationFromMap(envelopeItem(response.data, 'integration'));
  }

  Future<TalkSummary> summarizeChannel({
    required String workspaceId,
    required String channelId,
    DateTime? since,
    String language = 'vi',
  }) async {
    final response = await _api.post<Object>(
      '${_collaborationPath(workspaceId, channelId)}/ai/summary',
      data: compactMap({
        'since': since?.toUtc().toIso8601String(),
        'language': language,
      }),
    );
    final map = envelopeItem(response.data, 'summary');
    return TalkSummary(
      summary: stringField(map, const ['summary']),
      decisions: _stringList(map['decisions']),
      actionItems: _stringList(map['action_items']),
      model: stringField(map, const ['model']),
      messageCount: intField(map, const ['message_count']),
      generatedAt: dateTimeField(map, const ['generated_at']),
    );
  }

  Future<List<ConversationSummary>> listDirectConversations({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/direct-conversations',
    );
    return envelopeList(
      response.data,
      'direct_conversations',
    ).map(_directConversationFromMap).toList(growable: false);
  }

  Future<List<ConversationSummary>> listChannels({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels',
    );
    return envelopeList(
      response.data,
      'channels',
    ).map(_channelFromMap).toList(growable: false);
  }

  Future<List<ContactSummary>> listContacts() async {
    final response = await _api.get<Object>('/api/v1/contacts');
    return envelopeList(
      response.data,
      'contacts',
    ).map(_contactFromMap).toList(growable: false);
  }

  Future<List<ContactSummary>> listWorkspaceMembers({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/members',
    );
    return envelopeList(
      response.data,
      'members',
    ).map(_workspaceMemberFromMap).toList(growable: false);
  }

  Future<List<PresenceSummary>> listPresence({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/presence',
      queryParameters: const {'limit': 200},
    );
    return envelopeList(
      response.data,
      'presence',
    ).map(_presenceFromMap).toList(growable: false);
  }

  Future<void> updatePresence({
    required String workspaceId,
    required String deviceId,
    required ConversationPresence status,
    required String platform,
  }) async {
    await _api.put<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/presence/heartbeat',
      data: {
        'device_id': deviceId,
        'status': status.name,
        'metadata': {'platform': platform},
      },
    );
  }

  Future<ConversationSummary> getChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}',
    );
    return _channelFromMap(envelopeItem(response.data, 'channel'));
  }

  Future<ConversationSummary> createChannel({
    required String workspaceId,
    required String slug,
    required String name,
    required String description,
    required ChannelVisibility visibility,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels',
      data: compactMap({
        'slug': slug,
        'name': name,
        'description': description,
        'type': _visibilityToApi(visibility),
      }),
    );
    return _channelFromMap(envelopeItem(response.data, 'channel'));
  }

  Future<ChannelMember> requestJoinChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/join-requests',
      data: const {},
    );
    return _channelMemberFromMap(
      envelopeItem(response.data, 'member'),
      channelId: channelId,
    );
  }

  Future<ConversationSummary> openPrivateSession({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/private-session',
      data: const {},
    );
    return _channelFromMap(envelopeItem(response.data, 'channel'));
  }

  Future<ConversationSummary> createDirectConversation({
    required String workspaceId,
    required List<String> participantIds,
    String? sourceChannelId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/direct-conversations',
      data: compactMap({
        'participant_ids': participantIds,
        'source_channel_id': sourceChannelId,
      }),
    );
    return _directConversationFromMap(
      envelopeItem(response.data, 'direct_conversation'),
    );
  }

  Future<void> markRead({
    required String workspaceId,
    required String channelId,
    required String lastReadMessageId,
  }) async {
    await _api.put<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/read-state',
      data: {'last_read_message_id': lastReadMessageId},
    );
  }

  Future<List<ChannelMember>> listMembers({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/members',
    );
    return envelopeList(response.data, 'members')
        .map((map) => _channelMemberFromMap(map, channelId: channelId))
        .toList(growable: false);
  }

  Future<ChannelMember> addMember({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/members',
      data: {'user_id': userId},
    );
    return _channelMemberFromMap(
      envelopeItem(response.data, 'member'),
      channelId: channelId,
    );
  }

  Future<List<ChannelMember>> listJoinRequests({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/join-requests',
    );
    return envelopeList(response.data, 'join_requests')
        .map((map) => _channelMemberFromMap(map, channelId: channelId))
        .toList(growable: false);
  }

  Future<ChannelMember> approveJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/join-requests/${_e(userId)}/approve',
      data: const {},
    );
    return _channelMemberFromMap(
      envelopeItem(response.data, 'member'),
      channelId: channelId,
    );
  }

  Future<void> rejectJoinRequest({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    await _api.delete<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/join-requests/${_e(userId)}',
    );
  }

  Future<List<ChatMessage>> listMessages({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) async {
    final page = await listMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      limit: limit,
      beforeId: beforeId,
    );
    return page.messages;
  }

  Future<MessagePage> listMessagePage({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages',
      queryParameters: compactMap({'limit': limit, 'before': beforeId}),
    );
    return _messagePageFromResponse(response.data, workspaceId, channelId);
  }

  Future<List<ChatMessage>> searchMessages({
    required String workspaceId,
    required String query,
    String? channelId,
    String? senderId,
    String? kind,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
  }) async {
    final page = await searchMessagePage(
      workspaceId: workspaceId,
      query: query,
      channelId: channelId,
      senderId: senderId,
      kind: kind,
      dateFrom: dateFrom,
      dateTo: dateTo,
      limit: limit,
    );
    return page.messages;
  }

  Future<MessagePage> searchMessagePage({
    required String workspaceId,
    required String query,
    String? channelId,
    String? senderId,
    String? kind,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 30,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/messages/search',
      queryParameters: compactMap({
        'q': query,
        'channel_id': channelId,
        'sender_id': senderId,
        'kind': kind,
        'date_from': _dateParam(dateFrom),
        'date_to': _dateParam(dateTo),
        'limit': limit,
      }),
    );
    return _messagePageFromResponse(
      response.data,
      workspaceId,
      channelId ?? '',
    );
  }

  Future<MessagePage> listThread({
    required String workspaceId,
    required String channelId,
    required String messageId,
    int limit = 50,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/thread',
      queryParameters: {'limit': limit},
    );
    return _messagePageFromResponse(response.data, workspaceId, channelId);
  }

  Future<List<ChatMessage>> listPins({
    required String workspaceId,
    required String channelId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/pins',
    );
    return envelopeList(response.data, 'messages')
        .map((map) => _messageFromMap(map, workspaceId, channelId))
        .toList(growable: false);
  }

  Future<ChatMessage> sendMessage({
    required String workspaceId,
    required String channelId,
    required String body,
    String? clientMessageId,
    String? parentId,
    bool silent = false,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages',
      data: compactMap({
        'body': body,
        'kind': 'text',
        'parent_id': parentId,
        'client_message_id': clientMessageId,
        'mentioned_user_ids': _mentionedUserIds(body),
        'silent': silent,
      }),
      options: clientMessageId == null || clientMessageId.isEmpty
          ? null
          : Options(headers: {'Idempotency-Key': clientMessageId}),
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    );
  }

  Future<void> scheduleMessage({
    required String workspaceId,
    required String channelId,
    required String body,
    required DateTime scheduledFor,
    bool silent = false,
  }) async {
    await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/messages/scheduled',
      queryParameters: {'channel_id': channelId},
      data: {
        'body': body.trim(),
        'kind': 'text',
        'mentioned_user_ids': _mentionedUserIds(body),
        'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        'silent': silent,
      },
    );
  }

  Future<void> createMessageReminder({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required DateTime remindAt,
    String note = '',
  }) async {
    await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/reminders',
      data: {'remind_at': remindAt.toUtc().toIso8601String(), 'note': note},
    );
  }

  Future<ChatMessage> createPoll({
    required String workspaceId,
    required String channelId,
    required String question,
    required List<String> options,
    required bool multiple,
    required bool anonymous,
  }) async {
    const reactions = [
      '1️⃣',
      '2️⃣',
      '3️⃣',
      '4️⃣',
      '5️⃣',
      '6️⃣',
      '7️⃣',
      '8️⃣',
      '9️⃣',
      '🔟',
    ];
    final normalizedQuestion = question.trim();
    final normalizedOptions = options
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .take(reactions.length)
        .toList(growable: false);
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages',
      data: {
        'body': normalizedQuestion,
        'kind': 'event',
        'metadata': {
          'message_type': 'poll',
          'poll': {
            'question': normalizedQuestion,
            'multiple': multiple,
            'anonymous': anonymous,
            'options': [
              for (var index = 0; index < normalizedOptions.length; index++)
                {
                  'id': 'option-${index + 1}',
                  'label': normalizedOptions[index],
                  'reaction': reactions[index],
                },
            ],
          },
        },
      },
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    );
  }

  Future<ChatMessage> editMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String body,
  }) async {
    final response = await _api.patch<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}',
      data: {'body': body},
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    );
  }

  Future<void> deleteMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    await _api.delete<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}',
    );
  }

  Future<ChatMessage> addReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/reactions',
      data: {'emoji': emoji},
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    );
  }

  Future<ChatMessage> removeReaction({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String emoji,
  }) async {
    final response = await _api.delete<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/reactions/${_e(emoji)}',
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    );
  }

  Future<ChatMessage> pinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/pin',
      data: const {},
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      channelId,
    ).copyWith(isPinned: true);
  }

  Future<void> unpinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    await _api.delete<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/pin',
    );
  }

  Future<ChatMessage> forwardMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String targetChannelId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/forward',
      data: {'target_channel_id': targetChannelId},
    );
    return _messageFromMap(
      envelopeItem(response.data, 'message'),
      workspaceId,
      targetChannelId,
    );
  }

  Future<List<ChannelFile>> listFiles({
    required String workspaceId,
    int limit = 40,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/files',
      queryParameters: {'limit': limit},
    );
    return envelopeList(
      response.data,
      'files',
    ).map(_fileFromMap).toList(growable: false);
  }
}

MessagePage _messagePageFromResponse(
  Object? response,
  String workspaceId,
  String channelId,
) {
  final messages = envelopeList(response, 'messages')
      .map((map) {
        final resolvedChannelId = stringField(map, const [
          'channel_id',
          'channelId',
        ], fallback: channelId);
        return _messageFromMap(map, workspaceId, resolvedChannelId);
      })
      .toList(growable: false);
  final meta = _metaMap(response);
  return MessagePage(
    messages: messages,
    nextCursor: nullableStringField(meta, const ['next_cursor', 'nextCursor']),
    hasMore: boolField(meta, const ['has_more', 'hasMore']),
  );
}

JsonMap _metaMap(Object? response) {
  final map = jsonMap(response);
  return jsonMap(field(map, const ['meta']));
}

ConversationSummary _channelFromMap(JsonMap map) {
  final channelId = stringField(map, const ['id', 'channel_id', 'channelId']);
  final workspaceId = stringField(map, const ['workspace_id', 'workspaceId']);
  final visibility = _visibilityFromApi(
    stringField(map, const ['type', 'kind'], fallback: 'public'),
  );
  return ConversationSummary(
    id: channelId,
    workspaceId: workspaceId,
    channelId: channelId,
    kind: visibility == ChannelVisibility.direct
        ? ConversationKind.direct
        : ConversationKind.channel,
    title: stringField(map, const ['name', 'title'], fallback: channelId),
    preview: stringField(map, const ['description', 'preview']),
    avatarLabel: _avatarLabel(stringField(map, const ['name', 'title'])),
    avatarUrl: nullableStringField(map, const ['avatar_url', 'avatarUrl']),
    updatedAt: dateTimeField(map, const ['updated_at', 'updatedAt']),
    unreadCount: intField(map, const ['unread_count', 'unreadCount']),
    favorite: boolField(map, const ['is_favorite', 'favorite']),
    muted:
        stringField(map, const ['membership_status', 'membershipStatus']) ==
        'muted',
    memberCount: intField(map, const ['member_count', 'memberCount']),
    channelVisibility: visibility,
    membershipStatus: _membershipFromApi(
      stringField(map, const ['membership_status', 'membershipStatus']),
    ),
    canManage: boolField(map, const ['can_manage', 'canManage']),
    privateSessionMode: boolField(map, const [
      'private_session_mode',
      'privateSessionMode',
    ]),
  );
}

ConversationSummary _directConversationFromMap(JsonMap map) {
  final userMap = jsonMap(field(map, const ['user']));
  final participantMaps = jsonMapList(field(map, const ['participants']));
  final firstParticipant = participantMaps.isEmpty
      ? const <String, dynamic>{}
      : participantMaps.first;
  final displaySource = userMap.isNotEmpty ? userMap : firstParticipant;
  final lastMessage = jsonMap(
    field(map, const ['last_message', 'lastMessage']),
  );
  final lastMessageCreatedAt = nullableDateTimeField(lastMessage, const [
    'created_at',
    'createdAt',
    'sent_at',
    'sentAt',
  ]);
  final channelId = stringField(map, const ['channel_id', 'channelId', 'id']);
  final workspaceId = stringField(map, const ['workspace_id', 'workspaceId']);
  final participantIds = <String>{
    for (final participant in participantMaps)
      stringField(participant, const ['user_id', 'userId', 'id']),
    stringField(displaySource, const ['user_id', 'userId', 'id']),
  }..removeWhere((id) => id.isEmpty);

  return ConversationSummary(
    id: stringField(map, const ['id'], fallback: channelId),
    workspaceId: workspaceId,
    channelId: channelId,
    kind: ConversationKind.direct,
    title: stringField(displaySource, const [
      'display_name',
      'displayName',
      'username',
      'email',
    ], fallback: 'Tin nhắn riêng'),
    preview: stringField(lastMessage, const ['body']),
    avatarLabel: _avatarLabel(
      stringField(displaySource, const [
        'display_name',
        'displayName',
        'username',
        'email',
      ]),
    ),
    avatarUrl: nullableStringField(displaySource, const [
      'avatar_url',
      'avatarUrl',
    ]),
    peerUserId: nullableStringField(displaySource, const [
      'user_id',
      'userId',
      'id',
    ]),
    updatedAt:
        lastMessageCreatedAt ??
        dateTimeField(map, const ['updated_at', 'updatedAt']),
    unreadCount: intField(map, const ['unread_count', 'unreadCount']),
    participantIds: participantIds.toList(growable: false),
    channelVisibility: ChannelVisibility.direct,
    membershipStatus: MembershipStatus.active,
  );
}

PresenceSummary _presenceFromMap(JsonMap map) {
  return PresenceSummary(
    userId: stringField(map, const ['user_id', 'userId']),
    status: switch (stringField(map, const [
      'status',
    ], fallback: 'offline').toLowerCase()) {
      'online' => ConversationPresence.online,
      'away' => ConversationPresence.away,
      _ => ConversationPresence.offline,
    },
    lastHeartbeatAt: dateTimeField(map, const [
      'last_heartbeat_at',
      'lastHeartbeatAt',
    ]),
  );
}

ContactSummary _contactFromMap(JsonMap map) {
  final userMap = jsonMap(field(map, const ['user']));
  final source = userMap.isEmpty ? map : userMap;
  return ContactSummary(
    userId: stringField(source, const [
      'id',
      'user_id',
      'userId',
    ], fallback: stringField(map, const ['requester_id', 'receiver_id'])),
    displayName: stringField(source, const [
      'display_name',
      'displayName',
      'username',
      'email',
    ]),
    username: stringField(source, const ['username']),
    email: stringField(source, const ['email']),
    status: stringField(source, const ['status'], fallback: 'active'),
    avatarUrl: nullableStringField(source, const ['avatar_url', 'avatarUrl']),
    title: nullableStringField(source, const ['title', 'role']),
  );
}

ContactSummary _workspaceMemberFromMap(JsonMap map) {
  final userMap = jsonMap(field(map, const ['user']));
  final source = userMap.isEmpty ? map : {...userMap, ...map};
  return ContactSummary(
    userId: stringField(source, const ['user_id', 'userId', 'id']),
    displayName: stringField(source, const [
      'display_name',
      'displayName',
      'username',
      'email',
    ]),
    username: stringField(source, const ['username']),
    email: stringField(source, const ['email']),
    status: stringField(source, const ['status'], fallback: 'active'),
    avatarUrl: nullableStringField(source, const ['avatar_url', 'avatarUrl']),
    title: nullableStringField(source, const ['title', 'role']),
  );
}

ChannelMember _channelMemberFromMap(JsonMap map, {required String channelId}) {
  final userMap = jsonMap(field(map, const ['user']));
  final source = userMap.isEmpty ? map : {...userMap, ...map};
  return ChannelMember(
    channelId: stringField(source, const [
      'channel_id',
      'channelId',
    ], fallback: channelId),
    userId: stringField(source, const ['user_id', 'userId', 'id']),
    email: stringField(source, const ['email']),
    username: stringField(source, const ['username']),
    displayName: stringField(source, const [
      'display_name',
      'displayName',
      'username',
      'email',
    ]),
    status: stringField(source, const ['status'], fallback: 'active'),
    joinedAt: dateTimeField(source, const ['joined_at', 'joinedAt']),
    avatarUrl: nullableStringField(source, const ['avatar_url', 'avatarUrl']),
    lastReadMessageId: nullableStringField(source, const [
      'last_read_message_id',
      'lastReadMessageId',
    ]),
  );
}

ChatMessage _messageFromMap(JsonMap map, String workspaceId, String channelId) {
  final messageId = stringField(map, const ['id']);
  final resolvedWorkspaceId = stringField(map, const [
    'workspace_id',
    'workspaceId',
  ], fallback: workspaceId);
  return ChatMessage(
    id: messageId,
    workspaceId: resolvedWorkspaceId,
    channelId: stringField(map, const [
      'channel_id',
      'channelId',
    ], fallback: channelId),
    kind: stringField(map, const ['kind'], fallback: 'text'),
    body: stringField(map, const ['body']),
    createdAt: dateTimeField(map, const ['created_at', 'sent_at', 'createdAt']),
    senderId: nullableStringField(map, const [
      'sender_id',
      'author_id',
      'senderId',
      'authorId',
    ]),
    parentId: nullableStringField(map, const ['parent_id', 'parentId']),
    threadRootId: nullableStringField(map, const [
      'thread_root_id',
      'threadRootId',
    ]),
    editedAt: nullableDateTimeField(map, const ['edited_at', 'editedAt']),
    deletedAt: nullableDateTimeField(map, const ['deleted_at', 'deletedAt']),
    updatedAt: nullableDateTimeField(map, const ['updated_at', 'updatedAt']),
    mentions: field(map, const ['mentions']) is List
        ? (field(map, const ['mentions']) as List)
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList(growable: false)
        : const [],
    reactions: jsonMapList(
      field(map, const ['reactions']),
    ).map(_reactionFromMap).toList(growable: false),
    metadata: Map<String, Object?>.from(
      jsonMap(field(map, const ['metadata'])),
    ),
    attachments: _messageAttachmentsFromMap(
      map,
      workspaceId: resolvedWorkspaceId,
      messageId: messageId,
    ),
  );
}

List<MessageAttachment> _messageAttachmentsFromMap(
  JsonMap map, {
  required String workspaceId,
  required String messageId,
}) {
  return jsonMapList(field(map, const ['attachments', 'message_attachments']))
      .map(
        (attachmentMap) => _messageAttachmentFromMap(
          attachmentMap,
          workspaceId: workspaceId,
          messageId: messageId,
        ),
      )
      .toList(growable: false);
}

MessageAttachment _messageAttachmentFromMap(
  JsonMap map, {
  required String workspaceId,
  required String messageId,
}) {
  final fileMap = jsonMap(field(map, const ['file']));
  final file = _uploadedMessageFileFromMap(
    fileMap.isEmpty ? map : fileMap,
    fallbackWorkspaceId: workspaceId,
  );
  final resolvedMessageId = stringField(map, const [
    'message_id',
    'messageId',
  ], fallback: messageId);
  final fileId = stringField(map, const [
    'file_id',
    'fileId',
  ], fallback: file.id);
  return MessageAttachment(
    id: stringField(map, const [
      'id',
      'attachment_id',
      'attachmentId',
    ], fallback: '$resolvedMessageId:$fileId'),
    workspaceId: stringField(map, const [
      'workspace_id',
      'workspaceId',
    ], fallback: workspaceId),
    messageId: resolvedMessageId,
    fileId: fileId,
    file: file,
    sortOrder: intField(map, const ['sort_order', 'sortOrder']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

UploadedMessageFile _uploadedMessageFileFromMap(
  JsonMap map, {
  required String fallbackWorkspaceId,
}) {
  final id = stringField(map, const ['id', 'file_id', 'fileId']);
  final workspaceId = stringField(map, const [
    'workspace_id',
    'workspaceId',
  ], fallback: fallbackWorkspaceId);
  return UploadedMessageFile(
    id: id,
    name: stringField(map, const [
      'name',
      'file_name',
      'original_name',
      'originalName',
    ], fallback: 'file'),
    mimeType: stringField(map, const [
      'mime_type',
      'mimeType',
    ], fallback: 'application/octet-stream'),
    byteSize: intField(map, const ['byte_size', 'byteSize', 'size']),
    downloadPath: stringField(map, const [
      'download_url',
      'downloadUrl',
      'url',
    ], fallback: _downloadPathFallback(workspaceId, id)),
    status: stringField(map, const ['status'], fallback: 'ready'),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

String _downloadPathFallback(String workspaceId, String fileId) {
  if (workspaceId.isEmpty || fileId.isEmpty) {
    return '';
  }
  return '/api/v1/workspaces/${_e(workspaceId)}/files/${_e(fileId)}/download';
}

MessageReactionSummary _reactionFromMap(JsonMap map) {
  return MessageReactionSummary(
    emoji: stringField(map, const ['emoji']),
    count: intField(map, const ['count']),
    reactedByMe: boolField(map, const ['reacted_by_me', 'reactedByMe']),
  );
}

ChannelFile _fileFromMap(JsonMap map) {
  return ChannelFile(
    id: stringField(map, const ['id', 'file_id']),
    name: stringField(map, const [
      'name',
      'file_name',
      'original_name',
    ], fallback: 'file'),
    mimeType: stringField(map, const [
      'mime_type',
      'mimeType',
    ], fallback: 'application/octet-stream'),
    byteSize: intField(map, const ['byte_size', 'size_bytes', 'size']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

ChannelVisibility _visibilityFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'private' => ChannelVisibility.private,
    'direct' => ChannelVisibility.direct,
    _ => ChannelVisibility.public,
  };
}

String _visibilityToApi(ChannelVisibility visibility) {
  return switch (visibility) {
    ChannelVisibility.private => 'private',
    ChannelVisibility.direct => 'direct',
    ChannelVisibility.public => 'public',
  };
}

MembershipStatus _membershipFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'active' => MembershipStatus.active,
    'muted' => MembershipStatus.muted,
    'invited' => MembershipStatus.invited,
    'left' => MembershipStatus.left,
    'removed' => MembershipStatus.removed,
    _ => MembershipStatus.none,
  };
}

String _avatarLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final words = trimmed.split(RegExp(r'\s+'));
  if (words.length == 1) {
    return _prefix(words.first, 2).toUpperCase();
  }
  return '${_prefix(words.first, 1)}${_prefix(words.last, 1)}'.toUpperCase();
}

CollaborationSettings _collaborationSettingsFromMap(JsonMap map) {
  final roomMode = switch (stringField(map, const ['room_mode'])) {
    'public' => CollaborationRoomMode.public,
    'webinar' => CollaborationRoomMode.webinar,
    _ => CollaborationRoomMode.internal,
  };
  final role = switch (stringField(map, const ['default_participant_role'])) {
    'moderator' => CollaborationParticipantRole.moderator,
    'presenter' => CollaborationParticipantRole.presenter,
    'listener' => CollaborationParticipantRole.listener,
    _ => CollaborationParticipantRole.member,
  };
  return CollaborationSettings(
    channelId: stringField(map, const ['channel_id']),
    workspaceId: stringField(map, const ['workspace_id']),
    channelName: stringField(map, const ['channel_name']),
    channelType: stringField(map, const ['channel_type']),
    roomMode: roomMode,
    meetingProvider: stringField(map, const [
      'meeting_provider',
    ], fallback: 'jitsi'),
    meetingBaseUrl: nullableStringField(map, const ['meeting_base_url']),
    meetingRoomKey: nullableStringField(map, const ['meeting_room_key']),
    publicAccessEnabled: boolField(map, const ['public_access_enabled']),
    publicTokenPrefix: nullableStringField(map, const ['public_token_prefix']),
    hasPassword: boolField(map, const ['has_password']),
    lobbyEnabled: boolField(map, const ['lobby_enabled'], fallback: true),
    chatLocked: boolField(map, const ['chat_locked']),
    guestMicrophoneEnabled: boolField(map, const ['guest_microphone_enabled']),
    guestCameraEnabled: boolField(map, const ['guest_camera_enabled']),
    defaultParticipantRole: role,
  );
}

CollaborationGuest _collaborationGuestFromMap(JsonMap map) {
  return CollaborationGuest(
    id: stringField(map, const ['id']),
    displayName: stringField(map, const ['display_name']),
    status: stringField(map, const ['status']),
    expiresAt: dateTimeField(map, const ['expires_at']),
  );
}

CollaborationDocument _collaborationDocumentFromMap(JsonMap map) {
  return CollaborationDocument(
    channelId: stringField(map, const ['channel_id']),
    kind: stringField(map, const ['kind']),
    content: {
      for (final entry in jsonMap(map['content']).entries)
        entry.key: entry.value as Object?,
    },
    version: intField(map, const ['version'], fallback: 1),
    updatedAt: dateTimeField(map, const ['updated_at']),
  );
}

CollaborationTask _collaborationTaskFromMap(JsonMap map) {
  return CollaborationTask(
    id: stringField(map, const ['id']),
    title: stringField(map, const ['title']),
    status: stringField(map, const ['status'], fallback: 'open'),
    sourceMessageId: nullableStringField(map, const ['source_message_id']),
    assigneeUserId: nullableStringField(map, const ['assignee_user_id']),
    dueAt: nullableDateTimeField(map, const ['due_at']),
    createdAt: dateTimeField(map, const ['created_at']),
  );
}

CollaborationRole _collaborationRoleFromMap(JsonMap map) {
  final role = switch (stringField(map, const ['role'])) {
    'moderator' => CollaborationParticipantRole.moderator,
    'presenter' => CollaborationParticipantRole.presenter,
    'listener' => CollaborationParticipantRole.listener,
    _ => CollaborationParticipantRole.member,
  };
  return CollaborationRole(
    userId: stringField(map, const ['user_id']),
    displayName: stringField(map, const ['display_name']),
    username: stringField(map, const ['username']),
    role: role,
    avatarUrl: nullableStringField(map, const ['avatar_url']),
  );
}

BreakoutRoom _breakoutRoomFromMap(JsonMap map) {
  final assigned = map['assigned_user_ids'];
  return BreakoutRoom(
    id: stringField(map, const ['id']),
    name: stringField(map, const ['name']),
    roomKey: stringField(map, const ['room_key']),
    assignedUserIds: assigned is List
        ? assigned.map((value) => value.toString()).toList(growable: false)
        : const [],
    status: stringField(map, const ['status'], fallback: 'prepared'),
    assignmentMode: stringField(map, const [
      'assignment_mode',
    ], fallback: 'manual'),
    allowSelfSelect: boolField(map, const ['allow_self_select']),
    sequence: intField(map, const ['sequence']),
    startedAt: nullableDateTimeField(map, const ['started_at']),
  );
}

ChannelMeeting _channelMeetingFromMap(JsonMap map) {
  return ChannelMeeting(
    id: stringField(map, const ['id']),
    channelId: stringField(map, const ['channel_id']),
    title: stringField(map, const ['title'], fallback: 'Cuộc họp'),
    description: stringField(map, const ['description']),
    startsAt: dateTimeField(map, const ['starts_at']),
    endsAt: nullableDateTimeField(map, const ['ends_at']),
    lobbyOpensAt: nullableDateTimeField(map, const ['lobby_opens_at']),
    status: stringField(map, const ['status'], fallback: 'scheduled'),
    roomPolicy: stringField(map, const ['room_policy'], fallback: 'keep'),
    startedAt: nullableDateTimeField(map, const ['started_at']),
    endedAt: nullableDateTimeField(map, const ['ended_at']),
  );
}

VoiceRoom _voiceRoomFromMap(JsonMap map) {
  return VoiceRoom(
    channelId: stringField(map, const ['channel_id']),
    status: stringField(map, const ['status'], fallback: 'inactive'),
    startedBy: nullableStringField(map, const ['started_by']),
    startedAt: nullableDateTimeField(map, const ['started_at']),
    endedAt: nullableDateTimeField(map, const ['ended_at']),
  );
}

SharedConversationItem _sharedItemFromMap(JsonMap map) {
  return SharedConversationItem(
    id: stringField(map, const ['id']),
    kind: stringField(map, const ['kind']),
    title: stringField(map, const ['title'], fallback: 'Nội dung được chia sẻ'),
    subtitle: stringField(map, const ['subtitle']),
    url: stringField(map, const ['url']),
    createdAt: dateTimeField(map, const ['created_at']),
  );
}

RecordingPolicy _recordingPolicyFromMap(JsonMap map) {
  return RecordingPolicy(
    enabled: boolField(map, const ['enabled']),
    consentRequired: boolField(map, const ['consent_required'], fallback: true),
    retentionDays: intField(map, const ['retention_days'], fallback: 30),
    transcriptionEnabled: boolField(map, const ['transcription_enabled']),
    summaryEnabled: boolField(map, const ['summary_enabled']),
    provider: stringField(map, const ['provider'], fallback: 'jibri'),
  );
}

ChannelRecording _channelRecordingFromMap(JsonMap map) {
  final participants = map['participant_user_ids'];
  return ChannelRecording(
    id: stringField(map, const ['id']),
    status: stringField(map, const ['status'], fallback: 'pending'),
    provider: stringField(map, const ['provider'], fallback: 'jibri'),
    meetingId: nullableStringField(map, const ['meeting_id']),
    participantUserIds: participants is List
        ? participants.map((value) => value.toString()).toList(growable: false)
        : const [],
    consentCount: intField(map, const ['consent_count']),
    declinedCount: intField(map, const ['declined_count']),
    participantCount: intField(map, const ['participant_count']),
    readyToStart: boolField(map, const ['ready_to_start']),
    startedAt: nullableDateTimeField(map, const ['started_at']),
    endedAt: nullableDateTimeField(map, const ['ended_at']),
    expiresAt: nullableDateTimeField(map, const ['expires_at']),
    transcriptStatus: stringField(map, const [
      'transcript_status',
    ], fallback: 'pending'),
    transcript: nullableStringField(map, const ['transcript']),
    summaryStatus: stringField(map, const [
      'summary_status',
    ], fallback: 'pending'),
    summary: nullableStringField(map, const ['summary']),
    error: nullableStringField(map, const ['error']),
  );
}

TalkIntegration _talkIntegrationFromMap(JsonMap map) {
  return TalkIntegration(
    aiEnabled: boolField(map, const ['ai_enabled']),
    aiProvider: stringField(map, const ['ai_provider'], fallback: 'ollama'),
    transcriptionProvider: stringField(map, const [
      'transcription_provider',
    ], fallback: 'faster_whisper'),
    federationEnabled: boolField(map, const ['federation_enabled']),
    e2eeCallsEnabled: boolField(map, const ['e2ee_calls_enabled']),
    sipEnabled: boolField(map, const ['sip_enabled']),
    bridgeEnabled: boolField(map, const ['bridge_enabled']),
  );
}

List<String> _stringList(Object? value) {
  return value is List
      ? value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
      : const [];
}

String _e(String value) => Uri.encodeComponent(value);

String? _dateParam(DateTime? value) {
  if (value == null) {
    return null;
  }
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

List<String> _mentionedUserIds(String body) {
  final matches = RegExp(
    r'<@([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})>',
  ).allMatches(body);
  return {
    for (final match in matches)
      if (match.group(1) != null) match.group(1)!,
  }.toList(growable: false);
}

String _prefix(String value, int length) {
  if (value.length <= length) {
    return value;
  }
  return value.substring(0, length);
}
