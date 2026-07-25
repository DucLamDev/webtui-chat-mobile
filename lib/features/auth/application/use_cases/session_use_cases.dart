import '../../../../core/result/result.dart';
import '../../domain/entities/user_session.dart';
import '../../domain/repositories/auth_repository.dart';

final class ListSessionsUseCase {
  const ListSessionsUseCase(this._authRepository);

  final AuthRepository _authRepository;

  Future<Result<List<UserSession>>> execute() {
    return _authRepository.listSessions();
  }
}

final class RevokeSessionUseCase {
  const RevokeSessionUseCase(this._authRepository);

  final AuthRepository _authRepository;

  Future<Result<void>> execute(String sessionId) {
    return _authRepository.revokeSession(sessionId);
  }
}

final class RevokeAllSessionsUseCase {
  const RevokeAllSessionsUseCase(this._authRepository);

  final AuthRepository _authRepository;

  Future<Result<void>> execute() {
    return _authRepository.revokeAllSessions();
  }
}
