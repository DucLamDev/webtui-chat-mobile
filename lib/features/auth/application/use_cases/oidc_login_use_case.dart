import 'package:uuid/uuid.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/security/instance_scope.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/oidc_provider.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../../domain/repositories/device_identity_repository.dart';

final class OidcLoginUseCase {
  OidcLoginUseCase({
    required AuthRepository authRepository,
    required AuthTokenRepository tokenRepository,
    required DeviceIdentityRepository deviceIdentityRepository,
    required Uri? Function() loadExpectedServerOrigin,
    Uuid uuid = const Uuid(),
  }) : _authRepository = authRepository,
       _tokenRepository = tokenRepository,
       _deviceIdentityRepository = deviceIdentityRepository,
       _loadExpectedServerOrigin = loadExpectedServerOrigin,
       _uuid = uuid;

  final AuthRepository _authRepository;
  final AuthTokenRepository _tokenRepository;
  final DeviceIdentityRepository _deviceIdentityRepository;
  final Uri? Function() _loadExpectedServerOrigin;
  final Uuid _uuid;
  _PendingOidcAttempt? _pendingAttempt;
  int _attemptGeneration = 0;

  Future<Result<List<OidcProvider>>> providers(String domain) {
    return _authRepository.listOidcProviders(_domainHost(domain));
  }

  Future<Result<Uri>> start({
    required String domain,
    required String providerId,
  }) async {
    final requestGeneration = ++_attemptGeneration;
    _pendingAttempt = null;
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
    if (!_domainMatchesExpectedServer(domain)) {
      return const FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          code: 'OIDC_INSTANCE_MISMATCH',
          message: 'Callback SSO không thuộc máy chủ đang hoạt động.',
        ),
      );
    }
    try {
      final guard = await _tokenRepository.captureMutationGuard();
      if (guard == null) {
        throw StateError('Active instance is not live validated.');
      }
      final attemptId = _uuid.v4();
      final device = await _deviceIdentityRepository.currentDevice();
      if (await _tokenRepository.captureMutationGuard() != guard) {
        throw StateError('Active instance changed during OIDC start.');
      }
      final result = await _authRepository.startOidc(
        domain: normalizedDomain,
        providerId: providerId.trim(),
        returnTo: Uri(
          scheme: 'webtui',
          host: 'oidc',
          path: '/callback',
          queryParameters: {
            'server': normalizedDomain,
            'instance_scope': guard.instanceScopeId,
            'attempt': attemptId,
          },
        ).toString(),
        device: device,
      );
      if (await _tokenRepository.captureMutationGuard() != guard) {
        throw StateError('Active instance changed during OIDC start.');
      }
      if (requestGeneration != _attemptGeneration) {
        throw StateError('A newer OIDC attempt replaced this request.');
      }
      if (result case Success<Uri>()) {
        _pendingAttempt = _PendingOidcAttempt(
          id: attemptId,
          domain: normalizedDomain,
          guard: guard,
        );
      }
      return result;
    } on Object catch (error) {
      return FailureResult(_storageFailure(error));
    }
  }

  Future<Result<AuthSession>> complete({
    required String code,
    required String domain,
    required String instanceScopeId,
    required String attemptId,
    bool remember = true,
  }) async {
    final normalizedDomain = _domainHost(domain);
    final normalizedScopeId = instanceScopeId.trim();
    final normalizedAttemptId = attemptId.trim();
    if (code.trim().isEmpty ||
        normalizedDomain.isEmpty ||
        normalizedScopeId.isEmpty ||
        normalizedAttemptId.isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          code: 'OIDC_CALLBACK_INVALID',
          message: 'Callback đăng nhập SSO không hợp lệ.',
        ),
      );
    }
    if (!_domainMatchesExpectedServer(domain)) {
      return const FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          code: 'OIDC_INSTANCE_MISMATCH',
          message: 'Callback SSO không thuộc máy chủ đang hoạt động.',
        ),
      );
    }
    final pending = _pendingAttempt;
    if (pending == null ||
        pending.id != normalizedAttemptId ||
        pending.domain != normalizedDomain ||
        pending.guard.instanceScopeId != normalizedScopeId) {
      return const FailureResult(
        Failure(
          kind: FailureKind.unauthorized,
          code: 'OIDC_ATTEMPT_MISMATCH',
          message: 'Callback SSO không khớp với phiên đăng nhập đã bắt đầu.',
        ),
      );
    }
    _pendingAttempt = null;
    _attemptGeneration++;
    try {
      final guard = await _tokenRepository.captureMutationGuard();
      if (guard == null || guard != pending.guard) {
        throw StateError('OIDC callback instance no longer matches its start.');
      }
      final device = await _deviceIdentityRepository.currentDevice();
      if (await _tokenRepository.captureMutationGuard() != guard) {
        throw StateError('Active instance changed during OIDC completion.');
      }
      final result = await _authRepository.completeOidc(
        code: code.trim(),
        domain: normalizedDomain,
        device: device,
      );
      if (result case Success<AuthSession>(:final value)) {
        if (!await _tokenRepository.saveTokensIfCurrent(
          value.tokens,
          guard,
          persistence: remember
              ? AuthTokenPersistence.durable
              : AuthTokenPersistence.sessionOnly,
        )) {
          throw StateError('Active instance changed during OIDC completion.');
        }
      }
      return result;
    } on Object catch (error) {
      return FailureResult(_storageFailure(error));
    }
  }

  bool _domainMatchesExpectedServer(String domain) {
    final expected = _loadExpectedServerOrigin();
    if (expected == null) return false;
    try {
      final canonicalExpected = canonicalServerOrigin(expected);
      final trimmed = domain.trim();
      final candidate = Uri.tryParse(
        trimmed.contains('://')
            ? trimmed
            : '${canonicalExpected.scheme}://$trimmed',
      );
      return candidate != null &&
          candidate.path.isEmpty &&
          candidate.query.isEmpty &&
          candidate.fragment.isEmpty &&
          serverOriginsMatch(candidate, canonicalExpected);
    } on FormatException {
      return false;
    }
  }
}

final class _PendingOidcAttempt {
  const _PendingOidcAttempt({
    required this.id,
    required this.domain,
    required this.guard,
  });

  final String id;
  final String domain;
  final AuthTokenMutationGuard guard;
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
