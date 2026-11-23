import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_download_service.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/widgets/files/ide_file_card.dart';

import 'support/rpc_env.dart';

class _Saver implements IdeFileSaver {
  final saved = <String>[];
  @override
  Future<String?> save(
    File file,
    String name,
    String mime, {
    Future<bool> Function()? confirmOpen,
  }) async {
    saved.add('$name|$mime|${file.readAsStringSync()}');
    return ideSavedNote(name);
  }
}

void main() {
  group('ideFilePathsIn', () {
    test('lấy đường dẫn tuyệt đối có đuôi, bỏ trùng', () {
      const text =
          'Đã tạo /home/x/app-release.apk và /srv/p/bao-cao.md; '
          'lại /home/x/app-release.apk, xem https://a.com/b/c.png và ./ngan.txt';
      expect(ideFilePathsIn(text), [
        '/home/x/app-release.apk',
        '/srv/p/bao-cao.md',
      ]);
    });
    test('chặn ../ và đường không có đuôi', () {
      expect(ideFilePathsIn('/home/x/../etc/passwd.txt'), isEmpty);
      expect(ideFilePathsIn('mở /home/x/thumuc cho tôi'), isEmpty);
    });
    test('tối đa 8 tệp', () {
      final t = [for (var i = 0; i < 12; i++) '/a/f$i.txt'].join(' ');
      expect(ideFilePathsIn(t), hasLength(8));
    });
  });

  test('ideSafeFileName chặn ../, dấu / và ký tự điều khiển', () {
    expect(ideSafeFileName('../../etc/passwd'), 'passwd');
    expect(ideSafeFileName('a/b/c.apk'), 'c.apk');
    expect(ideSafeFileName(r'..\..\win.ini'), 'win.ini');
    expect(ideSafeFileName('x\u0000y\n.txt'), 'xy.txt');
    expect(ideSafeFileName('..'), 'tep-tai-ve');
    expect(ideSafeFileName('.bashrc'), 'bashrc');
    expect(ideSafeFileName('a' * 300 + '.zip').length, lessThanOrEqualTo(120));
    expect(ideSafeFileName('a' * 300 + '.zip'), endsWith('.zip'));
    expect(ideIsImageName('A.PNG'), isTrue);
    expect(ideIsImageName('a.apk'), isFalse);
  });

  test('tên tệp: bỏ ký tự định dạng Unicode, giới hạn độ dài giữ đuôi', () {
    expect(ideSafeFileName('a\u202Egpj.exe'), 'agpj.exe');
    expect(ideSafeFileName('x\u200B\u200F\u2066\u2069\uFEFFy.txt'), 'xy.txt');
    final long = ideSafeFileName('${'a' * 300}.apk');
    expect(long.length, 120);
    expect(long.endsWith('.apk'), isTrue);
  });

  test('MIME theo đuôi, không theo IDE; chỉ .apk nhắc cài đặt', () {
    expect(ideMimeFor('a.APK'), 'application/vnd.android.package-archive');
    expect(ideMimeFor('a.pdf'), 'application/pdf');
    expect(ideMimeFor('a.xyz'), 'application/octet-stream');
    expect(ideMimeFor('khongduoi'), 'application/octet-stream');
    expect(ideSavedNote('a.apk'), contains('Chỉ cài tệp bạn tin'));
    expect(ideSavedNote('a.pdf'), isNot(contains('cài')));
  });

  test('ideFormatSize', () {
    expect(ideFormatSize(512), '512 B');
    expect(ideFormatSize(2048), '2.0 KB');
    expect(ideFormatSize(null), '');
  });

  testWidgets('thẻ hiện tên, dung lượng; bấm tải về rồi lưu', (tester) async {
    late IdeRpcEnv env;
    final saver = _Saver();
    final data = utf8.encode('noi dung');
    final dir = Directory.systemTemp.createTempSync('ide-file-test');
    addTearDown(() => dir.deleteSync(recursive: true));

    env = IdeRpcEnv((op, args) => ideFakeSilent, ops: const ['files.get']);
    await tester.runAsync(env.up);
    addTearDown(() => tester.runAsync(env.dispose));

    final service = IdeDownloadService(
      env.rpc,
      saver: saver,
      tempDir: () async => dir,
      // Lưu ra ngoài app đang tắt ở đợt đầu; test này kiểm đường lưu khi bật.
      allowSave: true,
    );
    WebTuiColors.apply(Brightness.light);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ideDownloadServiceProvider.overrideWithValue(service),
          ideSaveToDeviceProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: const Scaffold(
            body: IdeFileCard(
              path: '/home/x/../x/ung-dung.apk',
              name: '../ung-dung.apk',
              size: 2048,
            ),
          ),
        ),
      ),
    );
    expect(find.text('ung-dung.apk'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.byTooltip('Tải về'), findsOneWidget);

    await tester.tap(find.byTooltip('Tải về'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Huỷ tải'), findsOneWidget);

    // Việc vào ra tệp chạy ở vòng lặp thật, tiếp nối ở đồng hồ giả: xen kẽ.
    Future<void> until(bool Function() ok) async {
      for (var i = 0; i < 100 && !ok(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    await until(() => env.lastSocket?.sentOfType('op').isNotEmpty ?? false);
    final sock = env.lastSocket!;
    final req = sock.sentOfType('op').last['req'];
    sock.emit({
      'type': 'file_meta',
      'req': req,
      'name': 'ung-dung.apk',
      'size': data.length,
      'mime': 'text/html',
      'mtime': 1,
    });
    sock.emit({
      'type': 'file_chunk',
      'req': req,
      'seq': 0,
      'data': base64Encode(data),
    });
    sock.emit({
      'type': 'file_end',
      'req': req,
      'sha256': sha256.convert(data).toString(),
    });
    await until(() => saver.saved.isNotEmpty);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(saver.saved, hasLength(1));
    expect(
      saver.saved.single,
      'ung-dung.apk|application/vnd.android.package-archive|noi dung',
    );
    expect(find.textContaining('Đã lưu vào Tải về'), findsOneWidget);
    expect(find.textContaining('Chỉ cài tệp bạn tin'), findsOneWidget);
    expect(env.calls, ['files.get']);
    // Lưu xong thì xoá thư mục tạm ide-dl-*.
    await until(() => dir.listSync().isEmpty);
    expect(dir.listSync(), isEmpty);
  });

  testWidgets('mặc định chưa lưu tệp ra ngoài app: thẻ không có nút tải về', (
    tester,
  ) async {
    WebTuiColors.apply(Brightness.light);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: const Scaffold(
            body: IdeFileCard(path: '/a/bao-cao.pdf', size: 2048),
          ),
        ),
      ),
    );
    expect(find.text('bao-cao.pdf'), findsOneWidget);
    expect(find.byTooltip('Tải về'), findsNothing);
    expect(find.text('2.0 KB · Mở tệp này trên máy tính.'), findsOneWidget);
    // Ảnh vẫn xem được trong app.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: const Scaffold(body: IdeFileCard(path: '/a/anh.png')),
        ),
      ),
    );
    expect(find.byTooltip('Xem ảnh'), findsOneWidget);
  });

  testWidgets('IDE gửi quá dung lượng đã khai thì dừng và xoá tệp dở', (
    tester,
  ) async {
    final env = IdeRpcEnv(
      (op, args) => ideFakeSilent,
      ops: const ['files.get'],
    );
    await tester.runAsync(env.up);
    addTearDown(() => tester.runAsync(env.dispose));
    final dir = Directory.systemTemp.createTempSync('ide-file-test3');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = IdeDownloadService(
      env.rpc,
      saver: _Saver(),
      tempDir: () async => dir,
    );
    await tester.runAsync(() async {
      final dl = service.start('/a/b.bin');
      for (var i = 0; i < 100; i++) {
        if (env.lastSocket?.sentOfType('op').isNotEmpty ?? false) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final sock = env.lastSocket!;
      final req = sock.sentOfType('op').last['req'];
      sock.emit({
        'type': 'file_meta',
        'req': req,
        'name': 'b.bin',
        'size': 3,
        'mime': 'application/octet-stream',
        'mtime': 1,
      });
      sock.emit({
        'type': 'file_chunk',
        'req': req,
        'seq': 0,
        'data': base64Encode(List<int>.filled(10, 1)),
      });
      var failed = false;
      unawaited(dl.done.then((_) {}, onError: (_) => failed = true));
      for (var i = 0; i < 100 && !failed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        tester.binding.scheduleFrame();
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(failed, isTrue);
      expect(dir.listSync(), isEmpty);
    });
  });

  testWidgets('tải lỗi thì báo, huỷ thì dừng', (tester) async {
    final env = IdeRpcEnv(
      (op, args) => const IdeFakeError('not_found'),
      ops: const ['files.get'],
    );
    await tester.runAsync(env.up);
    addTearDown(() => tester.runAsync(env.dispose));
    final dir = Directory.systemTemp.createTempSync('ide-file-test2');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = IdeDownloadService(
      env.rpc,
      saver: _Saver(),
      tempDir: () async => dir,
      allowSave: true,
    );
    WebTuiColors.apply(Brightness.light);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ideDownloadServiceProvider.overrideWithValue(service),
          ideSaveToDeviceProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: const Scaffold(body: IdeFileCard(path: '/a/b.zip')),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Tải về'));
    await settle(tester);
    expect(find.text('Không tải được tệp'), findsOneWidget);

    // Huỷ giữa chừng: không còn thanh tiến độ, không báo lỗi.
    final env2 = IdeRpcEnv(
      (op, args) => ideFakeSilent,
      ops: const ['files.get'],
    );
    await tester.runAsync(env2.up);
    addTearDown(() => tester.runAsync(env2.dispose));
    final service2 = IdeDownloadService(
      env2.rpc,
      saver: _Saver(),
      tempDir: () async => dir,
    );
    await tester.runAsync(() async {
      final dl = service2.start('/a/c.zip');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dl.cancel();
      await expectLater(dl.done, throwsA(isA<IdeDownloadCancelled>()));
    });
  });
}
