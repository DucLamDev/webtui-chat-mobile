import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/call_privacy.dart';
import '../../domain/repositories/call_privacy_repository.dart';

const _missingWorkspace = FailureResult<WhoCanCallMe>(
  Failure(
    kind: FailureKind.validation,
    message: 'Chưa chọn workspace.',
    code: 'WORKSPACE_REQUIRED',
  ),
);

final class LoadCallPrivacyUseCase {
  const LoadCallPrivacyUseCase(this._repository);

  final CallPrivacyRepository _repository;

  Future<Result<WhoCanCallMe>> execute(String workspaceId) {
    if (workspaceId.trim().isEmpty) {
      return Future.value(_missingWorkspace);
    }
    return _repository.load(workspaceId: workspaceId.trim());
  }
}

final class UpdateCallPrivacyUseCase {
  const UpdateCallPrivacyUseCase(this._repository);

  final CallPrivacyRepository _repository;

  Future<Result<WhoCanCallMe>> execute(String workspaceId, WhoCanCallMe value) {
    if (workspaceId.trim().isEmpty) {
      return Future.value(_missingWorkspace);
    }
    return _repository.update(workspaceId: workspaceId.trim(), value: value);
  }
}
