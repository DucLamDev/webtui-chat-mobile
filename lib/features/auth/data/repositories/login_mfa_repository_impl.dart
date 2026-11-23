import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/login_mfa.dart';
import '../../domain/repositories/login_mfa_repository.dart';
import '../datasources/auth_remote_data_source.dart';

final class LoginMfaRepositoryImpl implements LoginMfaRepository {
  const LoginMfaRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Future<Result<AuthSession>> complete({
    required String mfaToken,
    required LoginMfaMethod method,
    required String code,
  }) {
    return guardResult(
      () => _remote.completeLoginMfa(
        mfaToken: mfaToken,
        method: method.apiValue,
        code: code,
      ),
    );
  }
}
