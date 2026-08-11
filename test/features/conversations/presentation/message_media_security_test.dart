import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/conversations/data/files/scoped_attachment_file_store.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/screens/chat_room_screen.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_media_widgets.dart';

void main() {
  test(
    'external presigned attachment is never eligible for instance token',
    () {
      final attachment = _attachment('https://evil.example/video.mp4?sig=ok');
      final uri = attachmentDownloadUri(
        attachment,
        Uri.parse('https://server-a.example'),
      );

      expect(uri, Uri.parse('https://evil.example/video.mp4?sig=ok'));
      expect(
        attachmentUriCanUseInstanceCredentials(
          attachmentUri: uri!,
          apiBaseUri: Uri.parse('https://server-a.example'),
          activeInstanceOrigin: Uri.parse('https://server-a.example'),
        ),
        isFalse,
      );
    },
  );

  test('stale server A media cannot receive active server B token', () {
    final uri = attachmentDownloadUri(
      _attachment('/api/v1/files/file-1'),
      Uri.parse('https://server-a.example'),
    );

    expect(
      attachmentUriCanUseInstanceCredentials(
        attachmentUri: uri!,
        apiBaseUri: Uri.parse('https://server-a.example'),
        activeInstanceOrigin: Uri.parse('https://server-b.example'),
      ),
      isFalse,
    );
  });

  test(
    'attachment URL rejects credentials, fragment, and non-http schemes',
    () {
      expect(
        attachmentDownloadUri(
          _attachment('https://user:pass@server-a.example/file'),
          Uri.parse('https://server-a.example'),
        ),
        isNull,
      );
      expect(
        attachmentDownloadUri(
          _attachment('https://server-a.example/file#secret'),
          Uri.parse('https://server-a.example'),
        ),
        isNull,
      );
      expect(
        attachmentDownloadUri(
          _attachment('data:text/plain,secret'),
          Uri.parse('https://server-a.example'),
        ),
        isNull,
      );
      expect(
        attachmentDownloadUri(
          _attachment('http://public.example/file'),
          Uri.parse('https://server-a.example'),
        ),
        isNull,
        reason: 'cleartext HTTP is allowed only for loopback development',
      );
    },
  );

  test('same attachment metadata is isolated by instance and generation', () {
    final instanceA = InstanceScope(
      instanceId: '11111111-1111-4111-8111-111111111111',
      serverOrigin: Uri.parse('https://server-a.example'),
    );
    final instanceB = InstanceScope(
      instanceId: '22222222-2222-4222-8222-222222222222',
      serverOrigin: Uri.parse('https://server-b.example'),
    );

    final pathA = scopedAttachmentRelativePath(
      instanceScope: instanceA,
      sessionGeneration: 'generation-a',
      fileId: '../same-id',
      originalName: 'báo cáo.pdf',
      purpose: 'file',
    );
    final pathB = scopedAttachmentRelativePath(
      instanceScope: instanceB,
      sessionGeneration: 'generation-b',
      fileId: '../same-id',
      originalName: 'báo cáo.pdf',
      purpose: 'file',
    );
    final nextAccountA = scopedAttachmentRelativePath(
      instanceScope: instanceA,
      sessionGeneration: 'generation-a-2',
      fileId: '../same-id',
      originalName: 'báo cáo.pdf',
      purpose: 'file',
    );

    expect(pathA, isNot(pathB));
    expect(pathA, isNot(nextAccountA));
    expect(pathA, isNot(contains('same-id')));
    expect(pathA, isNot(contains('báo cáo')));
  });

  test('oversized previews fail before any media transfer is eligible', () {
    expect(
      attachmentPreviewWithinLimit(
        maxImagePreviewBytes + 1,
        maxBytes: maxImagePreviewBytes,
      ),
      isFalse,
    );
    expect(
      attachmentPreviewWithinLimit(
        maxVoicePlaybackBytes + 1,
        maxBytes: maxVoicePlaybackBytes,
      ),
      isFalse,
    );
    expect(
      attachmentPreviewWithinLimit(
        maxVideoPlaybackBytes + 1,
        maxBytes: maxVideoPlaybackBytes,
      ),
      isFalse,
    );
  });

  test('a message renders at most twenty attachment widgets', () {
    final attachments = List<MessageAttachment>.filled(
      25,
      _attachment('/api/v1/files/file-1'),
    );

    expect(boundedMessageAttachments(attachments), hasLength(20));
    expect(maxRenderedAttachmentsPerMessage, 20);
  });

  test('a message eagerly decodes at most four image previews', () {
    final images = List<MessageAttachment>.filled(
      20,
      _attachment(
        '/api/v1/files/file-1',
        mimeType: 'image/png',
        name: 'image.png',
      ),
    );

    expect(boundedEagerImageAttachments(images), hasLength(4));
    expect(maxEagerImagePreviewsPerMessage, 4);
  });
}

MessageAttachment _attachment(
  String downloadPath, {
  String mimeType = 'video/mp4',
  String name = 'video.mp4',
}) {
  final now = DateTime.utc(2026, 8, 10);
  return MessageAttachment(
    id: 'attachment-1',
    workspaceId: 'workspace-shared',
    messageId: 'message-shared',
    fileId: 'file-1',
    file: UploadedMessageFile(
      id: 'file-1',
      name: name,
      mimeType: mimeType,
      byteSize: 42,
      downloadPath: downloadPath,
      createdAt: now,
    ),
    createdAt: now,
  );
}
