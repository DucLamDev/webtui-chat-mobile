import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/device_approval.dart';
import '../../domain/entities/device_identity.dart';
import '../../domain/entities/email_verification.dart';
import '../../domain/entities/qr_login.dart';
import '../../domain/repositories/device_approval_repository.dart';
import '../../domain/repositories/email_verification_repository.dart';
import '../../domain/repositories/qr_login_repository.dart';
import '../datasources/device_approval_remote_data_source.dart';
import '../datasources/email_verification_remote_data_source.dart';
import '../datasources/qr_login_remote_data_source.dart';

final class QrLoginRepositoryImpl implements QrLoginRepository {
  const QrLoginRepositoryImpl(this._remote);

  final QrLoginRemoteDataSource _remote;

  @override
  Future<Result<QrLoginScan>> scan(QrLoginPayload payload) {
    return guardResult(() => _remote.scan(payload));
  }

  @override
  Future<Result<String>> approve(QrLoginPayload payload) {
    return guardResult(() => _remote.approve(payload));
  }

  @override
  Future<Result<String>> reject(QrLoginPayload payload) {
    return guardResult(() => _remote.reject(payload));
  }
}

final class DeviceApprovalRepositoryImpl implements DeviceApprovalRepository {
  const DeviceApprovalRepositoryImpl(this._remote);

  final DeviceApprovalRemoteDataSource _remote;

  @override
  Future<Result<MyDeviceApproval>> mine() => guardResult(_remote.mine);

  @override
  Future<Result<List<DeviceApprovalRequest>>> listPending(
    DeviceApprovalScope scope,
  ) {
    return guardResult(() => _remote.listPending(scope));
  }

  @override
  Future<Result<DeviceApprovalResult>> approve(String sessionId) {
    return guardResult(() => _remote.approve(sessionId));
  }

  @override
  Future<Result<DeviceApprovalResult>> reject(String sessionId) {
    return guardResult(() => _remote.reject(sessionId));
  }
}

final class EmailVerificationRepositoryImpl
    implements EmailVerificationRepository {
  const EmailVerificationRepositoryImpl(this._remote);

  final EmailVerificationRemoteDataSource _remote;

  @override
  Future<Result<AuthSession>> verify({
    required String verificationId,
    required String code,
    required DeviceIdentity device,
  }) {
    return guardResult(
      () => _remote.verify(
        verificationId: verificationId,
        code: code,
        device: device,
      ),
    );
  }

  @override
  Future<Result<EmailVerificationTicket>> resend(String verificationId) {
    return guardResult(() => _remote.resend(verificationId));
  }
}
