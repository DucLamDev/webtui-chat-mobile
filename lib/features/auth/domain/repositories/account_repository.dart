import '../../../../core/result/result.dart';

abstract interface class AccountRepository {
  Future<Result<void>> deleteAccount({
    required String confirmation,
    String? ownershipSuccessorEmail,
  });
}
