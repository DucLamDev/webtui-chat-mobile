import '../../../../core/result/result.dart';
import '../entities/auth_session.dart';
import '../entities/device_identity.dart';
import '../entities/user_session.dart';

abstract interface class AuthRepository {
  Future<Result<AuthSession>> login({
    required String identifier,
    required String password,
    required DeviceIdentity device,
  });

  Future<Result<AuthSession>> register({
    required String displayName,
    required String email,
    required String username,
    required String password,
    required DeviceIdentity device,
  });

  Future<Result<AuthSession>> loginWithGoogle({
    required String credential,
    required DeviceIdentity device,
  });

  Future<Result<AuthSession>> refresh(String refreshToken);

  Future<Result<void>> logout(String refreshToken);

  Future<Result<List<UserSession>>> listSessions();

  Future<Result<void>> revokeSession(String sessionId);

  Future<Result<void>> revokeAllSessions();
}
