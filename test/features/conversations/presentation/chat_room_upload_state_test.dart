import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/chat_room_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_media_widgets.dart';

const _scope = ChatRoomScope(
  workspaceId: 'ws',
  channelId: 'ch',
  title: 'Phòng',
);

const _video = PickedMessageAttachment(
  path: '/device/video.mp4',
  fileName: 'video.mp4',
  mimeType: 'video/mp4',
  byteSize: 9000000,
  kind: MessageAttachmentKind.video,
  compressVideo: true,
);

ChatRoomState _stateWith(MessageAttachmentUploadStatus status) {
  return const ChatRoomState(scope: _scope).copyWith(
    pendingAttachments: [
      MessageAttachmentUploadItem(
        clientAttachmentId: 'att-1',
        status: status,
        picked: _video,
      ),
    ],
  );
}

void main() {
  group('ChatRoomState.canSend', () {
    test('cho gửi ngay khi tệp còn đang tải', () {
      final state = _stateWith(MessageAttachmentUploadStatus.uploading);
      expect(state.hasUploadingAttachments, isTrue);
      expect(state.canSend, isTrue);
    });

    test('cho gửi khi tệp chờ tải hoặc đã tải xong', () {
      expect(_stateWith(MessageAttachmentUploadStatus.queued).canSend, isTrue);
      expect(
        _stateWith(MessageAttachmentUploadStatus.uploaded).canSend,
        isTrue,
      );
    });

    test('tệp lỗi một mình hoặc khung trống thì không gửi được', () {
      expect(_stateWith(MessageAttachmentUploadStatus.failed).canSend, isFalse);
      expect(const ChatRoomState(scope: _scope).canSend, isFalse);
    });

    test('có chữ thì gửi được', () {
      expect(
        const ChatRoomState(scope: _scope).copyWith(draft: 'xin chào').canSend,
        isTrue,
      );
    });
  });

  test('ô tệp giữ cờ đang nén qua copyWith', () {
    const item = MessageAttachmentUploadItem(
      clientAttachmentId: 'a',
      status: MessageAttachmentUploadStatus.uploading,
      compressing: true,
    );
    expect(item.copyWith(progress: 0.2).compressing, isTrue);
    expect(item.copyWith(compressing: false).compressing, isFalse);
    expect(
      const MessageAttachmentUploadItem(
        clientAttachmentId: 'b',
        status: MessageAttachmentUploadStatus.queued,
      ).compressing,
      isFalse,
    );
  });

  test('tin tạm đọc được tiến độ tải từ metadata', () {
    final uploading = ChatMessage(
      id: 'local-c1',
      workspaceId: 'ws',
      channelId: 'ch',
      kind: 'file',
      body: 'video',
      createdAt: DateTime.utc(2026, 11, 10),
      metadata: const {
        'client_message_id': 'c1',
        'delivery_status': 'uploading',
        'upload_progress': 0.45,
        'upload_stage': 'compressing',
      },
    );
    expect(uploading.uploadProgress, 0.45);
    expect(uploading.uploadStage, 'compressing');
    final failed = uploading.copyWith(
      metadata: {...uploading.metadata, 'delivery_status': 'failed'},
    );
    expect(failed.uploadProgress, isNull);
  });

  group('MessageLocalVideoPreview', () {
    Future<void> pump(WidgetTester tester, {double? progress, String? stage}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageLocalVideoPreview(
              path: '/khong/co/video.mp4',
              fileName: 'video.mp4',
              progress: progress,
              stage: stage,
            ),
          ),
        ),
      );
    }

    testWidgets('hiện vòng tiến độ và phần trăm khi đang tải lên', (
      tester,
    ) async {
      await pump(tester, progress: 0.45, stage: 'uploading');
      expect(find.text('Đang tải lên 45%'), findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(ring.value, 0.45);
    });

    testWidgets('hiện "Đang nén…" khi đang nén', (tester) async {
      await pump(tester, progress: 0.1, stage: 'compressing');
      expect(find.text('Đang nén…'), findsOneWidget);
    });

    testWidgets('không có tiến độ thì chỉ hiện biểu tượng phát', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Đang'), findsNothing);
    });
  });
}
