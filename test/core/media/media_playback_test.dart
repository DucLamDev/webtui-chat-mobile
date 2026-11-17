import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:webtui_chat/core/media/media_playback.dart';

import 'fake_video_player_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeVideoPlayerPlatform platform;

  setUp(() {
    platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  test('iPhone / iPad / Mac phát tệp tải về; Android vẫn phát dần', () {
    expect(preferLocalMediaPlayback(TargetPlatform.iOS), isTrue);
    expect(preferLocalMediaPlayback(TargetPlatform.macOS), isTrue);
    expect(preferLocalMediaPlayback(TargetPlatform.android), isFalse);
    expect(preferLocalMediaPlayback(TargetPlatform.linux), isFalse);
  });

  test('phát dần sẵn sàng thì trả trình phát', () async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://chat.example/api/v1/media/s?token=t'),
    );
    final ready = await initializeStreamOrNull(controller);
    expect(ready, same(controller));
    expect(ready!.value.isInitialized, isTrue);
    await ready.dispose();
  });

  test('phát dần treo quá hạn: huỷ trình phát, trả null để tải về', () async {
    platform.hangNetwork = true;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://chat.example/api/v1/media/s?token=t'),
    );
    final watch = Stopwatch()..start();
    final ready = await initializeStreamOrNull(
      controller,
      timeout: const Duration(milliseconds: 150),
    );
    expect(ready, isNull);
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(140));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(platform.disposed, isNotEmpty, reason: 'trình phát treo bị huỷ');
  });
}
