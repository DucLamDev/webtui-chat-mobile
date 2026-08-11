import '../../../../core/result/result.dart';
import '../../domain/entities/legal_document_versions.dart';
import '../../domain/repositories/auth_repository.dart';

final class LoadLegalDocumentVersionsUseCase {
  const LoadLegalDocumentVersionsUseCase(this._repository);

  final AuthRepository _repository;

  Future<Result<LegalDocumentVersions>> execute() {
    return _repository.loadLegalDocumentVersions();
  }
}
