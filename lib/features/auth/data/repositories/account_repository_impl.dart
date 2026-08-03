import '../../../../core/network/api_transport.dart';
import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/repositories/account_repository.dart';

final class AccountRepositoryImpl implements AccountRepository {
  const AccountRepositoryImpl(this._api);

  final ApiTransport _api;

  @override
  Future<Result<void>> deleteAccount({
    required String confirmation,
    String? ownershipSuccessorEmail,
  }) {
    return guardResult(() async {
      final normalizedSuccessorEmail = ownershipSuccessorEmail?.trim();
      await _api.delete<Object>(
        '/api/v1/users/me',
        data: {
          'confirmation': confirmation,
          if (normalizedSuccessorEmail != null &&
              normalizedSuccessorEmail.isNotEmpty)
            'ownership_successor_email': normalizedSuccessorEmail,
        },
      );
    });
  }
}
