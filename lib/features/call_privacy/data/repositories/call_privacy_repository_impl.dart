import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/call_privacy.dart';
import '../../domain/repositories/call_privacy_repository.dart';
import '../datasources/call_privacy_remote_data_source.dart';

final class CallPrivacyRepositoryImpl implements CallPrivacyRepository {
  const CallPrivacyRepositoryImpl(this._remote);

  final CallPrivacyRemoteDataSource _remote;

  @override
  Future<Result<WhoCanCallMe>> load({required String workspaceId}) {
    return guardResult(() => _remote.load(workspaceId: workspaceId));
  }

  @override
  Future<Result<WhoCanCallMe>> update({
    required String workspaceId,
    required WhoCanCallMe value,
  }) {
    return guardResult(
      () => _remote.update(workspaceId: workspaceId, value: value),
    );
  }
}
