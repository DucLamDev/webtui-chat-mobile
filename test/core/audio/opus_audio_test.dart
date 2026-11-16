import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/audio/opus_container.dart';
import 'package:webtui_chat/core/audio/opus_to_wav.dart';
import 'package:webtui_chat/core/audio/playable_audio.dart';

Uint8List _bytes(List<int> v) => Uint8List.fromList(v);

List<int> _el(List<int> id, List<int> data, {bool unknown = false}) {
  final size = unknown
      ? [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
      : [0x80 | data.length];
  return [...id, ...size, ...data];
}

List<int> _opusHead({int channels = 1, int preSkip = 312}) => [
  ...'OpusHead'.codeUnits,
  1,
  channels,
  preSkip & 0xFF,
  preSkip >> 8,
  0x80, 0xBB, 0, 0, // 48000
  0, 0, 0,
];

Uint8List _handMadeWebm({bool unknown = true, int lacing = 0}) {
  final track = _el(
    [0xAE],
    [
      ..._el([0xD7], [1]),
      ..._el([0x86], 'A_OPUS'.codeUnits),
      ..._el([0x63, 0xA2], _opusHead()),
    ],
  );
  final other = _el(
    [0xAE],
    [
      ..._el([0xD7], [2]),
      ..._el([0x86], 'V_VP8'.codeUnits),
    ],
  );
  final tracks = _el([0x16, 0x54, 0xAE, 0x6B], [...track, ...other]);
  List<int> block(int trackNo, List<int> payload) =>
      _el([0xA3], [0x80 | trackNo, 0, 0, 0x80 | (lacing << 1), ...payload]);
  final cluster1 = _el(
    [0x1F, 0x43, 0xB6, 0x75],
    [
      ..._el([0xE7], [0]),
      ...block(1, [1, 2, 3]),
      ...block(2, [9, 9]),
    ],
    unknown: unknown,
  );
  final groupBlock = _el([0xA0], _el([0xA1], [0x81, 0, 0, 0, 7, 8]));
  final cluster2 = _el(
    [0x1F, 0x43, 0xB6, 0x75],
    [
      ..._el([0xE7], [20]),
      ...groupBlock,
      ...block(1, [4]),
    ],
    unknown: unknown,
  );
  final segment = _el(
    [0x18, 0x53, 0x80, 0x67],
    [
      ..._el([0xEC], [0, 0, 0]),
      ...tracks,
      ...cluster1,
      ...cluster2,
    ],
    unknown: unknown,
  );
  return _bytes([
    ..._el([0x1A, 0x45, 0xDF, 0xA3], _el([0x42, 0x82], 'webm'.codeUnits)),
    ...segment,
  ]);
}

List<int> _oggPage(
  int seq,
  List<List<int>> segments, {
  int type = 0,
  int serial = 7,
}) {
  final data = [for (final s in segments) ...s];
  return [
    ...'OggS'.codeUnits,
    0,
    type,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    serial,
    0,
    0,
    0,
    seq,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    segments.length,
    for (final s in segments) s.length,
    ...data,
  ];
}

bool _opusAvailable() {
  for (final n in ['libopus.so.0', 'libopus.so', 'libopus.dylib']) {
    try {
      DynamicLibrary.open(n);
      return true;
    } on Object {
      continue;
    }
  }
  return false;
}

void main() {
  group('nhận diện', () {
    test('byte đầu', () {
      expect(
        sniffAudioContainer([0x1A, 0x45, 0xDF, 0xA3, 0]),
        AudioContainer.webm,
      );
      expect(sniffAudioContainer('OggS'.codeUnits), AudioContainer.ogg);
      expect(sniffAudioContainer('ftyp'.codeUnits), AudioContainer.other);
      expect(sniffAudioContainer([1]), AudioContainer.other);
    });

    test('tên / mime', () {
      expect(looksLikeOpusContainer(name: 'a.WEBM'), isTrue);
      expect(looksLikeOpusContainer(name: 'a.opus'), isTrue);
      expect(
        looksLikeOpusContainer(name: 'v', mimeType: 'audio/webm;codecs=opus'),
        isTrue,
      );
      expect(
        looksLikeOpusContainer(name: 'a.m4a', mimeType: 'audio/mp4'),
        isFalse,
      );
      expect(looksLikeOpusContainer(), isFalse);
    });

    test('chỉ iOS / macOS cần đổi', () {
      bool need(TargetPlatform p) =>
          audioNeedsTranscode(name: 'a.webm', platform: p);
      expect(need(TargetPlatform.iOS), isTrue);
      expect(need(TargetPlatform.macOS), isTrue);
      expect(need(TargetPlatform.android), isFalse);
      expect(
        audioNeedsTranscode(name: 'a.m4a', platform: TargetPlatform.iOS),
        isFalse,
      );
    });
  });

  group('tách WebM', () {
    test('unknown-size, bỏ track khác, đọc cả BlockGroup', () {
      final s = parseWebmOpus(_handMadeWebm());
      expect(s.channels, 1);
      expect(s.preSkip, 312);
      expect(s.packets.map((p) => p.toList()), [
        [1, 2, 3],
        [7, 8],
        [4],
      ]);
    });

    test('kích thước đầy đủ cũng đọc được', () {
      final s = parseWebmOpus(_handMadeWebm(unknown: false));
      expect(s.packets.length, 3);
    });

    test('tệp bị cắt giữa chừng giữ phần đã đọc', () {
      final full = _handMadeWebm();
      final s = parseWebmOpus(Uint8List.sublistView(full, 0, full.length - 2));
      expect(s.packets.length, 2);
    });

    test('lacing và không có Opus báo lỗi', () {
      expect(
        () => parseWebmOpus(_handMadeWebm(lacing: 1)),
        throwsA(isA<OpusContainerException>()),
      );
      expect(
        () => parseOpusContainer(_bytes([1, 2, 3, 4])),
        throwsA(isA<OpusContainerException>()),
      );
    });

    test('tệp mẫu do ffmpeg ghi (có / không live)', () {
      for (final name in ['tone.webm', 'tone_live.webm']) {
        final s = parseOpusContainer(
          File('test/fixtures/audio/$name').readAsBytesSync(),
        );
        expect(s.channels, 1, reason: name);
        expect(s.packets.length, greaterThan(10), reason: name);
      }
    });
  });

  group('tách Ogg', () {
    test('bỏ OpusHead / OpusTags, ghép nhiều segment thành một gói', () {
      final bytes = _bytes([
        ..._oggPage(0, [_opusHead(preSkip: 100)], type: 2),
        ..._oggPage(1, [
          [...'OpusTags'.codeUnits, 0, 0, 0, 0],
        ]),
        ..._oggPage(2, [
          List<int>.filled(255, 5),
          [1, 2],
          [3],
        ]),
      ]);
      final s = parseOggOpus(bytes);
      expect(s.preSkip, 100);
      expect(s.packets.first.length, 257);
      expect(s.packets[1].toList(), [3]);
    });

    test('gói nằm vắt qua hai trang', () {
      final bytes = _bytes([
        ..._oggPage(0, [_opusHead()], type: 2),
        ..._oggPage(1, [List<int>.filled(255, 8)]),
        ..._oggPage(2, [
          List<int>.filled(10, 8),
          [4],
        ], type: 1),
      ]);
      final s = parseOggOpus(bytes);
      expect(s.packets.map((p) => p.length), [265, 1]);
    });

    test('mẫu ffmpeg và lỗi', () {
      final s = parseOpusContainer(
        File('test/fixtures/audio/tone.ogg').readAsBytesSync(),
      );
      expect(s.channels, 1);
      expect(s.preSkip, greaterThan(0));
      expect(s.packets.length, greaterThan(10));
      expect(
        () => parseOggOpus(
          _bytes([
            ..._oggPage(0, [
              [1, 2, 3],
            ], type: 2),
          ]),
        ),
        throwsA(isA<OpusContainerException>()),
      );
    });
  });

  group('WAV', () {
    test('header đúng', () {
      final wav = buildWav(Int16List.fromList([1, -2, 3]), channels: 2);
      final v = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
      expect(v.getUint32(4, Endian.little), wav.length - 8);
      expect(v.getUint16(22, Endian.little), 2);
      expect(v.getUint32(24, Endian.little), 48000);
      expect(v.getUint32(28, Endian.little), 48000 * 2 * 2);
      expect(v.getUint32(40, Endian.little), 6);
      expect(v.getInt16(46, Endian.little), -2);
      expect(wav.length, 50);
    });
  });

  group('playableAudioFile', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('playable_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('m4a trả nguyên tệp', () async {
      final f = File('${tmp.path}/a.m4a')
        ..writeAsBytesSync([0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70]);
      final out = await playableAudioFile(
        source: f,
        cacheKey: 'k',
        cacheDirectory: Directory('${tmp.path}/c'),
      );
      expect(out.path, f.path);
    });

    test('WebM hỏng báo lỗi và không để lại tệp', () async {
      final f = File('${tmp.path}/a.webm')
        ..writeAsBytesSync([0x1A, 0x45, 0xDF, 0xA3, 0x80]);
      final cache = Directory('${tmp.path}/c');
      await expectLater(
        playableAudioFile(source: f, cacheKey: 'k', cacheDirectory: cache),
        throwsA(isA<Object>()),
      );
      expect(cache.listSync().where((e) => e.path.endsWith('.wav')), isEmpty);
    });

    final hasOpus = _opusAvailable();
    final skip = hasOpus ? null : 'Máy không có libopus để nạp';

    test('giải mã thật WebM / Ogg ra WAV và dùng lại bộ nhớ đệm', () async {
      final cache = Directory('${tmp.path}/c');
      for (final name in ['tone.webm', 'tone_live.webm', 'tone.ogg']) {
        final src = File('test/fixtures/audio/$name');
        final out = await playableAudioFile(
          source: src,
          cacheKey: 'file/$name',
          cacheDirectory: cache,
        );
        expect(out.path.endsWith('.wav'), isTrue);
        // WAV chỉ nằm trong thư mục được giao (kho theo phiên), không ra
        // thư mục tạm chung.
        expect(out.parent.path, cache.path);
        final wav = out.readAsBytesSync();
        // 0,5 giây, 48 kHz, 16 bit, đơn kênh ≈ 48000 byte (+ sai số khung).
        expect(
          wav.length,
          inInclusiveRange(44 + 44000, 44 + 52000),
          reason: name,
        );
        final samples = Int16List.sublistView(wav, 44);
        final peak = samples.fold<int>(0, (m, s) => s.abs() > m ? s.abs() : m);
        expect(peak, greaterThan(1000), reason: '$name phải có tiếng');
        final stamp = out.lastModifiedSync();
        final again = await playableAudioFile(
          source: src,
          cacheKey: 'file/$name',
          cacheDirectory: cache,
        );
        expect(again.lastModifiedSync(), stamp);
      }
    }, skip: skip);
  });
}
