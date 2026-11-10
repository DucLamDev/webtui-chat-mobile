import '../../../core/result/result.dart';
import '../domain/mfa_repository.dart';

/// Token chỉ trả cho thao tác hiện tại, không lưu trên đĩa hay tái sử dụng giữa tài khoản.
final class MfaUseCases {
  const MfaUseCases(this._repository);
  final MfaRepository _repository;
  Future<Result<MfaStatus>> status() => _repository.status();
  Future<Result<String>> reauthenticate(String method, String value) =>
      _repository.reauthenticate(method: method, value: value);
  Future<Result<TotpEnrollment>> enroll(String token) =>
      _repository.enroll(token);
  Future<Result<List<String>>> confirm(String code) =>
      _repository.confirm(code);
  Future<Result<void>> disable(String token) => _repository.disable(token);
}
