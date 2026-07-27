import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/chat_message.dart';

final class MessageAttachmentRemoteDataSource {
  MessageAttachmentRemoteDataSource(this._api);

  final ApiTransport _api;
  final Map<String, String> _resumableSessions = {};

  static const int resumableThreshold = 8 * 1024 * 1024;
  static const int uploadChunkSize = 5 * 1024 * 1024;

  Future<UploadedMessageFile> uploadFile({
    required String workspaceId,
    required PickedMessageAttachment attachment,
    void Function(double progress)? onProgress,
  }) async {
    if (attachment.byteSize >= resumableThreshold) {
      return _uploadResumable(
        workspaceId: workspaceId,
        attachment: attachment,
        onProgress: onProgress,
      );
    }
    onProgress?.call(0.1);
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        attachment.path,
        filename: attachment.fileName,
        contentType: DioMediaType.parse(attachment.mimeType),
      ),
    });
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/files',
      data: form,
      options: Options(contentType: Headers.multipartFormDataContentType),
    );
    onProgress?.call(1);
    return _uploadedFileFromMap(
      envelopeItem(response.data, 'file'),
      fallbackWorkspaceId: workspaceId,
    );
  }

  Future<UploadedMessageFile> _uploadResumable({
    required String workspaceId,
    required PickedMessageAttachment attachment,
    void Function(double progress)? onProgress,
  }) async {
    final cacheKey =
        '$workspaceId|${attachment.path}|${attachment.byteSize}|${attachment.fileName}';
    _UploadSession? session;
    final cachedId = _resumableSessions[cacheKey];
    if (cachedId != null) {
      try {
        final response = await _api.get<Object>(
          '/api/v1/workspaces/${_e(workspaceId)}/files/uploads/${_e(cachedId)}',
        );
        final current = _uploadSessionFromMap(
          envelopeItem(response.data, 'upload'),
        );
        if (current.status == 'uploading') session = current;
      } catch (_) {
        _resumableSessions.remove(cacheKey);
      }
    }
    if (session == null) {
      final response = await _api.post<Object>(
        '/api/v1/workspaces/${_e(workspaceId)}/files/uploads',
        data: {
          'original_name': attachment.fileName,
          'mime_type': attachment.mimeType,
          'total_size': attachment.byteSize,
          'chunk_size': uploadChunkSize,
          'metadata': {
            'source': 'flutter_mobile',
            'kind': attachment.kind.name,
          },
        },
      );
      session = _uploadSessionFromMap(envelopeItem(response.data, 'upload'));
      _resumableSessions[cacheKey] = session.id;
    }

    final file = await File(attachment.path).open();
    try {
      final uploaded = session.uploadedParts.toSet();
      var uploadedBytes = session.receivedBytes;
      onProgress?.call(
        attachment.byteSize == 0 ? 0 : uploadedBytes / attachment.byteSize,
      );
      for (var part = 0; part < session.totalChunks; part++) {
        if (uploaded.contains(part)) continue;
        final offset = part * session.chunkSize;
        final remaining = attachment.byteSize - offset;
        final length = remaining < session.chunkSize
            ? remaining
            : session.chunkSize;
        await file.setPosition(offset);
        final bytes = await file.read(length);
        final checksum = sha256.convert(bytes).toString();
        await _api.put<Object>(
          '/api/v1/workspaces/${_e(workspaceId)}/files/uploads/${_e(session.id)}/parts/$part',
          data: bytes,
          options: Options(
            contentType: 'application/octet-stream',
            headers: {
              'Content-Length': bytes.length,
              'X-Chunk-SHA256': checksum,
            },
          ),
        );
        uploadedBytes += bytes.length;
        onProgress?.call(uploadedBytes / attachment.byteSize);
      }
    } finally {
      await file.close();
    }

    final completed = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/files/uploads/${_e(session.id)}/complete',
      data: const {},
    );
    _resumableSessions.remove(cacheKey);
    onProgress?.call(1);
    return _uploadedFileFromMap(
      envelopeItem(completed.data, 'file'),
      fallbackWorkspaceId: workspaceId,
    );
  }

  Future<MessageAttachment> attachFile({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String fileId,
    int sortOrder = 0,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/attachments',
      data: {'file_id': fileId, 'sort_order': sortOrder},
    );
    return _attachmentFromMap(
      envelopeItem(response.data, 'attachment'),
      fallbackWorkspaceId: workspaceId,
    );
  }

  Future<List<MessageAttachment>> listAttachments({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/messages/${_e(messageId)}/attachments',
    );
    return envelopeList(response.data, 'attachments')
        .map(
          (item) => _attachmentFromMap(item, fallbackWorkspaceId: workspaceId),
        )
        .toList(growable: false);
  }

  Future<List<MessageAttachment>> listChannelMedia({
    required String workspaceId,
    required String channelId,
    int limit = 500,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/channels/${_e(channelId)}/media',
      queryParameters: {'limit': limit},
    );
    return envelopeList(response.data, 'attachments')
        .map(
          (item) => _attachmentFromMap(item, fallbackWorkspaceId: workspaceId),
        )
        .toList(growable: false);
  }

  Future<Uint8List> downloadFileBytes({
    required String downloadPath,
    String? mimeType,
  }) async {
    final response = await _api.get<List<int>>(
      downloadPath,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Accept': _acceptHeader(mimeType)},
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      return Uint8List(0);
    }
    return Uint8List.fromList(bytes);
  }
}

