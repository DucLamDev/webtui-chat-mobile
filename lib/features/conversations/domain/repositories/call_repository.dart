import '../../../../core/result/result.dart';
import '../entities/call_session.dart';

abstract interface class CallRepository {
  Future<Result<CallSession>> createCall({
    required String workspaceId,
    required String channelId,
    required String targetUserId,
    required CallMode mode,
    required String clientCallId,
    Map<String, Object?> metadata = const {},
  });

  Future<Result<CallSession>> getCall({
    required String workspaceId,
    required String callId,
  });

  Future<Result<CallSession>> acceptCall({
    required String workspaceId,
    required String callId,
  });

  Future<Result<CallSession>> rejectCall({
    required String workspaceId,
    required String callId,
    String? reason,
  });

  Future<Result<CallSession>> cancelCall({
    required String workspaceId,
    required String callId,
    String? reason,
  });

  Future<Result<CallSession>> hangupCall({
    required String workspaceId,
    required String callId,
    String? reason,
  });

  Future<Result<CallSession>> markMissed({
    required String workspaceId,
    required String callId,
    String? reason,
  });

  Future<Result<CallSignal>> sendSignal({
    required String workspaceId,
    required String callId,
    required CallSignalType signalType,
    required Map<String, Object?> payload,
  });
}
