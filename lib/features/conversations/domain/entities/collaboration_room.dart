enum CollaborationRoomMode { internal, public, webinar }

enum CollaborationParticipantRole { moderator, presenter, member, listener }

final class CollaborationUserGroup {
  const CollaborationUserGroup({
    required this.id,
    required this.name,
    required this.memberCount,
  });

  final String id;
  final String name;
  final int memberCount;
}

final class CollaborationSettings {
  const CollaborationSettings({
    required this.channelId,
    required this.workspaceId,
    required this.channelName,
    required this.channelType,
    required this.roomMode,
    required this.meetingProvider,
    required this.publicAccessEnabled,
    required this.hasPassword,
    required this.lobbyEnabled,
    required this.chatLocked,
    required this.guestMicrophoneEnabled,
    required this.guestCameraEnabled,
    required this.defaultParticipantRole,
    this.meetingBaseUrl,
    this.meetingRoomKey,
    this.publicTokenPrefix,
  });

  final String channelId;
  final String workspaceId;
  final String channelName;
  final String channelType;
  final CollaborationRoomMode roomMode;
  final String meetingProvider;
  final String? meetingBaseUrl;
  final String? meetingRoomKey;
  final bool publicAccessEnabled;
  final String? publicTokenPrefix;
  final bool hasPassword;
  final bool lobbyEnabled;
  final bool chatLocked;
  final bool guestMicrophoneEnabled;
  final bool guestCameraEnabled;
  final CollaborationParticipantRole defaultParticipantRole;

  bool get isDirect => channelType == 'direct';
  bool get canOpenMeeting =>
      meetingBaseUrl?.isNotEmpty == true && meetingRoomKey?.isNotEmpty == true;
}

final class PublicConversationLink {
  const PublicConversationLink({required this.settings, required this.token});

  final CollaborationSettings settings;
  final String token;
}

final class CollaborationGuest {
  const CollaborationGuest({
    required this.id,
    required this.displayName,
    required this.status,
    required this.expiresAt,
  });

  final String id;
  final String displayName;
  final String status;
  final DateTime expiresAt;
}

final class CollaborationDocument {
  const CollaborationDocument({
    required this.channelId,
    required this.kind,
    required this.content,
    required this.version,
    required this.updatedAt,
  });

  final String channelId;
  final String kind;
  final Map<String, Object?> content;
  final int version;
  final DateTime updatedAt;
}

final class CollaborationTask {
  const CollaborationTask({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    this.sourceMessageId,
    this.assigneeUserId,
    this.dueAt,
  });

  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final String? sourceMessageId;
  final String? assigneeUserId;
  final DateTime? dueAt;
}

final class CollaborationRole {
  const CollaborationRole({
    required this.userId,
    required this.displayName,
    required this.username,
    required this.role,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String username;
  final CollaborationParticipantRole role;
  final String? avatarUrl;
}

final class BreakoutRoom {
  const BreakoutRoom({
    required this.id,
    required this.name,
    required this.roomKey,
    required this.assignedUserIds,
    required this.status,
    this.assignmentMode = 'manual',
    this.allowSelfSelect = false,
    this.sequence = 0,
    this.startedAt,
  });

  final String id;
  final String name;
  final String roomKey;
  final List<String> assignedUserIds;
  final String status;
  final String assignmentMode;
  final bool allowSelfSelect;
  final int sequence;
  final DateTime? startedAt;

  bool get isActive => status == 'active' || status == 'open';
  bool get canSelfJoin => isActive && allowSelfSelect;
}

final class ChannelMeeting {
  const ChannelMeeting({
    required this.id,
    required this.channelId,
    required this.title,
    required this.startsAt,
    required this.status,
    required this.roomPolicy,
    this.description = '',
    this.endsAt,
    this.lobbyOpensAt,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String channelId;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime? lobbyOpensAt;
  final String status;
  final String roomPolicy;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isLive => status == 'active';
  bool get canStart => status == 'scheduled';
}

final class VoiceRoom {
  const VoiceRoom({
    required this.channelId,
    required this.status,
    this.startedBy,
    this.startedAt,
    this.endedAt,
  });

  final String channelId;
  final String status;
  final String? startedBy;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isActive => status == 'active';
}

final class TalkHome {
  const TalkHome({
    required this.upcomingMeetings,
    required this.activeVoiceRooms,
    required this.openTasks,
    required this.unreadMentions,
    required this.pendingReminders,
    required this.missedCalls,
  });

  final List<ChannelMeeting> upcomingMeetings;
  final List<VoiceRoom> activeVoiceRooms;
  final List<CollaborationTask> openTasks;
  final int unreadMentions;
  final int pendingReminders;
  final int missedCalls;
}

final class SharedConversationItem {
  const SharedConversationItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.createdAt,
    this.subtitle = '',
    this.url = '',
  });

  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final String url;
  final DateTime createdAt;
}

final class RecordingPolicy {
  const RecordingPolicy({
    required this.enabled,
    required this.consentRequired,
    required this.retentionDays,
    required this.transcriptionEnabled,
    required this.summaryEnabled,
    required this.provider,
  });

  final bool enabled;
  final bool consentRequired;
  final int retentionDays;
  final bool transcriptionEnabled;
  final bool summaryEnabled;
  final String provider;
}

final class ChannelRecording {
  const ChannelRecording({
    required this.id,
    required this.status,
    required this.provider,
    required this.participantUserIds,
    required this.consentCount,
    required this.declinedCount,
    required this.participantCount,
    required this.readyToStart,
    this.meetingId,
    this.startedAt,
    this.endedAt,
    this.expiresAt,
    this.transcriptStatus = 'pending',
    this.transcript,
    this.summaryStatus = 'pending',
    this.summary,
    this.error,
  });

  final String id;
  final String status;
  final String provider;
  final String? meetingId;
  final List<String> participantUserIds;
  final int consentCount;
  final int declinedCount;
  final int participantCount;
  final bool readyToStart;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? expiresAt;
  final String transcriptStatus;
  final String? transcript;
  final String summaryStatus;
  final String? summary;
  final String? error;

  bool get isActive =>
      status == 'pending' || status == 'recording' || status == 'processing';
}

final class TalkIntegration {
  const TalkIntegration({
    required this.aiEnabled,
    required this.aiProvider,
    required this.transcriptionProvider,
    required this.federationEnabled,
    required this.e2eeCallsEnabled,
    required this.sipEnabled,
    required this.bridgeEnabled,
  });

  final bool aiEnabled;
  final String aiProvider;
  final String transcriptionProvider;
  final bool federationEnabled;
  final bool e2eeCallsEnabled;
  final bool sipEnabled;
  final bool bridgeEnabled;
}

final class TalkSummary {
  const TalkSummary({
    required this.summary,
    required this.decisions,
    required this.actionItems,
    required this.model,
    required this.messageCount,
    required this.generatedAt,
  });

  final String summary;
  final List<String> decisions;
  final List<String> actionItems;
  final String model;
  final int messageCount;
  final DateTime generatedAt;
}
