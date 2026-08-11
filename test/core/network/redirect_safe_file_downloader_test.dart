import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/redirect_safe_file_downloader.dart';

void main() {
  late Directory temporaryDirectory;
  final servers = <HttpServer>[];

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'webtui-safe-download-',
    );
  });

  tearDown(() async {
    for (final server in servers) {
      await server.close(force: true);
    }
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'authenticated redirect is rejected before the sink is contacted',
    () async {
      var sinkRequests = 0;
      final sink = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(sink);
      sink.listen((request) async {
        sinkRequests += 1;
        request.response
          ..statusCode = HttpStatus.ok
          ..write('leaked');
        await request.response.close();
      });

      String? originAuthorization;
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      servers.add(origin);
      origin.listen((request) async {
        originAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${sink.port}/stolen',
          );
        await request.response.close();
      });

      final target = File('${temporaryDirectory.path}/video.mp4');
      await expectLater(
        const RedirectSafeFileDownloader().download(
          uri: Uri.parse('http://127.0.0.1:${origin.port}/video'),
          target: target,
          maxBytes: 1024,
          isStillCurrent: () async => true,
          bearerToken: 'server-a-token',
        ),
        throwsA(isA<RedirectSafeDownloadException>()),
      );

      expect(originAuthorization, 'Bearer server-a-token');
      expect(sinkRequests, 0);
      expect(await target.exists(), isFalse);
    },
  );

  test('streams bytes atomically and checks the expected length', () async {
    final bytes = utf8.encode('redirect-safe-video');
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(origin);
    origin.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..contentLength = bytes.length
        ..add(bytes);
      await request.response.close();
    });

    final target = File('${temporaryDirectory.path}/video.bin');
    final downloaded = await const RedirectSafeFileDownloader().download(
      uri: Uri.parse('http://127.0.0.1:${origin.port}/video'),
      target: target,
      maxBytes: 1024,
      expectedBytes: bytes.length,
      isStillCurrent: () async => true,
    );

    expect(downloaded.path, target.path);
    expect(await downloaded.readAsBytes(), bytes);
    expect(
      temporaryDirectory.listSync().whereType<File>().where(
        (file) => file.path.contains('.part-'),
      ),
      isEmpty,
    );
  });

  test('bounded avatar/image bytes never follow a bearer redirect', () async {
    var sinkRequests = 0;
    final sink = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(sink);
    sink.listen((request) async {
      sinkRequests += 1;
      request.response
        ..statusCode = HttpStatus.ok
        ..write('stolen-avatar');
      await request.response.close();
    });
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(origin);
    origin.listen((request) async {
      request.response
        ..statusCode = HttpStatus.temporaryRedirect
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${sink.port}/avatar',
        );
      await request.response.close();
    });

    await expectLater(
      const RedirectSafeFileDownloader().downloadBytes(
        uri: Uri.parse('http://127.0.0.1:${origin.port}/avatar'),
        maxBytes: 1024,
        bearerToken: 'avatar-token',
        isStillCurrent: () async => true,
      ),
      throwsA(isA<RedirectSafeDownloadException>()),
    );
    expect(sinkRequests, 0);
  });

  test('instance switch during streaming removes the partial file', () async {
    final firstChunkSent = Completer<void>();
    final releaseSecondChunk = Completer<void>();
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(origin);
    origin.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..contentLength = 6
        ..add(const [1, 2, 3]);
      await request.response.flush();
      firstChunkSent.complete();
      await releaseSecondChunk.future;
      request.response.add(const [4, 5, 6]);
      await request.response.close();
    });

    var current = true;
    final target = File('${temporaryDirectory.path}/switched.bin');
    final download = const RedirectSafeFileDownloader().download(
      uri: Uri.parse('http://127.0.0.1:${origin.port}/video'),
      target: target,
      maxBytes: 1024,
      expectedBytes: 6,
      isStillCurrent: () async => current,
    );
    await firstChunkSent.future;
    current = false;
    releaseSecondChunk.complete();

    await expectLater(download, throwsA(isA<RedirectSafeDownloadException>()));
    expect(await target.exists(), isFalse);
    expect(
      temporaryDirectory.listSync().whereType<File>().where(
        (file) => file.path.contains('.part-'),
      ),
      isEmpty,
    );
  });
}
