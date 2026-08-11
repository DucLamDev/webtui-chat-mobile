import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/device_identity.dart';
import '../../domain/entities/legal_acceptance.dart';
import '../../domain/entities/legal_document_versions.dart';
import '../../domain/entities/oidc_provider.dart';
import '../../domain/entities/user_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

final class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Future<Result<LegalDocumentVersions>> loadLegalDocumentVersions() {
    return guardResult(_remote.loadLegalDocumentVersions);
  }

  @override
  Future<Result<LegalAcceptance>> loadLegalAcceptance({
    required String workspaceId,
  }) {
    return guardResult(
      () => _remote.loadLegalAcceptance(workspaceId: workspaceId),
    );
  }

  @override
  Future<Result<LegalAcceptance>> acceptLegalDocuments({
    required String workspaceId,
    required String termsVersion,
    required String privacyVersion,
  }) {
    return guardResult(
      () => _remote.acceptLegalDocuments(
        workspaceId: workspaceId,
        termsVersion: termsVersion,
        privacyVersion: privacyVersion,
      ),
    );
  }

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
    String inviteToken = '',
    bool termsAccepted = false,
    String termsVersion = '',
    bool privacyAccepted = false,
    String privacyVersion = '',
    required DeviceIdentity device,
  }) {
    return guardResult(
      () => _remote.register(
        displayName: displayName,
        email: email,
        username: username,
        password: password,
        inviteToken: inviteToken,
        termsAccepted: termsAccepted,
        termsVersion: termsVersion,
        privacyAccepted: privacyAccepted,
        privacyVersion: privacyVersion,
        device: device,
      ),
    );
  }

  @override
  Future<Result<List<OidcProvider>>> listOidcProviders(String domain) {
    return guardResult(() => _remote.listOidcProviders(domain));
  }

  @override
  Future<Result<Uri>> startOidc({
    required String domain,
    required String providerId,
    required String returnTo,
    required DeviceIdentity device,
  }) {
    return guardResult(
      () => _remote.startOidc(
        domain: domain,
        providerId: providerId,
        returnTo: returnTo,
        device: device,
      ),
    );
  }

  @override
  Future<Result<AuthSession>> completeOidc({
    required String code,
    required String domain,
    required DeviceIdentity device,
  }) {
    return guardResult(
      () => _remote.completeOidc(code: code, domain: domain, device: device),
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
