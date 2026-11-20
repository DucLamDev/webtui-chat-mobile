import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:webtui_chat/core/audio/playable_audio.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/conversations/application/message_attachment_memo.dart';
import 'package:webtui_chat/features/conversations/data/files/attachment_cache_evictor.dart';
import 'package:webtui_chat/features/conversations/data/files/scoped_attachment_file_store.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final server = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: Uri.parse('https://chat.example'),
  );
  final apiBaseUri = Uri.parse('https://chat.example');
  const account = 'user:u-1';
  const store = ScopedAttachmentFileStore();

  MessageAttachment attachment({
    required String messageId,
    required String fileId,
    required String name,
    required String mimeType,
    required int byteSize,
    String? thumbnailUrl,
  }) {
    final createdAt = DateTime.utc(2026, 11, 19);
    return MessageAttachment(
      id: 'att-$fileId',
      workspaceId: 'ws-1',
      messageId: messageId,
      fileId: fileId,
      file: UploadedMessageFile(
        id: fileId,
        name: name,
        mimeType: mimeType,
        byteSize: byteSize,
        downloadPath: '/api/v1/workspaces/ws-1/files/$fileId/download',
        createdAt: createdAt,
        thumbnailUrl: thumbnailUrl,
      ),
      createdAt: createdAt,
    );
  }

  String download(String fileId) =>
      'https://chat.example/api/v1/workspaces/ws-1/files/$fileId/download';
  String thumbnail(String fileId) =>
      'https://chat.example/api/v1/workspaces/ws-1/files/$fileId/thumbnail';

  /// Ghi một tệp kho giả đúng như widget media đặt khoá / tên (viết tay khoá
  /// để test bắt được khi hai bên lệch nhau).
  Future<File> cached(String purpose, String key, {String name = ''}) async {
    final file = await store.cacheFileFor(
      instanceScope: server,
      accountKey: account,
      purpose: purpose,
      key: key,
      originalName: name,
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('$purpose|$key');
    return file;
  }

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('attachment-evictor-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temp.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'xoá đúng ảnh gốc, ảnh thu nhỏ, video, ảnh bìa, tin thoại + WAV, tệp của tin; tin khác giữ nguyên',
    () async {
      final photo = attachment(
        messageId: 'msg-1',
        fileId: 'f-anh',
        name: 'anh',
        mimeType: 'image/jpeg',
        byteSize: 2048,
        thumbnailUrl: '/api/v1/workspaces/ws-1/files/f-anh/thumbnail',
      );
      final video = attachment(
        messageId: 'msg-1',
        fileId: 'f-video',
        name: 'clip',
        mimeType: 'video/mp4',
        byteSize: 5000,
        thumbnailUrl: '/api/v1/workspaces/ws-1/files/f-video/thumbnail',
      );
      final voice = attachment(
        messageId: 'msg-1',
        fileId: 'f-voice',
        name: 'voice.webm',
        mimeType: 'audio/webm',
        byteSize: 300,
      );
      final document = attachment(
        messageId: 'msg-1',
        fileId: 'f-doc',
        name: 'bao-cao.pdf',
        mimeType: 'application/pdf',
        byteSize: 900,
      );
      final otherPhoto = attachment(
        messageId: 'msg-2',
        fileId: 'f-khac',
        name: 'khac.jpg',
        mimeType: 'image/jpeg',
        byteSize: 1024,
        thumbnailUrl: '/api/v1/workspaces/ws-1/files/f-khac/thumbnail',
      );

      final removed = [
        // Ảnh: gốc + thu nhỏ kèm cỡ tệp; lưu vào thư viện (tên có đuôi).
        await cached('image', '${download('f-anh')}|2048'),
        await cached('image', '${thumbnail('f-anh')}|2048'),
        await cached('file', download('f-anh'), name: 'anh.jpg'),
        // Video: tệp kho tên theo galleryFileName + ảnh bìa (không kèm cỡ).
        await cached('video', download('f-video'), name: 'clip.mp4'),
        await cached('image', thumbnail('f-video')),
        // Tin thoại + WAV giải mã cho iPhone.
        await cached('voice', download('f-voice'), name: 'voice.webm'),
        // Tệp mở bằng app khác.
        await cached('file', download('f-doc'), name: 'bao-cao.pdf'),
      ];
      final playableDirectory = await store.cacheDirectoryFor(
        instanceScope: server,
        accountKey: account,
        purpose: 'playable-audio',
      );
      await playableDirectory.create(recursive: true);
      final wav = File(
        path.join(
          playableDirectory.path,
          playableAudioCacheFileName('chat-f-voice'),
        ),
      );
      await wav.writeAsString('wav');
      removed.add(wav);

      final kept = [
        await cached('image', '${download('f-khac')}|1024'),
        await cached('image', '${thumbnail('f-khac')}|1024'),
        await cached('avatar', 'https://chat.example/avatar/u-2.png|false'),
      ];
      final otherWav = File(
        path.join(
          playableDirectory.path,
          playableAudioCacheFileName('chat-f-khac'),
        ),
      );
      await otherWav.writeAsString('wav');
      kept.add(otherWav);

      final deleted = await const AttachmentCacheEvictor().evict(
        instanceScope: server,
        accountKey: account,
        apiBaseUri: apiBaseUri,
        attachments: [photo, video, voice, document],
      );

      expect(deleted, removed.length);
      for (final file in removed) {
        expect(await file.exists(), isFalse, reason: file.path);
      }
      for (final file in kept) {
        expect(await file.exists(), isTrue, reason: file.path);
      }

      // Tin còn lại xoá được riêng sau đó.
      await const AttachmentCacheEvictor().evict(
        instanceScope: server,
        accountKey: account,
        apiBaseUri: apiBaseUri,
        attachments: [otherPhoto],
      );
      expect(await kept[0].exists(), isFalse);
      expect(await kept[1].exists(), isFalse);
      expect(await kept[2].exists(), isTrue);
    },
  );

  test('tài khoản khác cùng máy chủ không bị xoá tệp', () async {
    final photo = attachment(
      messageId: 'msg-1',
      fileId: 'f-anh',
      name: 'anh.jpg',
      mimeType: 'image/jpeg',
      byteSize: 2048,
    );
    final otherAccount = await store.cacheFileFor(
      instanceScope: server,
      accountKey: 'user:u-2',
      purpose: 'image',
      key: '${download('f-anh')}|2048',
    );
    await otherAccount.parent.create(recursive: true);
    await otherAccount.writeAsString('jpg');
    final mine = await cached('image', '${download('f-anh')}|2048');

    await const AttachmentCacheEvictor().evict(
      instanceScope: server,
      accountKey: account,
      apiBaseUri: apiBaseUri,
      attachments: [photo],
    );

    expect(await mine.exists(), isFalse);
    expect(await otherAccount.exists(), isTrue);
  });

  test('bộ nhớ tệp đính kèm bỏ được mục của một tin', () {
    final memo = MessageAttachmentMemo();
    final key = MessageAttachmentMemo.keyFor(
      userId: 'u-1',
      workspaceId: 'ws-1',
      channelId: 'ch-1',
      messageId: 'msg-1',
    );
    final photo = attachment(
      messageId: 'msg-1',
      fileId: 'f-anh',
      name: 'anh.jpg',
      mimeType: 'image/jpeg',
      byteSize: 2048,
    );
    memo.write(key, [photo]);

    expect(memo.remove(key)!.single.fileId, 'f-anh');
    expect(memo.read(key), isNull);
    expect(memo.remove(key), isNull);
    expect(memo.remove(null), isNull);
  });
}
