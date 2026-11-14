import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_audio_controller.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_file_logic.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_file_providers.dart';

SharedFile _file(String name, String mime, {String id = 'f1', int size = 10}) {
  return SharedFile(
    id: id,
    name: name,
    mimeType: mime,
    byteSize: size,
    createdAt: DateTime.utc(2026, 11, 1),
  );
}

final class _FakeEngine implements SharedAudioEngine {
  final played = <String>[];
  bool failUrl = false;

  @override
  Stream<Duration> get onPosition => const Stream.empty();
  @override
  Stream<Duration> get onDuration => const Stream.empty();
  @override
  Stream<void> get onComplete => const Stream.empty();

  @override
  Future<void> playUrl(Uri uri) async {
    if (failUrl) throw StateError('url');
    played.add('url:$uri');
  }

  @override
  Future<void> playFile(File file) async => played.add('file');
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('shared-files-test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('nhận loại tệp theo mime và đuôi', () {
    SharedFileFormat f(String n, String m) => sharedFileFormat(_file(n, m));
    expect(f('a.pdf', 'application/octet-stream'), SharedFileFormat.pdf);
    expect(f('a', 'application/pdf'), SharedFileFormat.pdf);
    expect(f('a.DOCX', 'application/octet-stream'), SharedFileFormat.word);
    expect(
      f(
        'a',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
      SharedFileFormat.excel,
    );
    expect(f('b.xls', 'x/y'), SharedFileFormat.excel);
    expect(f('b.pptx', 'x/y'), SharedFileFormat.powerpoint);
    expect(f('b.zip', 'application/zip'), SharedFileFormat.other);
  });

  test('hành động khi bấm theo loại tệp', () {
    SharedFileTapAction a(String n, String m) =>
        sharedFileTapAction(_file(n, m));
    expect(a('a.m4a', 'audio/mp4'), SharedFileTapAction.playInline);
    expect(a('a.png', 'image/png'), SharedFileTapAction.openImage);
    expect(a('a.mp4', 'video/mp4'), SharedFileTapAction.videoSheet);
    expect(a('a.pdf', 'application/pdf'), SharedFileTapAction.pdfSheet);
    expect(a('a.docx', 'x/y'), SharedFileTapAction.openSheet);
  });

  test('tên tệp gọn: cắt giữa, giữ đuôi', () {
    expect(shortenFileName('ngan.pdf'), 'ngan.pdf');
    final out = shortenFileName('${'a' * 60}-cuoi.pdf');
    expect(out.length, 34);
    expect(out, contains('…'));
    expect(out.endsWith('cuoi.pdf'.substring(3)), isTrue);
  });

  test('ghép đường dẫn phát dần với địa chỉ API, chặn khác nguồn', () {
    final base = Uri.parse('https://chat.example.com/');
    expect(
      resolveSharedFileUrl(base, '/api/v1/media/s?token=a')?.toString(),
      'https://chat.example.com/api/v1/media/s?token=a',
    );
    expect(resolveSharedFileUrl(base, 'https://evil.example.org/s'), isNull);
    expect(resolveSharedFileUrl(base, ''), isNull);
  });

  test('cache: lần hai không tải lại; dọn khi quá giới hạn', () async {
    final cache = SharedFileCache(directory: () async => dir, maxBytes: 25);
    var downloads = 0;
    Future<void> write(File t) async {
      downloads++;
      await t.writeAsBytes(List.filled(10, 1));
    }

    final a = _file('a.pdf', 'application/pdf', id: 'a');
    final first = await cache.ensure(file: a, download: write);
    expect(first.path, endsWith('a-10.pdf'));
    await cache.ensure(file: a, download: write);
    expect(downloads, 1);

    await first.setLastModified(DateTime(2020));
    await cache.ensure(
      file: _file('b.pdf', 'x', id: 'b'),
      download: write,
    );
    await cache.ensure(
      file: _file('c.pdf', 'x', id: 'c'),
      download: write,
    );
    expect(downloads, 3);
    expect(first.existsSync(), isFalse, reason: 'tệp lâu không dùng bị xoá');
    expect(File('${dir.path}/c-10.pdf').existsSync(), isTrue);
  });

  test(
    'đường dẫn phát dần hết hạn thì xin lại, còn hạn thì dùng lại',
    () async {
      var now = DateTime.utc(2026, 11, 14, 10);
      var asked = 0;
      final links = SharedFileStreamLinkCache(
        now: () => now,
        fetch: (id) async {
          asked++;
          return SharedFileStreamLink(
            url: '/s/$asked',
            expiresAt: now.add(const Duration(minutes: 15)),
          );
        },
      );
      expect((await links.linkFor('f'))!.url, '/s/1');
      now = now.add(const Duration(minutes: 10));
      expect((await links.linkFor('f'))!.url, '/s/1');
      now = now.add(const Duration(minutes: 4, seconds: 30));
      expect((await links.linkFor('f'))!.url, '/s/2', reason: 'trừ hao 1 phút');
    },
  );

  SharedFileMediaResolver resolver({
    required bool streamOk,
    required List<String> log,
  }) {
    return SharedFileMediaResolver(
      links: SharedFileStreamLinkCache(
        fetch: (id) async => streamOk
            ? SharedFileStreamLink(
                url: '/s',
                expiresAt: DateTime.now().add(const Duration(hours: 1)),
              )
            : null,
      ),
      cache: SharedFileCache(directory: () async => dir),
      absolute: (u) => Uri.parse('https://h.example.com$u'),
      download: (file, target) async {
        log.add('download');
        await target.writeAsBytes(List.filled(file.byteSize, 1));
      },
    );
  }

  test('stream-link lỗi (503) thì quay về tải rồi dùng tệp cục bộ', () async {
    final log = <String>[];
    final r = resolver(streamOk: false, log: log);
    final file = _file('v.mp4', 'video/mp4');
    expect(await r.resolve(file), isA<SharedMediaLocal>());
    expect(await r.resolve(file), isA<SharedMediaLocal>());
    expect(log, ['download'], reason: 'lần hai dùng cache');
    final ok = resolver(streamOk: true, log: log);
    expect(await ok.resolve(file), isA<SharedMediaStream>());
  });

  test('ghi âm: phát dần; lỗi thì tải rồi phát tệp', () async {
    final log = <String>[];
    final engine = _FakeEngine();
    final controller = SharedAudioController(
      engineFactory: () => engine,
      resolver: () => resolver(streamOk: true, log: log),
    );
    final file = _file('a.m4a', 'audio/mp4');
    await controller.toggle(file);
    expect(engine.played.single, startsWith('url:https://h.example.com/s'));
    expect(controller.isActive('f1'), isTrue);
    await controller.toggle(file);
    expect(controller.isActive('f1'), isFalse);

    engine.failUrl = true;
    await controller.toggle(file);
    expect(engine.played.last, 'file');
    expect(log, ['download']);
    controller.dispose();
  });
}
