import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';

void main() {
  group('MessageAttachment.kind', () {
    test('tin nhắn thoại ghi trên web (.webm, audio/webm) là âm thanh', () {
      final attachment = _attachment(
        name: 'voice-1793111097763.webm',
        mimeType: 'audio/webm',
      );

      expect(attachment.kind, MessageAttachmentKind.audio);
      expect(attachment.isVideo, isFalse);
    });

    test('tệp thoại .webm thiếu MIME vẫn là âm thanh', () {
      final attachment = _attachment(
        name: 'voice-1793111097763.webm',
        mimeType: 'application/octet-stream',
      );

      expect(attachment.kind, MessageAttachmentKind.audio);
    });

    test('MIME âm thanh thắng đuôi tệp kiểu video', () {
      expect(
        _attachment(name: 'ghi-am.mp4', mimeType: 'audio/mp4').kind,
        MessageAttachmentKind.audio,
      );
    });

    test('video .webm thật vẫn là video', () {
      expect(
        _attachment(name: 'man-hinh.webm', mimeType: 'video/webm').kind,
        MessageAttachmentKind.video,
      );
      expect(
        _attachment(name: 'clip.webm', mimeType: '').kind,
        MessageAttachmentKind.video,
      );
    });

    test('ghi âm trên app (.m4a) và ảnh giữ nguyên loại', () {
      expect(
        _attachment(name: 'voice.m4a', mimeType: 'audio/mp4').kind,
        MessageAttachmentKind.audio,
      );
      expect(
        _attachment(name: 'anh.jpg', mimeType: 'image/jpeg').kind,
        MessageAttachmentKind.image,
      );
      expect(
        _attachment(name: 'bao-cao.pdf', mimeType: 'application/pdf').kind,
        MessageAttachmentKind.file,
      );
    });
  });
}

MessageAttachment _attachment({
  required String name,
  required String mimeType,
}) {
  final createdAt = DateTime.utc(2026, 11, 2);
  return MessageAttachment(
    id: 'att-1',
    workspaceId: 'ws-1',
    messageId: 'msg-1',
    fileId: 'file-1',
    file: UploadedMessageFile(
      id: 'file-1',
      name: name,
      mimeType: mimeType,
      byteSize: 1024,
      downloadPath: '/api/v1/workspaces/ws-1/files/file-1/download',
      createdAt: createdAt,
    ),
    createdAt: createdAt,
  );
}
