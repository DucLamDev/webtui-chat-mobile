import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/repositories/call_repository.dart';
import '../datasources/call_remote_data_source.dart';

final class CallRepositoryImpl implements CallRepository {
  const CallRepositoryImpl(this._remote);

  final CallRemoteDataSource _remote;

  @override
  Future<Result<CallSession>> createCall({
    required String workspaceId,
    required String channelId,
    required String targetUserId,
    required CallMode mode,
    required String clientCallId,
    Map<String, Object?> metadata = const {},
  }) {
    return guardResult(
      () => _remote.createCall(
        workspaceId: workspaceId,
        channelId: channelId,
        targetUserId: targetUserId,
        mode: mode,
        clientCallId: clientCallId,
        metadata: metadata,
      ),
    );
  }

  @override
  Future<Result<CallSession>> getCall({
    required String workspaceId,
    required String callId,
  }) {
    return guardResult(
      () => _remote.getCall(workspaceId: workspaceId, callId: callId),
    );
  }

  @override
  Future<Result<CallSession>> acceptCall({
    required String workspaceId,
    required String callId,
  }) {
    return _changeStatus(
      workspaceId: workspaceId,
      callId: callId,
      action: 'accept',
    );
  }

  @override
  Future<Result<CallSession>> rejectCall({
    required String workspaceId,
    required String callId,
    String? reason,
  }) {
    return _changeStatus(
      workspaceId: workspaceId,
      callId: callId,
      action: 'reject',
      reason: reason,
    );
  }

  @override
  Future<Result<CallSession>> cancelCall({
    required String workspaceId,
    required String callId,
    String? reason,
  }) {
    return _changeStatus(
      workspaceId: workspaceId,
      callId: callId,
      action: 'cancel',
      reason: reason,
    );
  }

  @override
  Future<Result<CallSession>> hangupCall({
    required String workspaceId,
    required String callId,
    String? reason,
  }) {
    return _changeStatus(
      workspaceId: workspaceId,
      callId: callId,
      action: 'hangup',
      reason: reason,
    );
  }

  @override
  Future<Result<CallSession>> markMissed({
    required String workspaceId,
    required String callId,
    String? reason,
  }) {
    return _changeStatus(
      workspaceId: workspaceId,
      callId: callId,
      action: 'miss',
      reason: reason,
    );
  }

  @override
  Future<Result<CallSignal>> sendSignal({
    required String workspaceId,
    required String callId,
    required CallSignalType signalType,
    required Map<String, Object?> payload,
  }) {
    return guardResult(
      () => _remote.sendSignal(
        workspaceId: workspaceId,
        callId: callId,
        signalType: signalType,
        payload: payload,
      ),
    );
  }

  Future<Result<CallSession>> _changeStatus({
    required String workspaceId,
    required String callId,
    required String action,
    String? reason,
  }) {
    return guardResult(
      () => _remote.changeStatus(
        workspaceId: workspaceId,
        callId: callId,
        action: action,
        reason: reason,
      ),
    );
  }
}
