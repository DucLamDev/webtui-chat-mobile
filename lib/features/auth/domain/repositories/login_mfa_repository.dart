import '../../../../core/result/result.dart';
import '../entities/auth_session.dart';
import '../entities/login_mfa.dart';

/// Hoàn tất đăng nhập bằng yếu tố thứ hai (`POST /api/v1/auth/login/mfa`).
abstract interface class LoginMfaRepository {
  Future<Result<AuthSession>> complete({
    required String mfaToken,
    required LoginMfaMethod method,
    required String code,
  });
}
