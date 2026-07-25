import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/chat_message.dart';

final class MessageAttachmentRemoteDataSource {
  const MessageAttachmentRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<UploadedMessageFile> uploadFile({
    required String workspaceId,
    required PickedMessageAttachment attachment,
  }) async {
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
    return _uploadedFileFromMap(
      envelopeItem(response.data, 'file'),
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

String _e(String value) => Uri.encodeComponent(value);
