enum ModerationTargetType { message, user }

extension ModerationTargetTypeApi on ModerationTargetType {
  String get apiValue => switch (this) {
    ModerationTargetType.message => 'message',
    ModerationTargetType.user => 'user',
  };
}

enum ModerationReportReason {
  spam,
  harassment,
  hateSpeech,
  sexualContent,
  violence,
  illegalContent,
  privacy,
  impersonation,
  other,
}

extension ModerationReportReasonApi on ModerationReportReason {
  String get apiValue => switch (this) {
    ModerationReportReason.spam => 'spam',
    ModerationReportReason.harassment => 'harassment',
    ModerationReportReason.hateSpeech => 'hate_speech',
    ModerationReportReason.sexualContent => 'sexual_content',
    ModerationReportReason.violence => 'violence',
    ModerationReportReason.illegalContent => 'illegal_content',
    ModerationReportReason.privacy => 'privacy',
    ModerationReportReason.impersonation => 'impersonation',
    ModerationReportReason.other => 'other',
  };
}

ModerationTargetType moderationTargetTypeFromApi(String value) {
  return value.trim().toLowerCase() == 'user'
      ? ModerationTargetType.user
      : ModerationTargetType.message;
}

ModerationReportReason moderationReportReasonFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'spam' => ModerationReportReason.spam,
    'harassment' => ModerationReportReason.harassment,
    'hate_speech' => ModerationReportReason.hateSpeech,
    'sexual_content' => ModerationReportReason.sexualContent,
    'violence' => ModerationReportReason.violence,
    'illegal_content' => ModerationReportReason.illegalContent,
    'privacy' => ModerationReportReason.privacy,
    'impersonation' => ModerationReportReason.impersonation,
    _ => ModerationReportReason.other,
  };
}

final class ModerationReport {
  const ModerationReport({
    required this.id,
    required this.workspaceId,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.details,
  });

  final String id;
  final String workspaceId;
  final ModerationTargetType targetType;
  final String targetId;
  final ModerationReportReason reason;
  final String status;
  final DateTime createdAt;
  final String? details;
}

final class BlockedUser {
  const BlockedUser({
    required this.blockedUserId,
    required this.createdAt,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.reason,
  });

  final String blockedUserId;
  final DateTime createdAt;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? reason;

  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) {
      return '@$handle';
    }
    return blockedUserId;
  }
}
