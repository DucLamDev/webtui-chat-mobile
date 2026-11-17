import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/notifications/call_tone_player.dart';

/// Trình phát giả: ghi lại lời gọi, không chạm nền tảng.
class _FakePlayer extends Fake implements AudioPlayer {
  final calls = <String>[];
  double? playedVolume;
  ReleaseMode? loopMode;

  @override
  Future<void> setAudioContext(AudioContext ctx) async => calls.add('context');

  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async {
    loopMode = releaseMode;
    calls.add('mode');
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    playedVolume = volume;
    calls.add('play');
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  late List<_FakePlayer> created;

  setUp(() {
    created = [];
    CallTonePlayer.createPlayer = () {
      final player = _FakePlayer();
      created.add(player);
      return player;
    };
  });
  tearDown(() {
    CallTonePlayer.createPlayer = AudioPlayer.new;
    CallTonePlayer.volume = CallTonePlayer.defaultVolume;
  });

  test('chuông phát lặp theo Âm lượng đã chọn', () async {
    CallTonePlayer.volume = 0.5;
    final tone = CallTonePlayer.ringtone();
    await tone.start();
    expect(created, hasLength(1));
    expect(created.single.playedVolume, 0.5);
    expect(created.single.loopMode, ReleaseMode.loop);
    await tone.stop();
    expect(created.single.calls, containsAllInOrder(['stop', 'dispose']));
  });

  test('Âm lượng 0: không phát chuông', () async {
    CallTonePlayer.volume = 0;
    await CallTonePlayer.ringtone().start();
    await CallTonePlayer.ringback().start();
    expect(created, isEmpty);
  });

  testWidgets(
    'phát thử: đúng mức, phát một lần, tự dừng; lần mới dừng lần trước; 0 chỉ dừng',
    (tester) async {
      await CallTonePlayer.preview(0.3);
      expect(created, hasLength(1));
      expect(created[0].playedVolume, 0.3);
      expect(created[0].loopMode, ReleaseMode.stop);

      await CallTonePlayer.preview(0.6);
      expect(created, hasLength(2));
      expect(created[0].calls, containsAllInOrder(['stop', 'dispose']));
      expect(created[1].playedVolume, 0.6);

      await tester.pump(CallTonePlayer.previewDuration);
      expect(created[1].calls, containsAllInOrder(['play', 'stop', 'dispose']));

      await CallTonePlayer.preview(0);
      expect(created, hasLength(2));
    },
  );
}
