import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/repositories/google_identity_provider.dart';

final class GoogleSignInIdentityProvider implements GoogleIdentityProvider {
  GoogleSignInIdentityProvider();

  static const _clientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_SERVER_CLIENT_ID',
  );

  Future<void>? _initializing;

  @override
  Future<Result<String>> authenticate() async {
    try {
      await (_initializing ??= _initialize());
      final signIn = GoogleSignIn.instance;
      if (!signIn.supportsAuthenticate()) {
        return const FailureResult(
          Failure(
            kind: FailureKind.validation,
            code: 'GOOGLE_SIGN_IN_UNSUPPORTED',
            message: 'Thiết bị này chưa hỗ trợ đăng nhập Google.',
          ),
        );
      }

      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken?.trim() ?? '';
      if (idToken.isEmpty) {
        return const FailureResult(
          Failure(
            kind: FailureKind.unauthorized,
            code: 'GOOGLE_ID_TOKEN_MISSING',
            message: 'Google không trả về thông tin xác thực hợp lệ.',
          ),
        );
      }
      return Success(idToken);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return const FailureResult(
          Failure(
            kind: FailureKind.cancelled,
            code: 'GOOGLE_SIGN_IN_CANCELLED',
            message: 'Bạn đã hủy đăng nhập Google.',
          ),
        );
      }
      return FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          code: 'GOOGLE_SIGN_IN_FAILED',
          message:
              'Không thể đăng nhập Google. Hãy kiểm tra cấu hình OAuth của ứng dụng.',
          cause: error,
        ),
      );
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.unknown,
          code: 'GOOGLE_SIGN_IN_FAILED',
          message:
              'Không thể đăng nhập Google. Hãy kiểm tra cấu hình OAuth của ứng dụng.',
          cause: error,
        ),
      );
    }
  }

  Future<void> _initialize() {
    return GoogleSignIn.instance.initialize(
      clientId: _clientId.isEmpty ? null : _clientId,
      serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
    );
  }
}
