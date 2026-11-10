import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/platform/video_compressor.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_attachment_use_cases.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_media_uploader.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/message_attachment_repository.dart';

const _big = 10 * 1024 * 1024;

void main() {
  late Directory dir;
  late _FakeRepository repo;
  late _FakeCompressor compressor;
  late DefaultMessageMediaUploader uploader;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('webtui-uploader-test');
    repo = _FakeRepository();
    compressor = _FakeCompressor();
    uploader = DefaultMessageMediaUploader(
      uploadAttachment: UploadMessageAttachmentUseCase(repo),
      compressor: compressor,
      compressedPathFor: (id) async => '${dir.path}/$id.mp4',
    );
  });
  tearDown(() async {
    uploader.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  PickedMessageAttachment video({
    int size = _big,
    bool compress = true,
    String path = '',
    MessageAttachmentKind kind = MessageAttachmentKind.video,
  }) {
    final file = File(path.isEmpty ? '${dir.path}/goc.mov' : path);
    if (path.isEmpty) file.writeAsBytesSync([1, 2, 3]);
    return PickedMessageAttachment(
      path: file.path,
      fileName: 'goc.mov',
      mimeType: 'video/quicktime',
      byteSize: size,
      kind: kind,
      compressVideo: compress,
    );
  }

  Future<Result<UploadedMessageFile>> run(
    PickedMessageAttachment a, {
    void Function(MessageMediaUploadProgress)? onProgress,
  }) => uploader.upload(
    workspaceId: 'w',
    clientAttachmentId: 'c1',
    attachment: a,
    onProgress: onProgress,
  );

  test(
    'hai lần gọi cùng id chỉ tải một lần, gọi sau khi xong trả kết quả nhớ',
    () async {
      final a = video(compress: false);
      final first = run(a);
      final second = run(a);
      final r1 = await first;
      final r2 = await second;
      expect(r1.isSuccess, isTrue);
      expect(r2.isSuccess, isTrue);
      expect(repo.uploads, hasLength(1));

      final stages = <MessageMediaUploadStage>[];
      final r3 = await run(a, onProgress: (p) => stages.add(p.stage));
      expect(r3.valueOrNull?.id, r1.valueOrNull?.id);
      expect(repo.uploads, hasLength(1));
      expect(stages.last, MessageMediaUploadStage.done);
    },
  );

  test('video lớn được nén và tải bản nén, tiến độ tăng dần', () async {
    final events = <MessageMediaUploadProgress>[];
    final result = await run(video(), onProgress: events.add);

    expect(result.isSuccess, isTrue);
    expect(compressor.calls, 1);
    final sent = repo.uploads.single;
    expect(sent.path, '${dir.path}/c1.mp4');
    expect(sent.fileName, 'goc.mp4');
    expect(sent.mimeType, 'video/mp4');
    expect(sent.byteSize, _big ~/ 4);
    expect(sent.compressVideo, isFalse);
    expect(File(sent.path).existsSync(), isFalse); // đã xoá sau khi tải

    for (var i = 1; i < events.length; i++) {
      expect(events[i].progress, greaterThanOrEqualTo(events[i - 1].progress));
    }
    expect(events.first.stage, MessageMediaUploadStage.compressing);
    expect(
      events.any((e) => e.stage == MessageMediaUploadStage.uploading),
      isTrue,
    );
    expect(events.last.stage, MessageMediaUploadStage.done);
    expect(events.last.progress, 1);
    expect(
      events
          .where((e) => e.stage == MessageMediaUploadStage.compressing)
          .every((e) => e.progress <= 0.3),
      isTrue,
    );
    expect(uploader.progressOf('c1')?.stage, MessageMediaUploadStage.done);
  });

  test('nén trả null thì tải bản gốc', () async {
    compressor.mode = _Mode.nullResult;
    final a = video();
    await run(a);
    expect(repo.uploads.single.path, a.path);
  });

  test('nén ném lỗi thì tải bản gốc', () async {
    compressor.mode = _Mode.throws;
    final a = video();
    await run(a);
    expect(repo.uploads.single.path, a.path);
  });

  test('bản nén không đủ nhỏ thì tải bản gốc và xoá bản nén', () async {
    compressor.mode = _Mode.barelySmaller;
    final a = video();
    await run(a);
    expect(repo.uploads.single.path, a.path);
    expect(File('${dir.path}/c1.mp4').existsSync(), isFalse);
  });

  test(
    'dưới 4 MB, compressVideo=false hoặc không phải video: không nén',
    () async {
      await uploader.upload(
        workspaceId: 'w',
        clientAttachmentId: 'a',
        attachment: video(size: 3 * 1024 * 1024),
      );
      await uploader.upload(
        workspaceId: 'w',
        clientAttachmentId: 'b',
        attachment: video(compress: false),
      );
      await uploader.upload(
        workspaceId: 'w',
        clientAttachmentId: 'c',
        attachment: video(kind: MessageAttachmentKind.file),
      );
      expect(compressor.calls, 0);
      expect(repo.uploads, hasLength(3));
    },
  );

  test('tải lỗi rồi gọi lại thì chạy lại và dùng lại tệp nén', () async {
    repo.failNext = true;
    final a = video();
    final first = await run(a);
    expect(first.isFailure, isTrue);
    expect(uploader.progressOf('c1')?.stage, MessageMediaUploadStage.failed);
    expect(File('${dir.path}/c1.mp4').existsSync(), isTrue);

    final second = await run(a);
    expect(second.isSuccess, isTrue);
    expect(compressor.calls, 1);
    expect(repo.uploads, hasLength(2));
    expect(repo.uploads.last.path, '${dir.path}/c1.mp4');
  });

  test('tệp mất thì báo ATTACHMENT_FILE_MISSING', () async {
    final result = await run(video(path: '${dir.path}/khong-co.mov'));
    final failure = result.failureOrNull;
    expect(failure?.kind, FailureKind.validation);
    expect(failure?.code, 'ATTACHMENT_FILE_MISSING');
    expect(repo.uploads, isEmpty);
  });
}

enum _Mode { ok, nullResult, throws, barelySmaller }

final class _FakeCompressor implements VideoCompressor {
  int calls = 0;
  _Mode mode = _Mode.ok;

  @override
  Future<CompressedVideo?> compress({
    required String inputPath,
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    calls++;
    if (mode == _Mode.throws) throw StateError('nén lỗi');
    if (mode == _Mode.nullResult) return null;
    onProgress?.call(0.5);
    await File(outputPath).writeAsBytes([9, 9, 9]);
    onProgress?.call(1);
    return CompressedVideo(
      path: outputPath,
      byteSize: mode == _Mode.barelySmaller ? (_big * 0.9).toInt() : _big ~/ 4,
    );
  }

  @override
  Future<void> cancel(String outputPath) async {}
}

final class _FakeRepository implements MessageAttachmentRepository {
  final List<PickedMessageAttachment> uploads = [];
  bool failNext = false;

  @override
  Future<Result<UploadedMessageFile>> uploadFile({
    required String workspaceId,
    required PickedMessageAttachment attachment,
    void Function(double progress)? onProgress,
  }) async {
    uploads.add(attachment);
    onProgress?.call(0.5);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (failNext) {
      failNext = false;
      return const FailureResult(
        Failure(kind: FailureKind.network, message: 'mất mạng'),
      );
    }
    onProgress?.call(1);
    return Success(
      UploadedMessageFile(
        id: 'file-${uploads.length}',
        name: attachment.fileName,
        mimeType: attachment.mimeType,
        byteSize: attachment.byteSize,
        downloadPath: '/x',
        createdAt: DateTime(2026),
      ),
    );
  }

  @override
  Future<Result<MessageAttachment>> attachFile({
    required String workspaceId,
    required String channelId,
    required String messageId,
    required String fileId,
    int sortOrder = 0,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<MessageAttachment>>> listAttachments({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) => throw UnimplementedError();

  @override
  Future<Result<List<MessageAttachment>>> listChannelMedia({
    required String workspaceId,
    required String channelId,
    int limit = 500,
  }) => throw UnimplementedError();

  @override
  Future<Result<Uint8List>> downloadFileBytes({
    required String downloadPath,
    String? mimeType,
  }) => throw UnimplementedError();
}
