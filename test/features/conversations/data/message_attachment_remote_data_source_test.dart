import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/data/datasources/message_attachment_remote_data_source.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';

void main() {
  test('downloads attachment bytes through authenticated transport', () async {
    final api = _FakeApiTransport([1, 2, 3, 4]);
    final remote = MessageAttachmentRemoteDataSource(api);

    final bytes = await remote.downloadFileBytes(
      downloadPath: '/api/v1/workspaces/workspace-1/files/file-1/download',
      mimeType: 'image/jpeg',
    );

    expect(bytes, [1, 2, 3, 4]);
    expect(api.path, '/api/v1/workspaces/workspace-1/files/file-1/download');
    expect(api.options?.responseType, ResponseType.bytes);
    expect(api.options?.headers?['Accept'], 'image/jpeg');
  });

  test('lists all image attachments for a conversation', () async {
    final api = _FakeApiTransport({
      'success': true,
      'data': {
        'attachments': [
          {
            'workspace_id': 'workspace-1',
            'message_id': 'message-1',
            'file_id': 'file-1',
            'created_at': '2026-07-22T08:00:00Z',
            'file': {
              'id': 'file-1',
              'original_name': 'anh.png',
              'mime_type': 'image/png',
              'byte_size': 1024,
              'created_at': '2026-07-22T08:00:00Z',
            },
          },
        ],
      },
    });
    final remote = MessageAttachmentRemoteDataSource(api);

    final attachments = await remote.listChannelMedia(
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
    );

    expect(attachments, hasLength(1));
    expect(attachments.single.isImage, isTrue);
    expect(api.path, '/api/v1/workspaces/workspace-1/channels/channel-1/media');
    expect(api.queryParameters?['limit'], 500);
  });

  group('tải lên theo từng phần', () {
    const chunk = MessageAttachmentRemoteDataSource.uploadChunkSize;
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('webtui-upload-test');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<PickedMessageAttachment> makeFile(int size) async {
      final file = File('${dir.path}/video.mp4');
      await file.writeAsBytes(Uint8List(size));
      return PickedMessageAttachment(
        path: file.path,
        fileName: 'video.mp4',
        mimeType: 'video/mp4',
        byteSize: size,
        kind: MessageAttachmentKind.video,
      );
    }

    test('gửi đủ mảnh, mảnh cuối đúng dung lượng, tối đa 3 yêu cầu song song, '
        'tiến độ tăng dần tới 1', () async {
      final size = chunk * 6 + 123; // 7 mảnh
      final attachment = await makeFile(size);
      // Giữ các mảnh tới khi đủ 3 mảnh cùng chạy: máy CI chậm tính mã kiểm tra
      // mảnh lâu hơn thời gian gửi giả, nên chỉ chờ cố định thì đo hụt song song.
      final api = _ResumableApi(
        totalChunks: 7,
        totalSize: size,
        holdUntilConcurrent: 3,
      );
      final remote = MessageAttachmentRemoteDataSource(api, wait: (_) async {});
      final progress = <double>[];

      await remote.uploadFile(
        workspaceId: 'w',
        attachment: attachment,
        onProgress: progress.add,
      );

      expect(api.putLengths.keys.toList()..sort(), [0, 1, 2, 3, 4, 5, 6]);
      expect(api.putLengths[6], 123);
      expect(api.putLengths[0], chunk);
      expect(api.maxConcurrent, 3);
      expect(api.completed, isTrue);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
      expect(progress.last, 1);
      expect(progress.every((v) => v <= 1), isTrue);
    });

    test('tính mã kiểm tra mảnh ở isolate riêng dù bộ gửi giữ đối tượng không '
        'gửi qua isolate được', () async {
      // Dio thật giữ socket / cổng native: closure gửi sang isolate không được
      // kéo theo bộ gửi, nếu không sẽ lỗi "object is unsendable".
      final size = chunk * 2 + 7; // ≥ 8 MB: đi đường tải từng phần
      final attachment = await makeFile(size);
      final api = _UnsendableResumableApi(totalChunks: 3, totalSize: size);
      addTearDown(api.port.close);
      final remote = MessageAttachmentRemoteDataSource(api, wait: (_) async {});

      await remote.uploadFile(
        workspaceId: 'w',
        attachment: attachment,
        onProgress: (_) => api.port.sendPort,
      );

      expect(api.putLengths.keys.toList()..sort(), [0, 1, 2]);
      expect(api.completed, isTrue);
    });

    test('không gửi lại mảnh đã có trong phiên', () async {
      final size = chunk * 3 + 10;
      final attachment = await makeFile(size);
      final api = _ResumableApi(
        totalChunks: 4,
        totalSize: size,
        uploadedParts: const [0, 2],
      );
      final remote = MessageAttachmentRemoteDataSource(api, wait: (_) async {});

      await remote.uploadFile(workspaceId: 'w', attachment: attachment);

      expect(api.putLengths.keys.toList()..sort(), [1, 3]);
    });

    test('mảnh lỗi tạm thời được thử lại', () async {
      final size = chunk * 2;
      final attachment = await makeFile(size);
      final api = _ResumableApi(totalChunks: 2, totalSize: size)
        ..failures = {
          1: [503, 429],
        };
      final waits = <Duration>[];
      final remote = MessageAttachmentRemoteDataSource(
        api,
        wait: (d) async => waits.add(d),
      );

      await remote.uploadFile(workspaceId: 'w', attachment: attachment);

      expect(api.putLengths.keys.toSet(), {0, 1});
      expect(api.putCalls[1], 3);
      expect(waits, hasLength(2));
      expect(waits[1], greaterThan(waits[0]));
    });

    test('lỗi hẳn thì ném lỗi và dừng lấy mảnh mới', () async {
      final size = chunk * 8;
      final attachment = await makeFile(size);
      final api = _ResumableApi(totalChunks: 8, totalSize: size)
        ..failures = {
          0: [400],
        };
      final remote = MessageAttachmentRemoteDataSource(api, wait: (_) async {});

      await expectLater(
        remote.uploadFile(workspaceId: 'w', attachment: attachment),
        throwsA(isA<DioException>()),
      );
      expect(api.putCalls[0], 1);
      expect(api.completed, isFalse);
      expect(api.putCalls.length, lessThan(8));
    });

    test('lỗi tạm thời quá số lần thử thì ném lỗi', () async {
      final size = chunk * 2;
      final attachment = await makeFile(size);
      final api = _ResumableApi(totalChunks: 2, totalSize: size)
        ..failures = {
          0: [500, 500, 500, 500],
        };
      final remote = MessageAttachmentRemoteDataSource(api, wait: (_) async {});

      await expectLater(
        remote.uploadFile(workspaceId: 'w', attachment: attachment),
        throwsA(isA<DioException>()),
      );
      expect(api.putCalls[0], 3);
    });
  });
}

