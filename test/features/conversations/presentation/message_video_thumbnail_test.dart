import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/message_media_widgets.dart';

MessageAttachment _video({String? thumbnailUrl, int? durationMs = 35000}) {
  final createdAt = DateTime.utc(2026, 11, 14);
  return MessageAttachment(
    id: 'a1',
    workspaceId: 'w1',
    messageId: 'm1',
    fileId: 'f1',
    createdAt: createdAt,
    file: UploadedMessageFile(
      id: 'f1',
      name: 'clip.mp4',
      mimeType: 'video/mp4',
      byteSize: 4096,
      downloadPath: '/api/v1/workspaces/w1/files/f1/download',
      createdAt: createdAt,
      thumbnailUrl: thumbnailUrl,
      width: 1080,
      height: 1920,
      durationMs: durationMs,
    ),
  );
}

Future<void> _pump(WidgetTester tester, MessageAttachment attachment) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [activeServerDiscoveryProvider.overrideWithValue(null)],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: MessageVideoAttachmentView(
              attachment: attachment,
              apiBaseUri: Uri.parse('https://server.example'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('video có ảnh bìa hiện nút phát, thời lượng, chưa tải video', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      _video(thumbnailUrl: '/api/v1/workspaces/w1/files/f1/thumbnail'),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('video-thumbnail-play')), findsOneWidget);
    expect(find.text('0:35'), findsOneWidget);
    expect(find.bySemanticsLabel('Phát video, 0:35'), findsOneWidget);
    // Chưa bấm thì không dựng trình phát và không có vòng chờ tải video.
    expect(find.byType(VideoPlayer), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    handle.dispose();
  });

  testWidgets(
    'không có ảnh bìa thì hiện ô tối có phim, tên, thời lượng, nút phát',
    (tester) async {
      await _pump(tester, _video());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('video-thumbnail-play')), findsNothing);
      expect(find.byKey(const ValueKey('video-placeholder')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('video-placeholder-play')),
        findsOneWidget,
      );
      expect(find.text('clip.mp4'), findsOneWidget);
      expect(find.text('0:35'), findsOneWidget);
    },
  );

  testWidgets(
    'bấm nút phát trên ảnh bìa bắt đầu tải (máy chủ không hợp lệ thì báo lỗi)',
    (tester) async {
      await _pump(
        tester,
        _video(thumbnailUrl: '/api/v1/workspaces/w1/files/f1/thumbnail'),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('video-thumbnail-play')));
      await tester.pumpAndSettle();

      // Không có phiên máy chủ nên không tải được: hiện trạng thái lỗi.
      expect(find.text('Không phát được video'), findsWidgets);
      expect(find.byType(VideoPlayer), findsNothing);
    },
  );
}
