import 'package:uuid/uuid.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/repositories/call_repository.dart';

final class StartCallUseCase {
  const StartCallUseCase(this._repository, {Uuid uuid = const Uuid()})
    : _uuid = uuid;

  final CallRepository _repository;
  final Uuid _uuid;

  Future<Result<CallSession>> execute({
    required String workspaceId,
    required String channelId,
    required String targetUserId,
    required CallMode mode,
  }) {
    if (targetUserId.trim().isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Chưa có người nhận cuộc gọi.',
            code: 'CALL_TARGET_REQUIRED',
          ),
        ),
      );
    }
    return _repository.createCall(
      workspaceId: workspaceId,
      channelId: channelId,
      targetUserId: targetUserId,
      mode: mode,
      clientCallId: _uuid.v4(),
      metadata: const {'client': 'mobile'},
    );
  }
}

final class GetCallUseCase {
  const GetCallUseCase(this._repository);

  final CallRepository _repository;

  Future<Result<CallSession>> execute({
    required String workspaceId,
    required String callId,
  }) {
    return _repository.getCall(workspaceId: workspaceId, callId: callId);
  }
}

final class AcceptCallUseCase {
  const AcceptCallUseCase(this._repository);

  final CallRepository _repository;

  Future<Result<CallSession>> execute({
    required String workspaceId,
    required String callId,
  }) {
    return _repository.acceptCall(workspaceId: workspaceId, callId: callId);
  }
}

final class EndCallUseCase {
  const EndCallUseCase(this._repository);

  final CallRepository _repository;

  Future<Result<CallSession>> execute({
    required String workspaceId,
    required String callId,
    required CallStatus currentStatus,
    String? reason,
  }) {
    if (currentStatus == CallStatus.ringing) {
      return _repository.cancelCall(
        workspaceId: workspaceId,
        callId: callId,
        reason: reason,
      );
    }
    return _repository.hangupCall(
      workspaceId: workspaceId,
      callId: callId,
      reason: reason,
    );
  }
}

final class RejectCallUseCase {
  const RejectCallUseCase(this._repository);

  final CallRepository _repository;

  Future<Result<CallSession>> execute({
    required String workspaceId,
    required String callId,
    String? reason,
  }) {
    return _repository.rejectCall(
      workspaceId: workspaceId,
      callId: callId,
      reason: reason,
    );
  }
}

final class SendCallSignalUseCase {
  const SendCallSignalUseCase(this._repository);

  final CallRepository _repository;

  Future<Result<CallSignal>> execute({
    required String workspaceId,
    required String callId,
    required CallSignalType signalType,
    required Map<String, Object?> payload,
  }) {
    return _repository.sendSignal(
      workspaceId: workspaceId,
      callId: callId,
      signalType: signalType,
      payload: payload,
    );
  }
}
