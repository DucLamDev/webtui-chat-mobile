import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/chat_message.dart';

final class MessageAttachmentRemoteDataSource {
  MessageAttachmentRemoteDataSource(
    this._api, {
    Future<void> Function(Duration delay)? wait,
  }) : _wait = wait ?? Future<void>.delayed;

  final ApiTransport _api;
  final Future<void> Function(Duration delay) _wait;
  final Map<String, String> _resumableSessions = {};

  static const int resumableThreshold = 8 * 1024 * 1024;
  static const int uploadChunkSize = 5 * 1024 * 1024;
  static const int uploadConcurrency = 3;
  static const int maxPartRetries = 2;

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

    final uploaded = session.uploadedParts.toSet();
    final missing = <int>[
      for (var part = 0; part < session.totalChunks; part++)
        if (!uploaded.contains(part)) part,
    ];
    final total = attachment.byteSize;
    var uploadedBytes = session.receivedBytes;
    double ratio() =>
        total <= 0 ? 0 : (uploadedBytes / total).clamp(0.0, 1.0).toDouble();
    onProgress?.call(ratio());

    final sessionId = session.id;
    final chunkSize = session.chunkSize;
    var cursor = 0;
    Object? firstError;
    StackTrace? firstStack;

    Future<void> worker() async {
      RandomAccessFile? file;
      try {
        file = await File(attachment.path).open();
        while (firstError == null && cursor < missing.length) {
          final part = missing[cursor++];
          final offset = part * chunkSize;
          final remaining = total - offset;
          final length = remaining < chunkSize ? remaining : chunkSize;
          await file.setPosition(offset);
          final bytes = await file.read(length);
          final checksum = await _sha256InBackground(bytes);
          await _putPartWithRetry(
            '/api/v1/workspaces/${_e(workspaceId)}/files/uploads/${_e(sessionId)}/parts/$part',
            bytes,
            checksum,
          );
          uploadedBytes += bytes.length;
          onProgress?.call(ratio());
        }
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      } finally {
        await file?.close();
      }
    }

    if (missing.isNotEmpty) {
      await Future.wait([
        for (var i = 0; i < min(uploadConcurrency, missing.length); i++)
          worker(),
      ]);
    }
    final failure = firstError;
    if (failure != null) {
      Error.throwWithStackTrace(failure, firstStack ?? StackTrace.current);
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

  Future<void> _putPartWithRetry(
    String path,
    Uint8List bytes,
    String checksum,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _api.put<Object>(
          path,
          data: bytes,
          options: Options(
            contentType: 'application/octet-stream',
            headers: {
              'Content-Length': bytes.length,
              'X-Chunk-SHA256': checksum,
            },
          ),
        );
        return;
      } on DioException catch (error) {
        if (attempt >= maxPartRetries || !_isTransient(error)) rethrow;
        await _wait(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }

  static bool _isTransient(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode ?? 0;
        return code == 429 || (code >= 500 && code < 600);
      default:
        return false;
    }
  }

  Future<UploadedMessageFile> uploadThumbnail({
    required String workspaceId,
    required String fileId,
    required String thumbnailPath,
    int? durationMs,
    int? width,
    int? height,
  }) async {
    final form = FormData.fromMap({
      'thumbnail': await MultipartFile.fromFile(
        thumbnailPath,
        filename: 'thumbnail.jpg',
        contentType: DioMediaType.parse('image/jpeg'),
      ),
      if (durationMs != null && durationMs > 0) 'duration_ms': '$durationMs',
      if (width != null && width > 0) 'width': '$width',
      if (height != null && height > 0) 'height': '$height',
    });
    final response = await _api.put<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/files/${_e(fileId)}/thumbnail',
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

/// SHA-256 của một mảnh, tính ở isolate riêng để không làm đơ giao diện.
///
/// Hàm cấp cao nhất: closure gửi sang isolate chỉ mang theo [bytes], không kéo
/// theo đối tượng mạng / tệp đang mở của nơi gọi (các đối tượng đó không gửi
/// qua isolate được).
Future<String> _sha256InBackground(Uint8List bytes) =>
    Isolate.run(() => sha256.convert(bytes).toString());

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
    thumbnailUrl: nullableStringField(map, const [
      'thumbnail_url',
      'thumbnailUrl',
    ]),
    width: positiveIntField(map, const ['width']),
    height: positiveIntField(map, const ['height']),
    durationMs: positiveIntField(map, const ['duration_ms', 'durationMs']),
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
