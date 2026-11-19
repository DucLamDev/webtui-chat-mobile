import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_download_service.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_media_models.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/media/ide_appscreen_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/media/ide_video_list_screen.dart';

import '../support/more_env.dart';
import '../support/rpc_env.dart';

Map<String, Object?> _row(String state, {int done = 1}) => {
  'slug': 'ban-tin',
  'title': 'Bản tin <script>',
  'ratio': '9:16',
  'scenes': 3,
  'seconds': 65,
  'state': state,
  'status': state == 'nhap'
      ? {
          'step': 'render',
          'done': done,
          'total': 3,
          'note': '',
          'state': 'running',
        }
      : null,
};

void main() {
  group('Studio video', () {
    testWidgets('running thì hỏi lại, xong thì thôi', (tester) async {
      var running = true;
      final env = await pumpMore(
        tester,
        const IdeVideoListScreen(
          project: 'web',
          refreshInterval: Duration(milliseconds: 50),
        ),
        (op, a) => switch (op) {
          'video.list' => {
            'project': 'web',
            'videos': [_row(running ? 'nhap' : 'da-xuat')],
          },
          _ => null,
        },
        ops: {'video.list'},
      );
      expect(find.text('Bản tin <script>'), findsOneWidget);
      expect(
        find.byKey(const Key('ide_video_progress_ban-tin')),
        findsOneWidget,
      );
      final before = sentOps(env, 'video.list').length;
      await tester.pump(const Duration(milliseconds: 60));
      await settle(tester);
      expect(sentOps(env, 'video.list').length, greaterThan(before));
      running = false;
      await tester.pump(const Duration(milliseconds: 60));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 60));
      await settle(tester);
      final stopped = sentOps(env, 'video.list').length;
      expect(find.byKey(const Key('ide_video_progress_ban-tin')), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(sentOps(env, 'video.list').length, stopped);
    });

    testWidgets('danh sách rỗng và lỗi có nút thử lại', (tester) async {
      await pumpMore(
        tester,
        const IdeVideoListScreen(project: 'web'),
        (op, a) => {'project': 'web', 'videos': []},
        ops: {'video.list'},
      );
      expect(find.text('Chưa có video'), findsOneWidget);
      await pumpMore(
        tester,
        const IdeVideoListScreen(project: 'web'),
        (op, a) => const IdeFakeError('forbidden'),
        ops: {'video.list'},
      );
      expect(find.text('Không có quyền'), findsOneWidget);
    });
  });

  group('Màn hình app (giao diện)', () {
    testWidgets('run:false báo nhờ quản trị', (tester) async {
      await pumpMore(
        tester,
        const IdeAppScreenScreen(project: 'web'),
        (op, a) => {'ok': true, 'run': false},
        ops: {'appscreen.check', 'appscreen.status', 'appscreen.frame'},
      );
      expect(find.textContaining('nhờ quản trị'), findsOneWidget);
    });

    testWidgets('không có phiên: hiện "Chưa mở"; op ẩn thì ẩn nút', (
      tester,
    ) async {
      await pumpMore(
        tester,
        const IdeAppScreenScreen(project: 'web'),
        (op, a) => switch (op) {
          'appscreen.check' => {'ok': true, 'run': true},
          'appscreen.status' => {'sessions': [], 'max': 2, 'devices': {}},
          _ => null,
        },
        ops: {'appscreen.check', 'appscreen.status', 'appscreen.frame'},
      );
      expect(find.text('Chưa mở màn hình app'), findsOneWidget);
      expect(
        find.byKey(const Key('ide_app_submit')),
        findsNothing,
      ); // không có run
    });

    for (final (name, extra, hasStop) in [
      ('chỉ có run: không có nút Dừng', 'appscreen.run', false),
      ('chỉ có stop: không có nút Đổi thiết lập', 'appscreen.stop', true),
    ]) {
      testWidgets('có phiên, $name', (tester) async {
        await pumpMore(
          tester,
          const IdeAppScreenScreen(project: 'web'),
          (op, a) => switch (op) {
            'appscreen.check' => {'ok': true, 'run': true},
            'appscreen.status' => {
              'sessions': [
                {
                  'project': 'web',
                  'status': 'running',
                  'device': 'iphone',
                  'dark': false,
                },
              ],
              'max': 2,
              'devices': {
                'iphone': {'label': 'iPhone', 'platform': 'ios'},
              },
            },
            _ => const IdeFakeError('busy'),
          },
          ops: {
            'appscreen.check',
            'appscreen.status',
            'appscreen.frame',
            extra,
          },
        );
        expect(
          find.byKey(const Key('ide_app_stop')),
          hasStop ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('ide_app_change')),
          hasStop ? findsNothing : findsOneWidget,
        );
      });
    }
  });

  group('tải có trần dung lượng', () {
    Future<Object?> tryDownload(int size, int cap) async {
      final env = IdeRpcEnv((op, a) => ideFakeSilent, ops: const ['files.get']);
      await env.up();
      final tmp = await Directory.systemTemp.createTemp('media-test-');
      final svc = IdeDownloadService(env.rpc, tempDir: () async => tmp);
      final d = svc.start('/srv/web/v.mp4', maxBytes: cap);
      Object? err;
      final done = d.done.then<void>((_) {}, onError: (Object e) => err = e);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final req = env.lastSocket!.sentOfType('op').single['req'];
      env.lastSocket!.emit({
        'type': 'file_meta',
        'req': req,
        'name': 'v.mp4',
        'size': size,
      });
      await done.timeout(const Duration(seconds: 2));
      await env.dispose();
      await tmp.delete(recursive: true);
      return err;
    }

    test('ảnh > 8 MB bị chặn (Mở trên máy tính)', () async {
      expect(
        await tryDownload(ideVideoImageMaxBytes + 1, ideVideoImageMaxBytes),
        isA<IdeDownloadTooLarge>(),
      );
    });
    test('video > 150 MB bị chặn', () async {
      expect(
        await tryDownload(ideVideoFileMaxBytes + 1, ideVideoFileMaxBytes),
        isA<IdeDownloadTooLarge>(),
      );
    });
  });
}