String _acceptHeader(String? mimeType) {
  final normalized = mimeType?.trim();
  if (normalized == null || normalized.isEmpty) {
    return 'application/octet-stream';
  }
  return normalized;
}

MessageAttachment _attachmentFromMap(
  JsonMap map, {
  required String fallbackWorkspaceId,
}) {
  final fileMap = jsonMap(field(map, const ['file']));
  final workspaceId = stringField(map, const [
    'workspace_id',
    'workspaceId',
  ], fallback: fallbackWorkspaceId);
  final file = _uploadedFileFromMap(fileMap, fallbackWorkspaceId: workspaceId);
  final fileId = stringField(map, const [
    'file_id',
    'fileId',
  ], fallback: file.id);
  final messageId = stringField(map, const ['message_id', 'messageId']);
  return MessageAttachment(
    id: stringField(map, const ['id'], fallback: '$messageId:$fileId'),
    workspaceId: workspaceId,
    messageId: messageId,
    fileId: fileId,
    sortOrder: intField(map, const ['sort_order', 'sortOrder']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
    file: file,
  );
}

UploadedMessageFile _uploadedFileFromMap(
  JsonMap map, {
  required String fallbackWorkspaceId,
}) {
  final id = stringField(map, const ['id', 'file_id', 'fileId']);
  final workspaceId = stringField(map, const [
    'workspace_id',
    'workspaceId',
  ], fallback: fallbackWorkspaceId);
  return UploadedMessageFile(
    id: id,
    name: stringField(map, const [
      'name',
      'file_name',
      'original_name',
      'originalName',
    ], fallback: 'file'),
    mimeType: stringField(map, const ['mime_type', 'mimeType']),
    byteSize: intField(map, const ['byte_size', 'byteSize', 'size']),
    downloadPath: stringField(map, const [
      'download_url',
      'downloadUrl',
      'url',
    ], fallback: _downloadPathFallback(workspaceId, id)),
    status: stringField(map, const ['status'], fallback: 'ready'),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

String _downloadPathFallback(String workspaceId, String fileId) {
  if (workspaceId.isEmpty || fileId.isEmpty) {
    return '';
  }
  return '/api/v1/workspaces/${_e(workspaceId)}/files/${_e(fileId)}/download';
}

final class _UploadSession {
  const _UploadSession({
    required this.id,
    required this.chunkSize,
    required this.totalChunks,
    required this.receivedBytes,
    required this.uploadedParts,
    required this.status,
  });

  final String id;
  final int chunkSize;
  final int totalChunks;
  final int receivedBytes;
  final List<int> uploadedParts;
  final String status;
}

_UploadSession _uploadSessionFromMap(JsonMap map) {
  final rawParts = map['uploaded_parts'];
  return _UploadSession(
    id: stringField(map, const ['id']),
    chunkSize: intField(map, const ['chunk_size'], fallback: 5 * 1024 * 1024),
    totalChunks: intField(map, const ['total_chunks']),
    receivedBytes: intField(map, const ['received_bytes']),
    uploadedParts: rawParts is List
        ? rawParts
              .map(jsonMap)
              .map(
                (part) => intField(part, const ['part_number'], fallback: -1),
              )
              .where((part) => part >= 0)
              .toList(growable: false)
        : const [],
    status: stringField(map, const ['status'], fallback: 'uploading'),
  );
}

String _e(String value) => Uri.encodeComponent(value);
