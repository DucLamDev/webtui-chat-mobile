import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_video_poster_cache.dart';

SharedFile _video(String id, {int size = 100}) => SharedFile(
  id: id,
  name: '$id.mp4',
  mimeType: 'video/mp4',
  byteSize: size,
  createdAt: DateTime(2026),
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('poster_cache_'));
  tearDown(() => dir.deleteSync(recursive: true));

  SharedVideoPosterCache build(
    Future<bool> Function(Uri, String) extract, {
    Future<Uri?> Function(String)? link,
  }) => SharedVideoPosterCache(
    directory: () async => dir,
    streamUri: link ?? (id) async => Uri.parse('https://x.test/s/$id'),
    extract: extract,
  );

  Future<bool> write(String path) async {
    File(path).writeAsBytesSync([1, 2, 3]);
    return true;
  }

  test('lần hai dùng lại tệp, không cắt lại', () async {
    var calls = 0;
    final cache = build((u, p) {
      calls++;
      return write(p);
    });
    final a = await cache.posterFor(_video('a'));
    final b = await cache.posterFor(_video('a'));
    expect(a, isNotNull);
    expect(b?.path, a?.path);
    expect(calls, 1);
  });

  test('trùng id cùng lúc chỉ cắt một lần', () async {
    var calls = 0;
    final cache = build((u, p) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return write(p);
    });
    final r = await Future.wait([
      cache.posterFor(_video('a')),
      cache.posterFor(_video('a')),
    ]);
    expect(r.every((f) => f != null), isTrue);
    expect(calls, 1);
  });

  test('lỗi trả null và không thử lại', () async {
    var calls = 0;
    final cache = build((u, p) async {
      calls++;
      return false;
    });
    expect(await cache.posterFor(_video('a')), isNull);
    expect(await cache.posterFor(_video('a')), isNull);
    expect(calls, 1);
  });

  test('không có đường dẫn phát thì null, không cắt', () async {
    var calls = 0;
    final cache = build((u, p) async {
      calls++;
      return true;
    }, link: (_) async => null);
    expect(await cache.posterFor(_video('a')), isNull);
    expect(calls, 0);
  });

  test('tối đa 2 lượt cắt song song', () async {
    var running = 0;
    var peak = 0;
    final gates = <Completer<void>>[];
    final cache = build((u, p) async {
      running++;
      if (running > peak) peak = running;
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      running--;
      return write(p);
    });
    final futures = [for (var i = 0; i < 5; i++) cache.posterFor(_video('v$i'))];
    var done = 0;
    while (done < 5) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      while (done < gates.length) {
        gates[done++].complete();
      }
    }
    final files = await Future.wait(futures);
    expect(files.every((f) => f != null), isTrue);
    expect(peak, 2);
  });
}
