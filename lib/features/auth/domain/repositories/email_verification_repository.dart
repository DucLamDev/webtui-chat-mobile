import '../../../../core/result/result.dart';
import '../entities/auth_session.dart';
import '../entities/device_identity.dart';
import '../entities/email_verification.dart';

abstract interface class EmailVerificationRepository {
  /// `POST /auth/email/verify` → kết quả giống `/auth/login`.
  Future<Result<AuthSession>> verify({
    required String verificationId,
    required String code,
    required DeviceIdentity device,
  });

  /// `POST /auth/email/resend` → phiên xác minh mới (thời hạn, giờ gửi lại).
  Future<Result<EmailVerificationTicket>> resend(String verificationId);
}
