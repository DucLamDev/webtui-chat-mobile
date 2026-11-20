import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/core/storage/local_media_cache_usage.dart';
import 'package:webtui_chat/design_system/components/webtui_components.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/media_cache_providers.dart';
import 'package:webtui_chat/features/settings/domain/entities/app_settings.dart';
import 'package:webtui_chat/features/settings/domain/repositories/app_settings_repository.dart';
import 'package:webtui_chat/features/settings/presentation/screens/app_settings_screen.dart';

void main() {
  tearDown(() => WebTuiColors.apply(Brightness.light));

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    required bool dark,
    _FakeMediaCacheUsage? mediaCache,
  }) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WebTuiColors.apply(dark ? Brightness.dark : Brightness.light);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(
              flavor: AppFlavor.dev,
              apiBaseUri: Uri.parse('http://localhost:8080'),
              wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
            ),
          ),
          appSettingsRepositoryProvider.overrideWithValue(_MemoryRepository()),
          activeServerDiscoveryProvider.overrideWithValue(_discovery()),
          localMediaCacheUsageProvider.overrideWithValue(
            mediaCache ?? _FakeMediaCacheUsage(),
          ),
        ],
        child: MaterialApp(
          theme: dark ? WebTuiTheme.dark() : WebTuiTheme.light(),
          home: const AppSettingsScreen(),
        ),
      ),
    );
    // Kiểm tra phiên bản / quyền thông báo chạy nền lúc mở màn: cho chạy xong
    // để không còn bộ đếm giờ treo khi test kết thúc.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    return ProviderScope.containerOf(
      tester.element(find.byType(AppSettingsScreen)),
    );
  }

  Color? headerColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style?.color;

  testWidgets('sáng: nhóm là thẻ trắng trên nền xám, tiêu đề nhóm màu xám', (
    tester,
  ) async {
    await pumpScreen(tester, dark: false);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      WebTuiColors.groupBackground,
    );
    expect(
      find.byKey(const Key('settings_section_card')),
      findsAtLeastNWidgets(4),
    );
    expect(headerColor(tester, 'Thông báo'), WebTuiColors.textMuted);
    expect(headerColor(tester, 'Thông báo'), isNot(WebTuiColors.primary));
    // Nút cuối dòng là nút viên thuốc, không còn nút chữ xanh.
    expect(find.byType(TextButton), findsNothing);
    expect(
      find.widgetWithText(SettingsActionButton, 'Cho phép'),
      findsOneWidget,
    );
  });

  testWidgets('tối: giữ nền liền, không chia thẻ; tiêu đề nhóm màu xám', (
    tester,
  ) async {
    await pumpScreen(tester, dark: true);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      WebTuiColors.page,
    );
    expect(find.byKey(const Key('settings_section_card')), findsNothing);
    expect(headerColor(tester, 'Giao diện'), WebTuiColors.textMuted);
  });

  testWidgets(
    'dung lượng lưu trên máy: hiện cỡ kho, xoá có hỏi lại rồi tính lại',
    (tester) async {
      final cache = _FakeMediaCacheUsage(bytes: (12.5 * 1024 * 1024).round());
      await pumpScreen(tester, dark: false, mediaCache: cache);
      await tester.pump();
      expect(find.text('Dung lượng lưu trên máy'), findsOneWidget);
      expect(find.text('12,5 MB'), findsOneWidget);

      final clearRow = find.byKey(
        const ValueKey('app-settings-clear-media-cache'),
      );
      await tester.ensureVisible(clearRow);
      await tester.tap(
        find.descendant(
          of: clearRow,
          matching: find.byType(SettingsActionButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Xóa bộ nhớ đệm?'), findsOneWidget);
      // Huỷ: không xoá gì.
      await tester.tap(find.byKey(const Key('webtui_dialog_cancel')));
      await tester.pumpAndSettle();
      expect(cache.clears, 0);

      await tester.tap(
        find.descendant(
          of: clearRow,
          matching: find.byType(SettingsActionButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
      await tester.pumpAndSettle();
      expect(cache.clears, 1);
      expect(find.text('0 B'), findsOneWidget);
      expect(find.text('Đã xóa bộ nhớ đệm'), findsOneWidget);
    },
  );

  testWidgets('tính dung lượng lỗi: báo lỗi, chạm để tính lại', (tester) async {
    final cache = _FakeMediaCacheUsage(bytes: 2048, failMeasure: true);
    await pumpScreen(tester, dark: false, mediaCache: cache);
    await tester.pump();
    expect(
      find.text('Không tính được dung lượng. Chạm để thử lại.'),
      findsOneWidget,
    );

    cache.failMeasure = false;
    final row = find.byKey(const ValueKey('app-settings-media-cache-size'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pump();
    expect(find.text('2,0 KB'), findsOneWidget);
    expect(
      find.text('Không tính được dung lượng. Chạm để thử lại.'),
      findsNothing,
    );
  });

  testWidgets(
    'công tắc tự tải ảnh khi dùng 4G: mặc định bật, tắt thì báo cho widget media',
    (tester) async {
      final container = await pumpScreen(tester, dark: false);
      expect(container.read(mediaAutoDownloadOnCellularProvider), isTrue);
      final row = find.byKey(
        const ValueKey('app-settings-auto-download-cellular'),
      );
      await tester.ensureVisible(row);
      final toggle = find.descendant(
        of: row,
        matching: find.byType(WebTuiToggle),
      );
      expect(tester.widget<WebTuiToggle>(toggle).value, isTrue);

      await tester.tap(toggle);
      await tester.pump();
      expect(tester.widget<WebTuiToggle>(toggle).value, isFalse);
      expect(container.read(mediaAutoDownloadOnCellularProvider), isFalse);
    },
  );

  test('định dạng dung lượng', () {
    expect(formatStorageBytes(0), '0 B');
    expect(formatStorageBytes(512), '512 B');
    expect(formatStorageBytes(2048), '2,0 KB');
    expect(formatStorageBytes(150 * 1024 * 1024), '150 MB');
    expect(formatStorageBytes(3 * 1024 * 1024 * 1024), '3,0 GB');
  });

  testWidgets('chưa bật khoá ứng dụng: không có dòng thời gian khoá', (
    tester,
  ) async {
    await pumpScreen(tester, dark: false);
    expect(find.text('Khóa ứng dụng'), findsOneWidget);
    expect(find.textContaining('Tự khóa'), findsNothing);
  });
}

class _FakeMediaCacheUsage implements LocalMediaCacheUsage {
  _FakeMediaCacheUsage({this.bytes = 0, this.failMeasure = false});

  int bytes;
  bool failMeasure;
  int clears = 0;

  @override
  Future<int> usedBytes() async {
    if (failMeasure) throw StateError('đọc thư mục lỗi');
    return bytes;
  }

  @override
  Future<void> clear() async {
    clears += 1;
    bytes = 0;
  }
}

class _MemoryRepository implements AppSettingsRepository {
  AppSettings _settings = const AppSettings();

  @override
  Future<AppSettings> read() async => _settings;

  @override
  Future<void> save(AppSettings settings) async => _settings = settings;
}

SelfHostedServerDiscovery _discovery() => SelfHostedServerDiscovery(
  instanceId: '11111111-1111-4111-8111-111111111111',
  discoveryVersion: '1',
  domain: 'localhost',
  name: 'Company Chat',
  apiBaseUri: Uri.parse('http://localhost:8080'),
  wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
  registrationMode: 'open',
  appVersion: 'test',
  apiContractVersion: 1,
  serverVersion: 'test',
  minimumSupportedMobileVersion: '1.0.0',
  capabilities: const SelfHostedCapabilities(
    moderation: true,
    reporting: true,
    blocking: true,
    accountDeletion: true,
    legalAcceptance: true,
  ),
);
