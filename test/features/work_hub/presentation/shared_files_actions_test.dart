import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_audio_controller.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_file_logic.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_file_providers.dart';
import 'package:webtui_chat/features/work_hub/presentation/screens/shared_files_screen.dart';
import 'package:webtui_chat/features/work_hub/presentation/widgets/shared_file_widgets.dart';

import '../work_hub_fakes.dart';

final class _Engine implements SharedAudioEngine {
  final played = <String>[];
  @override
  Stream<Duration> get onPosition => const Stream.empty();
  @override
  Stream<Duration> get onDuration => const Stream.empty();
  @override
  Stream<void> get onComplete => const Stream.empty();
  @override
  Future<void> playUrl(Uri uri) async => played.add(uri.path);
  @override
  Future<void> playFile(File file) async => played.add('file');
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

SharedFile _f(String id, String name, String mime) => SharedFile(
  id: id,
  name: name,
  mimeType: mime,
  byteSize: 100,
  createdAt: DateTime(2026, 11, 10),
);

void main() {
  final files = [
    _f('a', 'ghi-am.m4a', 'audio/mp4'),
    _f('v', 'quay.mp4', 'video/mp4'),
    _f('p', 'bao-cao.pdf', 'application/pdf'),
    _f('w', 'hop-dong.docx', 'application/octet-stream'),
    _f('x', 'so-lieu.xlsx', 'application/octet-stream'),
  ];

  Future<_Engine> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final engine = _Engine();
    final dir = Directory.systemTemp.createTempSync('files-actions');
    addTearDown(() => dir.deleteSync(recursive: true));
    final resolver = SharedFileMediaResolver(
      links: SharedFileStreamLinkCache(
        fetch: (_) async => SharedFileStreamLink(
          url: '/stream/x',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      ),
      cache: SharedFileCache(directory: () async => dir),
      absolute: (u) => Uri.parse('https://h.example.com$u'),
      download: (_, _) async {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workHubRepositoryProvider.overrideWithValue(
            FakeWorkHubRepository(files: files),
          ),
          activeServerUriProvider.overrideWithValue(
            Uri.parse('https://h.example.com/'),
          ),
          sharedAudioEngineFactoryProvider.overrideWithValue(() => engine),
          sharedFileMediaResolverProvider.overrideWith((ref, ws) => resolver),
        ],
        child: MaterialApp(
          theme: WebTuiTheme.light(),
          home: const SharedFilesScreen(workspaceId: 'ws'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return engine;
  }

  testWidgets('ghi âm: bấm là phát ngay tại dòng, không mở màn mới', (
    tester,
  ) async {
    final engine = await open(tester);
    await tester.tap(find.byKey(const Key('file_a')));
    await tester.pump();
    await tester.pump();
    expect(engine.played, ['/stream/x']);
    expect(find.byKey(const Key('file_audio_progress_a')), findsOneWidget);
    expect(find.byType(SharedFilesScreen), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);

    await tester.tap(find.byKey(const Key('file_a')));
    await tester.pump();
    expect(find.byKey(const Key('file_audio_progress_a')), findsNothing);
  });

  testWidgets('video / PDF mở bảng thao tác, không đẩy màn mới', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('file_v')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('file_sheet_cover')), findsOneWidget);
    expect(find.byKey(const Key('file_action_view')), findsOneWidget);
    // Không còn mục "Tải về" (chỉ ghi vào bộ nhớ tạm mà báo đã tải xong);
    // lưu / chia sẻ đi qua "Mở bằng ứng dụng khác".
    expect(find.byKey(const Key('file_action_download')), findsNothing);
    expect(find.byKey(const Key('file_action_external')), findsOneWidget);
    expect(
      find.text('Lưu vào máy, chia sẻ hoặc mở bằng ứng dụng khác'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('file_p')));
    await tester.pumpAndSettle();
    expect(find.text('Xem'), findsOneWidget);
    expect(find.byKey(const Key('file_sheet_cover')), findsNothing);
    expect(find.byKey(const Key('file_action_external')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('file_w')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('file_action_open')), findsOneWidget);
    expect(find.byKey(const Key('file_action_view')), findsNothing);
    expect(find.byKey(const Key('file_action_download')), findsNothing);
    expect(
      find.text('Mở bằng ứng dụng có sẵn; từ đó lưu hoặc chia sẻ'),
      findsOneWidget,
    );
    expect(find.byType(SharedFilesScreen), findsOneWidget);
  });

  testWidgets('logo loại tệp theo mime / đuôi', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('file_badge_pdf')), findsOneWidget);
    expect(find.byKey(const Key('file_badge_word')), findsOneWidget);
    expect(find.byKey(const Key('file_badge_excel')), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(sharedFileBadgeStyle(SharedFileFormat.powerpoint)!.letter, 'P');
    expect(sharedFileBadgeStyle(SharedFileFormat.other), isNull);
  });
}
