import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/platform/video_compressor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'webtui/video_compress';
  const channel = MethodChannel(channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory dir;
  late MethodChannelVideoCompressor compressor;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('video_compress_test');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    compressor = MethodChannelVideoCompressor(channel: channel);
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });

  test('nén thành công trả về CompressedVideo và gửi đúng tham số', () async {
    final out = File('${dir.path}/out.mp4');
    Map<Object?, Object?>? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call.arguments as Map<Object?, Object?>;
      await out.writeAsBytes([1, 2, 3]);
      return {'path': out.path, 'byteSize': 3};
    });
    final result = await compressor.compress(
      inputPath: '${dir.path}/in.mp4',
      outputPath: out.path,
    );
    expect(result?.path, out.path);
    expect(result?.byteSize, 3);
    expect(seen?['id'], out.path);
    expect(seen?['shortSide'], 720);
    expect(seen?['videoBitrate'], 2500000);
    expect(seen?['audioBitrate'], 128000);
  });

  test('native báo lỗi hoặc thiếu plugin thì trả null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'CANCELLED');
    });
    expect(
      await compressor.compress(inputPath: 'a', outputPath: '${dir.path}/x'),
      isNull,
    );
    messenger.setMockMethodCallHandler(channel, null);
    expect(
      await compressor.compress(inputPath: 'a', outputPath: '${dir.path}/x'),
      isNull,
    );
  });

  test('tệp kết quả không tồn tại thì trả null', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {'path': '${dir.path}/none.mp4', 'byteSize': 10},
    );
    expect(
      await compressor.compress(inputPath: 'a', outputPath: '${dir.path}/x'),
      isNull,
    );
  });

  test('tiến độ chuyển đúng callback theo id', () async {
    final out = File('${dir.path}/out.mp4');
    final other = <double>[];
    final mine = <double>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      await out.writeAsBytes([1]);
      for (final entry in {'khac': 0.9, out.path: 0.5}.entries) {
        await messenger.handlePlatformMessage(
          channelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('progress', {'id': entry.key, 'progress': entry.value}),
          ),
          (_) {},
        );
      }
      return {'path': out.path, 'byteSize': 1};
    });
    await compressor.compress(
      inputPath: 'a',
      outputPath: out.path,
      onProgress: mine.add,
    );
    expect(mine, [0.5]);
    expect(other, isEmpty);
  });

  test('cancel gửi đúng id', () async {
    Object? seen;
    String? method;
    messenger.setMockMethodCallHandler(channel, (call) async {
      method = call.method;
      seen = call.arguments;
      return null;
    });
    await compressor.cancel('/tmp/abc.mp4');
    expect(method, 'cancel');
    expect(seen, {'id': '/tmp/abc.mp4'});
  });

  test('nền tảng không hỗ trợ thì trả null, không gọi native', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return null;
    });
    expect(await compressor.compress(inputPath: 'a', outputPath: 'b'), isNull);
    expect(called, isFalse);
  });

  test('poster thành công trả về VideoPoster và gửi đúng tham số', () async {
    final out = File('${dir.path}/poster.jpg');
    String? method;
    Map<Object?, Object?>? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      method = call.method;
      seen = call.arguments as Map<Object?, Object?>;
      await out.writeAsBytes([1, 2, 3, 4]);
      return {
        'path': out.path,
        'byteSize': 4,
        'width': 1080,
        'height': 1920,
        'durationMs': 35000,
      };
    });
    final result = await compressor.poster(
      inputPath: '${dir.path}/in.mp4',
      outputPath: out.path,
    );
    expect(method, 'poster');
    expect(seen?['maxSide'], 480);
    expect(seen?['timeMs'], 1000);
    expect(seen?['input'], '${dir.path}/in.mp4');
    expect(result?.path, out.path);
    expect(result?.byteSize, 4);
    expect(result?.width, 1080);
    expect(result?.height, 1920);
    expect(result?.durationMs, 35000);
  });

  test(
    'poster: native lỗi, thiếu tệp hoặc nền tảng khác thì trả null',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'POSTER_FAILED');
      });
      expect(
        await compressor.poster(inputPath: 'a', outputPath: '${dir.path}/p'),
        isNull,
      );
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {'path': '${dir.path}/none.jpg', 'byteSize': 10},
      );
      expect(
        await compressor.poster(inputPath: 'a', outputPath: '${dir.path}/p'),
        isNull,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(
        await compressor.poster(inputPath: 'a', outputPath: '${dir.path}/p'),
        isNull,
      );
      expect(
        await const NoopVideoCompressor().poster(
          inputPath: 'a',
          outputPath: 'b',
        ),
        isNull,
      );
    },
  );
}