final class _FakeApiTransport implements ApiTransport {
  _FakeApiTransport(this.payload);

  final Object payload;
  String? path;
  Options? options;
  Map<String, dynamic>? queryParameters;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    this.path = path;
    this.options = options;
    this.queryParameters = queryParameters;
    return Response<T>(
      data: payload as T,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    throw UnimplementedError();
  }
}

final class _UnsendableResumableApi extends _ResumableApi {
  _UnsendableResumableApi({
    required super.totalChunks,
    required super.totalSize,
  });

  /// `ReceivePort` không gửi qua isolate được (giống socket của Dio thật).
  final ReceivePort port = ReceivePort();
}

final class _ResumableApi extends _FakeApiTransport {
  _ResumableApi({
    required this.totalChunks,
    required this.totalSize,
    this.uploadedParts = const [],
    this.holdUntilConcurrent,
  }) : super(const <String, Object?>{});

  final int totalChunks;
  final int totalSize;
  final List<int> uploadedParts;

  /// Có giá trị thì mỗi lần gửi mảnh chờ tới khi đủ ngần ấy mảnh cùng chạy
  /// (tối đa 5 giây, để bộ gửi tuần tự làm test đỏ chứ không treo).
  final int? holdUntilConcurrent;
  final Completer<void> _concurrencyGate = Completer<void>();
  final Map<int, int> putLengths = {};
  final Map<int, int> putCalls = {};
  Map<int, List<int>> failures = {};
  int _running = 0;
  int maxConcurrent = 0;
  bool completed = false;

  Map<String, Object?> get _upload => {
    'id': 'up-1',
    'chunk_size': MessageAttachmentRemoteDataSource.uploadChunkSize,
    'total_chunks': totalChunks,
    'received_bytes':
        uploadedParts.length *
        MessageAttachmentRemoteDataSource.uploadChunkSize,
    'status': 'uploading',
    'uploaded_parts': [
      for (final part in uploadedParts) {'part_number': part},
    ],
  };

  Response<T> _ok<T>(String path, Object data) => Response<T>(
    data: data as T,
    requestOptions: RequestOptions(path: path),
  );

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path.endsWith('/complete')) {
      completed = true;
      return _ok(path, {
        'data': {
          'file': {'id': 'f1', 'original_name': 'video.mp4'},
        },
      });
    }
    return _ok(path, {
      'data': {'upload': _upload},
    });
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final part = int.parse(path.split('/').last);
    putCalls[part] = (putCalls[part] ?? 0) + 1;
    _running++;
    if (_running > maxConcurrent) maxConcurrent = _running;
    try {
      final hold = holdUntilConcurrent;
      if (hold != null && !_concurrencyGate.isCompleted) {
        if (_running >= hold) {
          _concurrencyGate.complete();
        } else {
          await _concurrencyGate.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {},
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final queue = failures[part];
      if (queue != null && queue.isNotEmpty) {
        final status = queue.removeAt(0);
        throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.badResponse,
          response: Response<Object>(
            requestOptions: RequestOptions(path: path),
            statusCode: status,
          ),
        );
      }
      final bytes = data! as Uint8List;
      expect(options?.headers?['Content-Length'], bytes.length);
      expect(options?.headers?['X-Chunk-SHA256'], isA<String>());
      putLengths[part] = bytes.length;
      return _ok(path, const <String, Object?>{});
    } finally {
      _running--;
    }
  }
}
