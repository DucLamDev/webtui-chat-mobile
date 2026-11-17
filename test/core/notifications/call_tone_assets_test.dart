import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/notifications/call_tone_player.dart';

void main() {
  test('mọi âm thanh cuộc gọi có tệp thật và đã khai trong pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = [
      CallTonePlayer.ringtoneAsset,
      CallTonePlayer.ringbackAsset,
      for (final cue in CallCue.values) cue.asset,
    ];
    expect(assets.toSet(), hasLength(4), reason: 'bốn âm thanh khác nhau');
    for (final asset in assets) {
      final path = 'assets/$asset';
      expect(File(path).existsSync(), isTrue, reason: '$path phải có');
      expect(File(path).lengthSync(), greaterThan(1000), reason: path);
      expect(pubspec, contains('- $path'), reason: 'khai $path');
    }
    // Bộ cũ đã bỏ hẳn.
    expect(pubspec, isNot(contains('ringtone.wav')));
    expect(pubspec, isNot(contains('ringback.wav')));
  });

  test('chuông gốc Android (app chạy nền) là tệp raw cùng nhạc chuông', () {
    final raw = File(
      'android/app/src/main/res/raw/nhac_chuong_cuoc_goi_den.mp3',
    );
    expect(raw.existsSync(), isTrue);
    expect(
      raw.lengthSync(),
      File('assets/${CallTonePlayer.ringtoneAsset}').lengthSync(),
    );
  });
}
