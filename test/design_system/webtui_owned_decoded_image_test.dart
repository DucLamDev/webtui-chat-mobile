import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_owned_decoded_image.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAA'
  'AARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXYzBO'
  'm/kfAAQ0AjJ06KygAAAAAElFTkSuQmCC',
);

Uint8List _paddedPixel([int padding = 8 * 1024]) {
  final chunkType = ascii.encode('vpAg');
  final chunkData = Uint8List(padding);
  final chunk = ByteData(12 + padding)..setUint32(0, padding, Endian.big);
  chunk.buffer.asUint8List().setRange(4, 8, chunkType);
  chunk.buffer.asUint8List().setRange(8, 8 + padding, chunkData);
  chunk.setUint32(8 + padding, _crc32(chunkType, chunkData), Endian.big);
  final iendOffset = _onePixelPng.length - 12;
  final result = BytesBuilder(copy: false)
    ..add(_onePixelPng.sublist(0, iendOffset))
    ..add(chunk.buffer.asUint8List())
    ..add(_onePixelPng.sublist(iendOffset));
  return result.takeBytes();
}

int _crc32(List<int> prefix, Uint8List data) {
  final table = List<int>.generate(256, (index) {
    var value = index;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) != 0 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    return value;
  }, growable: false);
  var crc = 0xffffffff;
  void update(Iterable<int> bytes) {
    for (final byte in bytes) {
      crc = table[(crc ^ byte) & 0xff] ^ (crc >>> 8);
    }
  }

  update(prefix);
  update(data);
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxFrames = 120,
}) async {
  for (var frame = 0; frame < maxFrames; frame++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('condition was not reached within $maxFrames frames');
}

void main() {
  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('padded encoded bytes never enter Flutter global ImageCache', (
    tester,
  ) async {
    var created = 0;
    var disposed = 0;
    Object? decodeError;
    final bytes = _paddedPixel();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WebTuiOwnedDecodedImage(
          requestKey: 'padded',
          loadBytes: () async => bytes,
          maxEncodedBytes: bytes.lengthInBytes,
          decodeTargetWidth: 32,
          decodeTargetHeight: 32,
          fallback: const Text('fallback'),
          loading: const Text('loading'),
          onImageCreated: () => created++,
          onImageDisposed: () => disposed++,
          onDecodeError: (error) => decodeError = error,
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => decodeError != null || find.byType(RawImage).evaluate().isNotEmpty,
    );

    expect(decodeError, isNull);
    expect(find.byType(RawImage), findsOneWidget);
    expect(PaintingBinding.instance.imageCache.currentSize, 0);
    expect(PaintingBinding.instance.imageCache.currentSizeBytes, 0);
    expect(created, 1);
    expect(disposed, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposed, 1);
  });

  testWidgets('late decode is disposed after request replacement', (
    tester,
  ) async {
    final first = Completer<Uint8List?>();
    final second = Completer<Uint8List?>();
    var request = 1;
    var created = 0;
    var disposed = 0;
    final pixel = _paddedPixel(8);

    Widget subject() {
      final current = request;
      return Directionality(
        textDirection: TextDirection.ltr,
        child: WebTuiOwnedDecodedImage(
          requestKey: current,
          loadBytes: () => current == 1 ? first.future : second.future,
          maxEncodedBytes: 2 * 1024 * 1024,
          decodeTargetWidth: 32,
          decodeTargetHeight: 32,
          fallback: const Text('fallback'),
          loading: const Text('loading'),
          onImageCreated: () => created++,
          onImageDisposed: () => disposed++,
        ),
      );
    }

    await tester.pumpWidget(subject());
    request = 2;
    await tester.pumpWidget(subject());
    second.complete(pixel);
    await _pumpUntil(tester, () => find.byType(RawImage).evaluate().isNotEmpty);
    expect(find.byType(RawImage), findsOneWidget);

    first.complete(pixel);
    await tester.pump(const Duration(milliseconds: 30));
    expect(created, 1);
    expect(disposed, 0, reason: 'the stale response is dropped before decode');
    expect(PaintingBinding.instance.imageCache.currentSize, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposed, 1, reason: 'the active second frame is disposed');
  });

  testWidgets(
    'lazy padded-image grid keeps global cache empty and live images bounded',
    (tester) async {
      final padded = _paddedPixel();
      final controller = ScrollController();
      var created = 0;
      var disposed = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 400,
            child: GridView.builder(
              controller: controller,
              itemCount: 500,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: 80,
              ),
              itemBuilder: (context, index) {
                return WebTuiOwnedDecodedImage(
                  requestKey: 'padded-$index',
                  loadBytes: () async => Uint8List.fromList(padded),
                  maxEncodedBytes: padded.lengthInBytes,
                  decodeTargetWidth: 32,
                  decodeTargetHeight: 32,
                  fallback: const SizedBox.square(dimension: 32),
                  loading: const SizedBox.square(dimension: 32),
                  onImageCreated: () => created++,
                  onImageDisposed: () => disposed++,
                );
              },
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () => created > 0);

      for (final fraction in const [0.25, 0.5, 0.75, 1.0]) {
        final before = created;
        controller.jumpTo(controller.position.maxScrollExtent * fraction);
        await tester.pump();
        await _pumpUntil(tester, () => created > before);
        expect(PaintingBinding.instance.imageCache.currentSize, 0);
        expect(PaintingBinding.instance.imageCache.currentSizeBytes, 0);
        expect(
          created - disposed,
          lessThan(50),
          reason: 'only the lazy viewport may own decoded images',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntil(tester, () => disposed == created);
      expect(PaintingBinding.instance.imageCache.currentSize, 0);
      expect(PaintingBinding.instance.imageCache.currentSizeBytes, 0);
      expect(disposed, created);
      controller.dispose();
    },
  );
}
