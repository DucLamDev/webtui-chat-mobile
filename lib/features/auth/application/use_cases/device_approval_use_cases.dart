import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/device_approval.dart';
import '../../domain/repositories/device_approval_repository.dart';

final class LoadMyDeviceApprovalUseCase {
  const LoadMyDeviceApprovalUseCase(this._repository);

  final DeviceApprovalRepository _repository;

  Future<Result<MyDeviceApproval>> execute() => _repository.mine();
}

final class ListPendingDeviceApprovalsUseCase {
  const ListPendingDeviceApprovalsUseCase(this._repository);

  final DeviceApprovalRepository _repository;

  Future<Result<List<DeviceApprovalRequest>>> execute({
    DeviceApprovalScope scope = DeviceApprovalScope.mine,
  }) {
    return _repository.listPending(scope);
  }
}

/// Tìm một yêu cầu chờ duyệt theo `session_id`: trước trong danh sách của
/// chính mình, rồi danh sách quản trị (403 ở phạm vi quản trị coi như không có).
final class FindDeviceApprovalRequestUseCase {
  const FindDeviceApprovalRequestUseCase(this._repository);

  final DeviceApprovalRepository _repository;

  Future<Result<DeviceApprovalRequest?>> execute(
    String sessionId, {
    bool preferAdmin = false,
  }) async {
    final id = sessionId.trim();
    if (id.isEmpty) {
      return const Success(null);
    }
    final scopes = preferAdmin
        ? const [DeviceApprovalScope.admin, DeviceApprovalScope.mine]
        : const [DeviceApprovalScope.mine, DeviceApprovalScope.admin];
    Failure? firstFailure;
    for (final scope in scopes) {
      final result = await _repository.listPending(scope);
      switch (result) {
        case Success<List<DeviceApprovalRequest>>(:final value):
          for (final item in value) {
            if (item.sessionId == id) {
              return Success(item);
            }
          }
        case FailureResult<List<DeviceApprovalRequest>>(:final failure):
          if (scope == DeviceApprovalScope.mine ||
              failure.kind != FailureKind.forbidden) {
            firstFailure ??= failure;
          }
      }
    }
    final failure = firstFailure;
    return failure == null ? const Success(null) : FailureResult(failure);
  }
}

final class DecideDeviceApprovalUseCase {
  const DecideDeviceApprovalUseCase(this._repository);

  final DeviceApprovalRepository _repository;

  Future<Result<DeviceApprovalResult>> execute(
    String sessionId, {
    required bool approve,
  }) {
    final id = sessionId.trim();
    if (id.isEmpty) {
      return Future.value(
        FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: tr(
              'Không xác định được phiên cần duyệt.',
              'Could not identify the session to approve.',
            ),
            code: 'DEVICE_APPROVAL_SESSION_REQUIRED',
          ),
        ),
      );
    }
    return approve ? _repository.approve(id) : _repository.reject(id);
  }
}

String deviceApprovalFailureMessage(Failure failure) {
  if (failure.hasCode(DeviceApprovalErrorCode.forbidden)) {
    return tr(
      'Bạn không có quyền duyệt thiết bị này.',
      'You do not have permission to approve this device.',
    );
  }
  if (failure.hasCode(DeviceApprovalErrorCode.alreadyDecided)) {
    return tr(
      'Yêu cầu này đã được xử lý.',
      'This request has already been handled.',
    );
  }
  if (failure.hasCode(DeviceApprovalErrorCode.notFound)) {
    return tr(
      'Yêu cầu duyệt không còn tồn tại.',
      'This approval request no longer exists.',
    );
  }
  if (failure.hasCode(DeviceApprovalErrorCode.expired)) {
    return tr(
      'Yêu cầu duyệt đã hết hạn.',
      'This approval request has expired.',
    );
  }
  return failure.message;
}

/// Tên vai trò người duyệt cho giao diện.
String deviceApprovalRoleLabel(String role) {
  return switch (role.trim().toLowerCase()) {
    'self' => tr('Chính bạn', 'You'),
    'admin' => tr('Quản trị viên', 'Administrator'),
    'delegate' => tr('Người được chỉ định', 'Designated approver'),
    _ => role,
  };
}
