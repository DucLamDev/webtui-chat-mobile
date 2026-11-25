// Điểm vào chỉ để xem giao diện màn VPSTTT IDE (không vào bản phát hành):
//   vpsttt-app run --target test/preview/ide_web_preview.dart
// Dùng khung giả thay WebView, không gọi máy chủ.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_access.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_bridge_dispatcher.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_device_keys.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_prompter.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_providers.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_session_cleaner.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_use_cases.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_device_key.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_host_policy.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_launch.dart';
import 'package:webtui_chat/features/ide_web/presentation/screens/ide_web_screen.dart';
import 'package:webtui_chat/features/ide_web/presentation/widgets/ide_web_mic_chip.dart';
import 'package:webtui_chat/features/ide_web/presentation/widgets/ide_web_prompt_dialog.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/work_hub_providers.dart';
import 'package:webtui_chat/features/work_hub/presentation/widgets/work_apps_grid.dart';

import '../features/ide_web/support/fakes.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: WebTuiTheme.light(),
    darkTheme: WebTuiTheme.dark(),
    builder: (context, child) {
      WebTuiColors.apply(Theme.of(context).brightness);
      return child!;
    },
    home: const _Menu(),
  );
}

FakeIdeWebRepository _repository(Result<IdeWebLaunch> launch) =>
    FakeIdeWebRepository(launch: launch);

final _scenes = <String, FakeIdeWebRepository Function()>{
  'Đang mở': () =>
      _repository(Success(testBrowserLaunch()))..launchGate = Completer<void>(),
  'Chờ trình duyệt': () => _repository(Success(testBrowserLaunch())),
  'Trang IDE': () => _repository(
    Success(IdeWebDirectLaunch(launchId: 'l', entry: testEntry())),
  ),
  'Chưa kết nối được': () => _repository(failResult(FailureKind.network)),
  'Mở quá nhiều lần': () => _repository(failResult(FailureKind.rateLimited)),
  'Quản trị tắt': () =>
      _repository(failResult(FailureKind.forbidden, code: 'IDE_WEB_DISABLED')),
  'Chưa được cấp quyền': () => _repository(
    failResult(FailureKind.forbidden, code: 'IDE_WEB_NOT_ALLOWED'),
  ),
  'Hết hạn': () => _repository(
    failResult(FailureKind.unknown, code: 'IDE_WEB_LAUNCH_EXPIRED'),
  ),
  'WebView cũ': () => _repository(
    Success(IdeWebDirectLaunch(launchId: 'l', entry: testEntry())),
  ),
};

final _prompts = <String, IdeWebPrompt>{
  'Hỏi đăng ký khoá': const IdeWebCreateKeyPrompt(IdeWebKeyPurpose.biometric),
  'Hỏi xoá khoá': const IdeWebDeleteKeyPrompt(),
  'Hỏi lưu tệp': const IdeWebSaveFilePrompt(
    name: 'bao-cao-thang-11.pdf',
    bytes: 2400000,
  ),
  'Hỏi micro': const IdeWebMicrophonePrompt(),
  'Hỏi liên kết ngoài': IdeWebExternalLinkPrompt(
    Uri.parse('https://example.com/tai-lieu'),
  ),
};

/// Tên các cảnh, theo thứ tự trong danh sách.
List<String> get previewScenes => [
  ..._scenes.keys,
  ..._prompts.keys,
  'Chỉ báo đang thu',
  'Ô trong lưới',
];

class _Menu extends StatelessWidget {
  const _Menu();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Xem thử VPSTTT IDE')),
    body: ListView(
      children: [
        for (final scene in _scenes.entries)
          ListTile(
            title: Text(scene.key),
            onTap: () => _open(
              context,
              _Scene(
                repository: scene.value(),
                supported: scene.key != 'WebView cũ',
              ),
            ),
          ),
        for (final prompt in _prompts.entries)
          ListTile(
            title: Text(prompt.key),
            onTap: () => showDialog<bool>(
              context: context,
              builder: (_) => IdeWebPromptDialog(prompt: prompt.value),
            ),
          ),
        ListTile(
          title: const Text('Chỉ báo đang thu'),
          onTap: () => _open(context, const _MicScene()),
        ),
        ListTile(
          title: const Text('Ô trong lưới'),
          onTap: () => _open(context, const _TileScene()),
        ),
      ],
    ),
  );

  static void _open(BuildContext context, Widget child) => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => child)),
  );
}

class _Scene extends StatelessWidget {
  const _Scene({required this.repository, required this.supported});

  final FakeIdeWebRepository repository;
  final bool supported;

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      ideWebEnabledProvider.overrideWithValue(true),
      ideWebHostPolicyProvider.overrideWithValue(IdeWebHostPolicy(testBase)),
      authAccessTokenProvider.overrideWith((_) async => 'token'),
      ideWebRepositoryProvider.overrideWithValue(repository),
      ideWebPendingStoreProvider.overrideWithValue(FakePendingStore()),
      ideWebSessionReaderProvider.overrideWithValue(
        IdeWebSessionReader(
          tokens: FakeTokenRepository(),
          currentUserId: () async => 'user-1',
        ),
      ),
      ideWebSessionCleanerProvider.overrideWithValue(
        IdeWebSessionCleaner(
          data: FakeDataCleaner(),
          markers: MemoryMarkerStore(),
        ),
      ),
      ideWebDeviceKeysProvider.overrideWithValue(
        IdeWebDeviceKeys(chip: FakeKeyChip(), store: MemoryKeyStore()),
      ),
      ideWebAppInfoProvider.overrideWithValue(
        const IdeWebAppInfo(
          appVersion: '1',
          platform: 'android',
          osVersion: '15',
        ),
      ),
      ideWebBrowserProvider.overrideWithValue(FakeBrowser()),
      ideWebViewFactoryProvider.overrideWithValue(
        (_) => FakeIdeWebView()..supported = supported,
      ),
    ],
    child: const IdeWebScreen(),
  );
}

class _MicScene extends StatelessWidget {
  const _MicScene();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const CloseButton(),
      title: const Text('VPSTTT IDE'),
      actions: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 16),
          child: Center(
            child: IdeWebMicChip(capturing: ValueNotifier<bool>(true)),
          ),
        ),
      ],
    ),
    body: FakeIdeWebView().build(),
  );
}

class _TileScene extends StatelessWidget {
  const _TileScene();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Công việc')),
    body: ProviderScope(
      overrides: [workHubEnabledProvider.overrideWithValue(false)],
      child: WorkAppsSection(
        workspaceId: 'ws',
        extraApps: [
          WorkAppItem(
            key: const Key('workspace_module_ide_web'),
            icon: Icons.terminal_rounded,
            color: workAppBlue,
            label: 'VPSTTT IDE',
            onTap: () {},
          ),
        ],
      ),
    ),
  );
}
