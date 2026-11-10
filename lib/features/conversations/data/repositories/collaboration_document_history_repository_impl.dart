import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/collaboration_document_version.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/repositories/collaboration_document_history_repository.dart';
import '../datasources/collaboration_document_history_remote_data_source.dart';

final class CollaborationDocumentHistoryRepositoryImpl
    implements CollaborationDocumentHistoryRepository {
  const CollaborationDocumentHistoryRepositoryImpl(this._remote);

  final CollaborationDocumentHistoryRemoteDataSource _remote;

  @override
  Future<Result<CollaborationDocument>> getDocument({
    required String workspaceId,
    required String channelId,
    required String kind,
  }) {
    return guardResult(
      () => _remote.getDocument(
        workspaceId: workspaceId,
        channelId: channelId,
        kind: kind,
      ),
    );
  }

  @override
  Future<Result<List<CollaborationDocumentVersion>>> listVersions({
    required String workspaceId,
    required String channelId,
    required String kind,
    int limit = 50,
  }) {
    return guardResult(
      () => _remote.listVersions(
        workspaceId: workspaceId,
        channelId: channelId,
        kind: kind,
        limit: limit,
      ),
    );
  }

  @override
  Future<Result<CollaborationDocumentVersionDetail>> getVersion({
    required String workspaceId,
    required String channelId,
    required String kind,
    required int version,
  }) {
    return guardResult(
      () => _remote.getVersion(
        workspaceId: workspaceId,
        channelId: channelId,
        kind: kind,
        version: version,
      ),
    );
  }

  @override
  Future<Result<CollaborationDocument>> restoreVersion({
    required String workspaceId,
    required String channelId,
    required String kind,
    required int version,
    required int expectedVersion,
  }) {
    return guardResult(
      () => _remote.restoreVersion(
        workspaceId: workspaceId,
        channelId: channelId,
        kind: kind,
        version: version,
        expectedVersion: expectedVersion,
      ),
    );
  }
}
