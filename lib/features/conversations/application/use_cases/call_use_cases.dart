import 'package:uuid/uuid.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../auth/domain/repositories/device_identity_repository.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/repositories/call_repository.dart';

/// Mã thiết bị gửi kèm khi tạo / nhận / từ chối cuộc gọi: chính là mã máy đã
/// đăng ký push, để máy chủ biết máy nào đã nhận và báo các máy còn lại ngừng
/// chuông. Không đọc được thì trả `null` (máy chủ giữ hành vi cũ).
final class ResolveCallDeviceIdUseCase {
  const ResolveCallDeviceIdUseCase(this._deviceIdentityRepository);

  final DeviceIdentityRepository? _deviceIdentityRepository;

  Future<String?> execute() async {
    final repository = _deviceIdentityRepository;
    if (repository == null) return null;
    try {
      final id = (await repository.currentDevice()).id.trim();
      return id.isEmpty ? null : id;
    } on Object {
      return null;
    }
  }
}

/// Bấm nghe nhưng máy chủ trả 409 `CALL_INVALID_TRANSITION`: cuộc gọi đã được
/// nhận ở máy khác (hoặc vừa kết thúc). Máy này chỉ tắt chuông, không gửi gì.
bool isCallAlreadyHandledFailure(Failure? failure) {
  if (failure == null || failure.kind != FailureKind.conflict) return false;
  final code = failure.code?.trim();
  return code == null || code.isEmpty || code == 'CALL_INVALID_TRANSITION';
}

final class StartCallUseCase {
  const StartCallUseCase(
    this._repository, {
    Uuid uuid = const Uuid(),
    ResolveCallDeviceIdUseCase? resolveDeviceId,
  }) : _uuid = uuid,
       _resolveDeviceId = resolveDeviceId;

  final CallRepository _repository;
  final Uuid _uuid;
  final ResolveCallDeviceIdUseCase? _resolveDeviceId;

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
    return _create(
      workspaceId: workspaceId,
      channelId: channelId,
      targetUserId: targetUserId,
      mode: mode,
    );
  }

  Future<Result<CallSession>> _create({
    required String workspaceId,
    required String channelId,
    required String targetUserId,
    required CallMode mode,
  }) async {
    return _repository.createCall(
      workspaceId: workspaceId,
      channelId: channelId,
      targetUserId: targetUserId,
      mode: mode,
      clientCallId: _uuid.v4(),
      metadata: const {'client': 'mobile'},
      deviceId: await _resolveDeviceId?.execute(),
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

final class FindIncomingCallUseCase {
  const FindIncomingCallUseCase(this._repository);

  final CallRepository _repository;

  Future<Result<CallSession?>> execute({required String workspaceId}) {
    return _repository.findIncomingRingingCall(workspaceId: workspaceId);
  }
}

final class AcceptCallUseCase {
  const AcceptCallUseCase(
    this._repository, {
    ResolveCallDeviceIdUseCase? resolveDeviceId,
  }) : _resolveDeviceId = resolveDeviceId;

  final CallRepository _repository;
  final ResolveCallDeviceIdUseCase? _resolveDeviceId;

  Future<Result<CallSession>> execute({
    required String workspaceId,
    required String callId,
  }) async {
    return _repository.acceptCall(
      workspaceId: workspaceId,
      callId: callId,
      deviceId: await _resolveDeviceId?.execute(),
    );
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
  const RejectCallUseCase(
    this._repository, {
    ResolveCallDeviceIdUseCase? resolveDeviceId,
  }) : _resolveDeviceId = resolveDeviceId;

  final CallRepository _repository;
  final ResolveCallDeviceIdUseCase? _resolveDeviceId;

  Future<Result<CallSession>> execute({
    required String workspaceId,
    required String callId,
    String? reason,
  }) async {
    return _repository.rejectCall(
      workspaceId: workspaceId,
      callId: callId,
      reason: reason,
      deviceId: await _resolveDeviceId?.execute(),
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
