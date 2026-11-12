import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/rich_message_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/rich_message.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/rich_message_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/voice_playback_link.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/voice_transcript_view.dart';

const _segments = [
  FileTranscriptSegment(startMs: 500, endMs: 2000, text: 'Xin chào'),
  FileTranscriptSegment(startMs: 3000, endMs: 5000, text: 'mọi người'),
  FileTranscriptSegment(startMs: 5000, endMs: 8000, text: 'hôm nay họp'),
];

void main() {
  group('chép lời đồng bộ: đoạn đang nghe', () {
    test('danh sách rỗng hoặc vị trí âm', () {
      expect(activeTranscriptSegmentIndex(const [], 1000), -1);
      expect(activeTranscriptSegmentIndex(_segments, -1), -1);
    });

    test('trước đoạn đầu chưa tô gì', () {
      expect(activeTranscriptSegmentIndex(_segments, 0), -1);
      expect(activeTranscriptSegmentIndex(_segments, 499), -1);
    });

    test('đúng mép đầu đoạn thì chọn đoạn đó', () {
      expect(activeTranscriptSegmentIndex(_segments, 500), 0);
      expect(activeTranscriptSegmentIndex(_segments, 3000), 1);
      expect(activeTranscriptSegmentIndex(_segments, 5000), 2);
    });

    test('khoảng lặng giữ đoạn trước', () {
      expect(activeTranscriptSegmentIndex(_segments, 2500), 0);
    });

    test('sau khi đoạn cuối hết thì thôi tô', () {
      expect(activeTranscriptSegmentIndex(_segments, 7999), 2);
      expect(activeTranscriptSegmentIndex(_segments, 8000), -1);
    });

    test('danh sách chưa sắp xếp, đoạn có giờ hỏng', () {
      final shuffled = [
        _segments[2],
        const FileTranscriptSegment(startMs: -1, endMs: -1, text: 'hỏng'),
        _segments[0],
        _segments[1],
      ];
      expect(activeTranscriptSegmentIndex(shuffled, 3500), 3);
      expect(activeTranscriptSegmentIndex(shuffled, 6000), 0);
      // Thiếu giờ kết thúc: lấy giờ bắt đầu làm mốc hết.
      expect(
        activeTranscriptSegmentIndex(const [
          FileTranscriptSegment(startMs: 0, endMs: 0, text: 'a'),
          FileTranscriptSegment(startMs: 1000, endMs: 0, text: 'b'),
        ], 500),
        0,
      );
    });

    test('định dạng giờ', () {
      expect(formatTranscriptTime(0), '0:00');
      expect(formatTranscriptTime(65400), '1:05');
      expect(formatTranscriptTime(-5), '0:00');
    });
  });

  group('VoicePlaybackLink', () {
    test('chỉ báo khi vị trí đổi; gỡ đúng trình phát đang gắn', () async {
      final link = VoicePlaybackLink();
      var notified = 0;
      link.addListener(() => notified += 1);
      link
        ..reportPosition(1000)
        ..reportPosition(1000);
      expect(notified, 1);

      final seeks = <int>[];
      Future<void> first(int ms) async => seeks.add(ms);
      Future<void> second(int ms) async => seeks.add(ms + 1);
      link
        ..attach(first)
        ..attach(second)
        ..detach(first);
      expect(link.canSeek, isTrue);
      await link.seekAndPlay(-20);
      expect(seeks, [1]);

      link.detach(second);
      expect(link.canSeek, isFalse);
      expect(link.positionMs, 0);
      await link.seekAndPlay(500);
      expect(seeks, [1]);
      link.dispose();
    });
  });

  testWidgets('tô đoạn đang nghe và chạm đoạn để tua', (tester) async {
    final link = VoicePlaybackLink();
    final seeks = <int>[];
    link.attach((ms) async => seeks.add(ms));
    addTearDown(link.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeServerDiscoveryProvider.overrideWithValue(_server()),
          loadFileTranscriptUseCaseProvider.overrideWithValue(
            LoadFileTranscriptUseCase(_Transcripts()),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VoiceTranscriptView(
              attachment: _attachment(),
              playbackLink: link,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Xem lời'));
    await tester.pumpAndSettle();
    expect(find.text('Xin chào'), findsOneWidget);
    expect(find.text('0:03'), findsOneWidget);
    expect(_weight(tester, 'mọi người'), isNot(FontWeight.w600));

    link.reportPosition(3500);
    await tester.pumpAndSettle();
    expect(_weight(tester, 'mọi người'), FontWeight.w600);
    expect(_weight(tester, 'Xin chào'), isNot(FontWeight.w600));

    // Hết bài (vị trí về 0): thôi tô.
    link.reportPosition(0);
    await tester.pumpAndSettle();
    expect(_weight(tester, 'mọi người'), isNot(FontWeight.w600));

    await tester.tap(find.text('hôm nay họp'));
    await tester.pump();
    expect(seeks, [5000]);
  });

  testWidgets('không có trình phát thì chỉ hiện lời, không bấm được', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeServerDiscoveryProvider.overrideWithValue(_server()),
          loadFileTranscriptUseCaseProvider.overrideWithValue(
            LoadFileTranscriptUseCase(_Transcripts()),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: VoiceTranscriptView(attachment: _attachment())),
        ),
      ),
    );
    await tester.tap(find.text('Xem lời'));
    await tester.pumpAndSettle();
    expect(find.text('hôm nay họp'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('hôm nay họp'),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });
}

FontWeight? _weight(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.fontWeight;

MessageAttachment _attachment() => MessageAttachment(
  id: 'att-1',
  workspaceId: 'ws',
  messageId: 'msg-1',
  fileId: 'file-1',
  file: UploadedMessageFile(
    id: 'file-1',
    name: 'voice.m4a',
    mimeType: 'audio/mp4',
    byteSize: 1024,
    downloadPath: '/api/v1/workspaces/ws/files/file-1/download',
    createdAt: DateTime.utc(2026, 11, 11),
  ),
  createdAt: DateTime.utc(2026, 11, 11),
);

SelfHostedServerDiscovery _server() => SelfHostedServerDiscovery(
  instanceId: '11111111-1111-4111-8111-111111111111',
  discoveryVersion: '1',
  domain: 'chat.company.example',
  name: 'Máy chủ thử',
  apiBaseUri: Uri.parse('https://chat.company.example'),
  wsBaseUri: Uri.parse('wss://chat.company.example/ws'),
  registrationMode: 'closed',
  appVersion: '1.0.0',
  apiContractVersion: 1,
  serverVersion: '1.0.0',
  minimumSupportedMobileVersion: '1.0.0',
  capabilities: const SelfHostedCapabilities(transcription: true),
  zoneKind: 'dedicated',
);

/// Máy chủ giả: lời đã chép xong, chỉ có đoạn (không có chữ gộp).
final class _Transcripts implements RichMessageRepository {
  @override
  Future<Result<FileTranscript>> getFileTranscript({
    required String workspaceId,
    required String fileId,
  }) async => Success(
    FileTranscript(
      fileId: fileId,
      status: FileTranscriptStatus.ready,
      segments: _segments,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
