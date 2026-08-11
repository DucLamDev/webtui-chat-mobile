import '../../../../core/result/result.dart';
import '../entities/auth_session.dart';
import '../entities/device_identity.dart';
import '../entities/legal_acceptance.dart';
import '../entities/legal_document_versions.dart';
import '../entities/oidc_provider.dart';
import '../entities/user_session.dart';

abstract interface class AuthRepository {
  Future<Result<LegalDocumentVersions>> loadLegalDocumentVersions();

  Future<Result<LegalAcceptance>> loadLegalAcceptance({
    required String workspaceId,
  });

  Future<Result<LegalAcceptance>> acceptLegalDocuments({
    required String workspaceId,
    required String termsVersion,
    required String privacyVersion,
  });

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
    String inviteToken,
    bool termsAccepted = false,
    String termsVersion = '',
    bool privacyAccepted = false,
    String privacyVersion = '',
    required DeviceIdentity device,
  });

  Future<Result<List<OidcProvider>>> listOidcProviders(String domain);

  Future<Result<Uri>> startOidc({
    required String domain,
    required String providerId,
    required String returnTo,
    required DeviceIdentity device,
  });

  Future<Result<AuthSession>> completeOidc({
    required String code,
    required String domain,
    required DeviceIdentity device,
  });

  Future<Result<AuthSession>> refresh(String refreshToken);

  Future<Result<void>> logout(String refreshToken);

  Future<Result<List<UserSession>>> listSessions();

  Future<Result<void>> revokeSession(String sessionId);

  Future<Result<void>> revokeAllSessions();
}
