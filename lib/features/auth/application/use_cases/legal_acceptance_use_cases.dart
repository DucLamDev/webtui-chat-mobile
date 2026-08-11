import '../../../../core/result/result.dart';
import '../../domain/entities/legal_acceptance.dart';
import '../../domain/repositories/auth_repository.dart';

final class LoadLegalAcceptanceUseCase {
  const LoadLegalAcceptanceUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<LegalAcceptance>> execute({required String workspaceId}) {
    return _repository.loadLegalAcceptance(workspaceId: workspaceId);
  }
}

final class AcceptLegalDocumentsUseCase {
  const AcceptLegalDocumentsUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<LegalAcceptance>> execute({
    required String workspaceId,
    required String termsVersion,
    required String privacyVersion,
  }) {
    return _repository.acceptLegalDocuments(
      workspaceId: workspaceId,
      termsVersion: termsVersion,
      privacyVersion: privacyVersion,
    );
  }
}
