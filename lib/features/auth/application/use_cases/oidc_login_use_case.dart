import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/oidc_provider.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/device_identity_repository.dart';

final class OidcLoginUseCase {
  const OidcLoginUseCase({
    required AuthRepository authRepository,
    required AuthTokenRepository tokenRepository,
    required DeviceIdentityRepository deviceIdentityRepository,
  }) : _authRepository = authRepository,
       _tokenRepository = tokenRepository,
       _deviceIdentityRepository = deviceIdentityRepository;

  final AuthRepository _authRepository;
  final AuthTokenRepository _tokenRepository;
  final DeviceIdentityRepository _deviceIdentityRepository;

  Future<Result<List<OidcProvider>>> providers(String domain) {
    return _authRepository.listOidcProviders(_domainHost(domain));
  }

  Future<Result<Uri>> start({
    required String domain,
    required String providerId,
  }) async {
    final normalizedDomain = _domainHost(domain);
    if (normalizedDomain.isEmpty || providerId.trim().isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          code: 'OIDC_INPUT_REQUIRED',
          message: 'Thiếu thông tin máy chủ hoặc nhà cung cấp SSO.',
        ),
      );
    }
    try {
      final device = await _deviceIdentityRepository.currentDevice();
      return _authRepository.startOidc(
        domain: normalizedDomain,
        providerId: providerId.trim(),
        returnTo: Uri(
          scheme: 'webtui',
          host: 'oidc',
          path: '/callback',
          queryParameters: {'server': normalizedDomain},
        ).toString(),
        device: device,
      );
    } on Object catch (error) {
      return FailureResult(_storageFailure(error));
    }
  }

  Future<Result<AuthSession>> complete({
    required String code,
    required String domain,
  }) async {
    final normalizedDomain = _domainHost(domain);
    if (code.trim().isEmpty || normalizedDomain.isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          code: 'OIDC_CALLBACK_INVALID',
          message: 'Callback đăng nhập SSO không hợp lệ.',
        ),
      );
    }
    try {
      final device = await _deviceIdentityRepository.currentDevice();
      final result = await _authRepository.completeOidc(
        code: code.trim(),
        domain: normalizedDomain,
        device: device,
      );
      if (result case Success<AuthSession>(:final value)) {
        await _tokenRepository.saveTokens(value.tokens);
      }
      return result;
    } on Object catch (error) {
      return FailureResult(_storageFailure(error));
    }
  }
}

String _domainHost(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  return uri?.host.toLowerCase() ?? '';
}

Failure _storageFailure(Object error) {
  return Failure(
    kind: FailureKind.storage,
    code: 'OIDC_LOGIN_STORAGE_FAILURE',
    message: 'Không thể hoàn tất và lưu phiên đăng nhập SSO an toàn.',
    cause: error,
  );
}
