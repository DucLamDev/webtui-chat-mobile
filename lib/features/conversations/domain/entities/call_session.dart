enum CallMode { audio, video }

enum CallStatus { ringing, accepted, rejected, cancelled, ended, missed }

extension CallStatusState on CallStatus {
  bool get isTerminal =>
      this == CallStatus.rejected ||
      this == CallStatus.cancelled ||
      this == CallStatus.ended ||
      this == CallStatus.missed;
}

enum CallSignalType {
  offer,
  answer,
  iceCandidate,
  ready,
  ringing,
  accepted,
  rejected,
  cancelled,
  ended,
  missed,
}

final class CallSession {
  const CallSession({
    required this.id,
    required this.workspaceId,
    required this.channelId,
    required this.initiatorUserId,
    required this.targetUserId,
    required this.mode,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.clientCallId,
    this.startedAt,
    this.endedAt,
    this.metadata = const {},
  });

  final String id;
  final String workspaceId;
  final String channelId;
  final String initiatorUserId;
  final String targetUserId;
  final String? clientCallId;
  final CallMode mode;
  final CallStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> metadata;

  bool get isTerminal => status.isTerminal;

  CallSession copyWith({
    CallStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    DateTime? updatedAt,
  }) {
    return CallSession(
      id: id,
      workspaceId: workspaceId,
      channelId: channelId,
      initiatorUserId: initiatorUserId,
      targetUserId: targetUserId,
      clientCallId: clientCallId,
      mode: mode,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      metadata: metadata,
    );
  }
}

final class CallSignal {
  const CallSignal({
    required this.id,
    required this.workspaceId,
    required this.callId,
    required this.senderUserId,
    required this.signalType,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String workspaceId;
  final String callId;
  final String senderUserId;
  final CallSignalType signalType;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}
