import '../../../../core/result/result.dart';

abstract interface class AccountRepository {
  /// [reauthToken] lấy từ `POST /api/v1/auth/reauth` trên cùng thiết bị.
  Future<Result<void>> deleteAccount({
    required String confirmation,
    required String reauthToken,
    String? ownershipSuccessorEmail,
  });
}
