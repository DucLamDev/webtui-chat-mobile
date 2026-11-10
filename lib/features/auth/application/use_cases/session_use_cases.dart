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

enum SessionRevokeOutcome {
  /// Đã thu hồi phiên của thiết bị khác; máy này vẫn đăng nhập.
  revokedOtherDevice,

  /// Thu hồi đúng phiên máy này (`is_current`): đã đăng xuất cục bộ.
  signedOutThisDevice,
}

/// Thu hồi một phiên trong danh sách. Chỉ đăng xuất máy này khi máy chủ báo
/// phiên đó là `is_current`; phiên khác còn hạn (`isActive`) không liên quan.
final class RevokeDeviceSessionUseCase {
  const RevokeDeviceSessionUseCase({
    required AuthRepository authRepository,
    required Future<Result<void>> Function() signOutThisDevice,
  }) : _authRepository = authRepository,
       _signOutThisDevice = signOutThisDevice;

  final AuthRepository _authRepository;
  final Future<Result<void>> Function() _signOutThisDevice;

  Future<Result<SessionRevokeOutcome>> execute(UserSession session) async {
    final result = await _authRepository.revokeSession(session.id);
    switch (result) {
      case FailureResult<void>(:final failure):
        return FailureResult(failure);
      case Success<void>():
        if (!session.isCurrent) {
          return const Success(SessionRevokeOutcome.revokedOtherDevice);
        }
        await _signOutThisDevice();
        return const Success(SessionRevokeOutcome.signedOutThisDevice);
    }
  }
}

final class RevokeAllSessionsUseCase {
  const RevokeAllSessionsUseCase(this._authRepository);

  final AuthRepository _authRepository;

  Future<Result<void>> execute() {
    return _authRepository.revokeAllSessions();
  }
}
