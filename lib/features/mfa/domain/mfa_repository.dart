import '../../../core/result/result.dart';

final class MfaStatus {
  const MfaStatus({required this.enabled, required this.totpEnabled});
  final bool enabled;
  final bool totpEnabled;
}

final class TotpEnrollment {
  const TotpEnrollment({required this.secret, required this.uri});
  final String secret;
  final String uri;
}

abstract interface class MfaRepository {
  Future<Result<MfaStatus>> status();
  Future<Result<String>> reauthenticate({
    required String method,
    required String value,
  });
  Future<Result<TotpEnrollment>> enroll(String token);
  Future<Result<List<String>>> confirm(String code);
  Future<Result<void>> disable(String token);
}
