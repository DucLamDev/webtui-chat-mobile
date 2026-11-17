import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Trình phát giả cho test: tệp cục bộ sẵn sàng ngay; nguồn mạng (phát dần)
/// sẵn sàng ngay, hoặc treo mãi khi [hangNetwork] (giống AVPlayer đứng ở ảnh
/// bìa trên iPhone).
final class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final created = <DataSource>[];
  final disposed = <int>[];
  final played = <int>[];
  bool hangNetwork = false;

  final _events = <int, StreamController<VideoEvent>>{};
  int _nextId = 1;

  List<DataSourceType> get createdTypes => [
    for (final source in created) source.sourceType,
  ];

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) => createWithOptions(
    VideoCreationOptions(
      dataSource: dataSource,
      viewType: VideoViewType.textureView,
    ),
  );

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    created.add(options.dataSource);
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    final hang =
        hangNetwork && options.dataSource.sourceType == DataSourceType.network;
    if (!hang) {
      events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 5),
          size: const Size(320, 180),
        ),
      );
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    // Không chờ close(): luồng đã bị huỷ nghe thì sự kiện kết thúc không bao
    // giờ được giao, chờ sẽ treo test.
    unawaited(_events.remove(playerId)?.close());
  }

  @override
  Future<void> play(int playerId) async => played.add(playerId);

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.shrink();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}
