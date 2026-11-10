import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/collaboration_document_version.dart';
import '../../domain/entities/collaboration_room.dart';
import 'conversation_remote_data_source.dart';

/// REST lịch sử phiên bản ghi chú / bảng trắng của phòng.
final class CollaborationDocumentHistoryRemoteDataSource {
  const CollaborationDocumentHistoryRemoteDataSource(this._api);

  final ApiTransport _api;

  String _documentPath(String workspaceId, String channelId, String kind) =>
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/collaboration/documents/${_e(kind)}';

  Future<CollaborationDocument> getDocument({
    required String workspaceId,
    required String channelId,
    required String kind,
  }) async {
    final response = await _api.get<Object>(
      _documentPath(workspaceId, channelId, kind),
    );
    return collaborationDocumentFromJson(
      envelopeItem(response.data, 'document'),
    );
  }

  Future<List<CollaborationDocumentVersion>> listVersions({
    required String workspaceId,
    required String channelId,
    required String kind,
    int limit = 50,
  }) async {
    final response = await _api.get<Object>(
      '${_documentPath(workspaceId, channelId, kind)}/versions',
      queryParameters: {'limit': limit},
    );
    return [
      for (final map in envelopeList(response.data, 'versions'))
        CollaborationDocumentVersion(
          version: intField(map, const ['version']),
          authorId: nullableStringField(map, const ['author_id']),
          authorName: nullableStringField(map, const ['author_name']),
          createdAt: dateTimeField(map, const ['created_at']),
          updatedAt: dateTimeField(map, const ['updated_at', 'created_at']),
          sizeBytes: intField(map, const ['size_bytes']),
        ),
    ];
  }

  Future<CollaborationDocumentVersionDetail> getVersion({
    required String workspaceId,
    required String channelId,
    required String kind,
    required int version,
  }) async {
    final response = await _api.get<Object>(
      '${_documentPath(workspaceId, channelId, kind)}/versions/$version',
    );
    final map = envelopeItem(response.data, 'version');
    return CollaborationDocumentVersionDetail(
      version: intField(map, const ['version'], fallback: version),
      content: {
        for (final entry in jsonMap(map['content']).entries)
          entry.key: entry.value as Object?,
      },
      authorId: nullableStringField(map, const ['author_id']),
      authorName: nullableStringField(map, const ['author_name']),
      createdAt: dateTimeField(map, const ['created_at']),
      updatedAt: dateTimeField(map, const ['updated_at', 'created_at']),
    );
  }

  Future<CollaborationDocument> restoreVersion({
    required String workspaceId,
    required String channelId,
    required String kind,
    required int version,
    required int expectedVersion,
  }) async {
    final response = await _api.post<Object>(
      '${_documentPath(workspaceId, channelId, kind)}/versions/$version/restore',
      data: {'expected_version': expectedVersion},
    );
    return collaborationDocumentFromJson(
      envelopeItem(response.data, 'document'),
    );
  }
}

String _e(String value) => Uri.encodeComponent(value);
