import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/device_identity.dart';
import '../../domain/entities/user_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

final class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Future<Result<AuthSession>> login({
    required String identifier,
    required String password,
    required DeviceIdentity device,
  }) {
    return guardResult(
      () => _remote.login(
        identifier: identifier,
        password: password,
        device: device,
      ),
    );
  }

  @override
  Future<Result<AuthSession>> register({
    required String displayName,
    required String email,
    required String username,
    required String password,
    required DeviceIdentity device,
  }) {
    return guardResult(
      () => _remote.register(
        displayName: displayName,
        email: email,
        username: username,
        password: password,
        device: device,
      ),
    );
  }

  @override
  Future<Result<AuthSession>> loginWithGoogle({
    required String credential,
    required DeviceIdentity device,
  }) {
    return guardResult(
      () => _remote.loginWithGoogle(credential: credential, device: device),
    );
  }

  @override
  Future<Result<AuthSession>> refresh(String refreshToken) {
    return guardResult(() => _remote.refresh(refreshToken));
  }

  @override
  Future<Result<void>> logout(String refreshToken) {
    return guardResult(() => _remote.logout(refreshToken));
  }

  @override
  Future<Result<List<UserSession>>> listSessions() {
    return guardResult(_remote.listSessions);
  }

  @override
  Future<Result<void>> revokeSession(String sessionId) {
    return guardResult(() => _remote.revokeSession(sessionId));
  }

  @override
  Future<Result<void>> revokeAllSessions() {
    return guardResult(_remote.revokeAllSessions);
  }
}
