import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/collaboration_document_version.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/repositories/collaboration_document_history_repository.dart';

/// Câu báo khi khôi phục mà tài liệu đã bị người khác sửa trước.
const collaborationDocumentConflictMessage =
    'Tài liệu vừa được người khác sửa, hãy tải lại';

const _supportedKinds = {'notes', 'whiteboard'};

Failure? _invalidKind(String kind) => _supportedKinds.contains(kind)
    ? null
    : const Failure(
        kind: FailureKind.validation,
        message: 'Loại tài liệu không hợp lệ.',
        code: 'VALIDATION_ERROR',
      );

final class LoadCollaborationDocumentUseCase {
  const LoadCollaborationDocumentUseCase(this._repository);

  final CollaborationDocumentHistoryRepository _repository;

  Future<Result<CollaborationDocument>> execute({
    required String workspaceId,
    required String channelId,
    required String kind,
  }) {
    final failure = _invalidKind(kind);
    if (failure != null) return Future.value(FailureResult(failure));
    return _repository.getDocument(
      workspaceId: workspaceId,
      channelId: channelId,
      kind: kind,
    );
  }
}

final class ListCollaborationDocumentVersionsUseCase {
  const ListCollaborationDocumentVersionsUseCase(this._repository);

  final CollaborationDocumentHistoryRepository _repository;

  Future<Result<List<CollaborationDocumentVersion>>> execute({
    required String workspaceId,
    required String channelId,
    required String kind,
    int limit = 50,
  }) async {
    final failure = _invalidKind(kind);
    if (failure != null) return FailureResult(failure);
    final result = await _repository.listVersions(
      workspaceId: workspaceId,
      channelId: channelId,
      kind: kind,
      limit: limit.clamp(1, 200).toInt(),
    );
    return switch (result) {
      Success(:final value) => Success(
        List.unmodifiable(
          [...value]
            ..sort((left, right) => right.version.compareTo(left.version)),
        ),
      ),
      FailureResult() => result,
    };
  }
}

final class LoadCollaborationDocumentVersionUseCase {
  const LoadCollaborationDocumentVersionUseCase(this._repository);

  final CollaborationDocumentHistoryRepository _repository;

  Future<Result<CollaborationDocumentVersionDetail>> execute({
    required String workspaceId,
    required String channelId,
    required String kind,
    required int version,
  }) {
    final failure = _invalidKind(kind);
    if (failure != null) return Future.value(FailureResult(failure));
    return _repository.getVersion(
      workspaceId: workspaceId,
      channelId: channelId,
      kind: kind,
      version: version,
    );
  }
}

/// Khôi phục một bản cũ. Xung đột phiên bản đổi thành câu báo chung để người
/// dùng biết phải tải lại.
final class RestoreCollaborationDocumentVersionUseCase {
  const RestoreCollaborationDocumentVersionUseCase(this._repository);

  final CollaborationDocumentHistoryRepository _repository;

  Future<Result<CollaborationDocument>> execute({
    required String workspaceId,
    required String channelId,
    required String kind,
    required int version,
    required int expectedVersion,
  }) async {
    final failure = _invalidKind(kind);
    if (failure != null) return FailureResult(failure);
    final result = await _repository.restoreVersion(
      workspaceId: workspaceId,
      channelId: channelId,
      kind: kind,
      version: version,
      expectedVersion: expectedVersion,
    );
    if (result case FailureResult(:final failure)
        when failure.code == 'DOCUMENT_VERSION_CONFLICT' ||
            (failure.kind == FailureKind.conflict &&
                (failure.code ?? '').isEmpty)) {
      return FailureResult(
        failure.copyWith(
          kind: FailureKind.conflict,
          message: collaborationDocumentConflictMessage,
          code: 'DOCUMENT_VERSION_CONFLICT',
        ),
      );
    }
    return result;
  }
}
