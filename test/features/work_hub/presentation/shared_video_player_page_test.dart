import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_file_logic.dart';
import 'package:webtui_chat/features/work_hub/presentation/widgets/shared_file_viewers.dart';

import '../../../core/media/fake_video_player_platform.dart';

void main() {
  late Directory dir;
  late FakeVideoPlayerPlatform platform;
  late int linkRequests;
  late List<String> downloads;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('shared-video-page');
    platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    linkRequests = 0;
    downloads = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final file = SharedFile(
    id: 'v1',
    name: 'clip.mp4',
    mimeType: 'video/mp4',
    byteSize: 16,
    createdAt: DateTime.utc(2026, 11, 17),
  );

  SharedFileMediaResolver resolver() => SharedFileMediaResolver(
    links: SharedFileStreamLinkCache(
      fetch: (id) async {
        linkRequests++;
        return SharedFileStreamLink(
          url: '/api/v1/media/s?token=t',
          expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        );
      },
    ),
    cache: SharedFileCache(directory: () async => dir),
    absolute: (url) => Uri.parse('https://chat.example$url'),
    download: (file, target) async {
      downloads.add(file.id);
      await target.writeAsBytes(List.filled(file.byteSize, 1));
    },
  );

  /// Dựng trang và chờ thật (tải tệp là I/O thật) tới khi trình phát xong.
  Future<void> open(
    WidgetTester tester, {
    required bool preferLocal,
    Duration streamStartTimeout = const Duration(seconds: 12),
  }) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: SharedVideoPlayerPage(
            file: file,
            resolver: resolver(),
            preferLocalPlayback: preferLocal,
            streamStartTimeout: streamStartTimeout,
          ),
        ),
      );
      for (var i = 0; i < 50 && platform.played.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  }

  testWidgets('iPhone: tải video về rồi phát tệp, không xin link phát dần', (
    tester,
  ) async {
    await open(tester, preferLocal: true);

    expect(linkRequests, 0);
    expect(downloads, ['v1']);
    expect(platform.createdTypes, [DataSourceType.file]);
    expect(platform.played, isNotEmpty, reason: 'bắt đầu phát ngay');
    expect(find.byKey(const Key('video_retry')), findsNothing);
    await close(tester);
  });

  testWidgets(
    'phát dần treo quá hạn: tự tải về rồi phát tệp, không đứng hình',
    (tester) async {
      platform.hangNetwork = true;
      await open(
        tester,
        preferLocal: false,
        streamStartTimeout: const Duration(milliseconds: 150),
      );

      expect(linkRequests, 1);
      expect(platform.createdTypes, [
        DataSourceType.network,
        DataSourceType.file,
      ]);
      expect(downloads, ['v1']);
      expect(platform.played, isNotEmpty);
      expect(find.byKey(const Key('video_retry')), findsNothing);
      await close(tester);
    },
  );

  testWidgets('Android: phát dần chạy được thì không tải cả tệp', (
    tester,
  ) async {
    await open(tester, preferLocal: false);

    expect(linkRequests, 1);
    expect(platform.createdTypes, [DataSourceType.network]);
    expect(downloads, isEmpty);
    await close(tester);
  });
}
