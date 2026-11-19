import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/ide_access.dart';
import '../../data/ide_connection.dart';
import '../../domain/ide_ready.dart';
import '../../domain/ide_term.dart';
import '../controllers/ide_controllers.dart';
import '../widgets/ide_step_sheet.dart';
import 'files/ide_files_tab.dart';
import 'ide_ai_sessions_tab.dart';
import 'terminal/ide_terminal_tab.dart';

enum IdeTab { ai, files, terminal, projects, more }

/// Tab nào hiện: chỉ khi IDE báo có op tương ứng trong `ready.ops`.
List<IdeTab> visibleIdeTabs(IdeReady? ready) {
  if (ready == null) return const [];
  return [
    if (ready.hasOp('ai.sessions')) IdeTab.ai,
    if (ready.hasGroup('files')) IdeTab.files,
    // Quản trị tắt terminal: `term.*` biến mất khỏi ops nhưng vẫn hiện tab để báo.
    if (ready.hasGroup('term') || ideTermDisabled(ready)) IdeTab.terminal,
    if (ready.hasGroup('jobs') || ready.hasGroup('projects')) IdeTab.projects,
    if (ready.hasGroup('devices') || ready.hasGroup('deploy')) IdeTab.more,
  ];
}

class IdeScreen extends ConsumerStatefulWidget {
  const IdeScreen({super.key});

  @override
  ConsumerState<IdeScreen> createState() => _IdeScreenState();
}

class _IdeScreenState extends ConsumerState<IdeScreen>
    with WidgetsBindingObserver {
  IdeTab _tab = IdeTab.ai;
  late final IdeConnection _connection;
  late final IdeStepPresenterLease _lease;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connection = ref.read(ideConnectionProvider);
    _lease = IdeStepPresenterLease(ref.read(ideStepPresenterProvider.notifier));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lease.acquire(context, () => mounted);
      _connection.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lease.release();
    _connection.markInactive();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ở nền quá lâu thì cổng hỏi lại vân tay: chưa xác thực thì chưa nối.
      ref.read(ideAccessControllerProvider).onForeground().then((ok) {
        if (ok && mounted) _connection.markActive();
      });
    } else if (state == AppLifecycleState.paused) {
      _connection.markInactive();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(ideEnabledProvider);
    final credentials = ref.watch(ideCredentialsProvider);
    // Gắn (lại) máy xong khi màn này đang mở: nối lại bằng khoá mới.
    ref.listen(ideCredentialsProvider, (previous, next) {
      final now = next.valueOrNull?.deviceId;
      final before = previous?.valueOrNull?.deviceId;
      if (now != null && now != before && mounted) {
        unawaited(_connection.restartAfterPairing());
      }
    });
    final status = ref.watch(ideLinkStatusProvider).valueOrNull;
    final tabs = visibleIdeTabs(status?.ready);
    if (tabs.isNotEmpty && !tabs.contains(_tab)) _tab = tabs.first;

    final Widget body;
    if (!enabled) {
      body = _Message(
        icon: Icons.block_rounded,
        title: tr('IDE chưa được bật', 'IDE is not enabled'),
        message: tr(
          'Máy chủ này chưa bật IDE hoặc tài khoản không có quyền dùng.',
          'This server has no IDE or your account cannot use it.',
        ),
      );
    } else {
      body = credentials.when(
        loading: () => WebTuiLoadingState(
          message: tr('Đang kiểm tra máy...', 'Checking this device...'),
        ),
        error: (_, _) => WebTuiErrorState(
          title: tr('Không đọc được khoá máy', 'Could not read device key'),
          message: tr('Hãy thử lại.', 'Please try again.'),
          onRetry: () => ref.invalidate(ideCredentialsProvider),
        ),
        data: (creds) {
          if (creds == null) {
            return _Message(
              icon: Icons.phonelink_setup_rounded,
              title: tr('Chưa gắn máy', 'Phone not paired'),
              message: tr(
                'Gắn điện thoại với IDE trên máy tính bằng mã QR.',
                'Pair this phone with the IDE on your computer using a QR code.',
              ),
              action: FilledButton(
                onPressed: () => context.push('/ide/pair'),
                child: Text(tr('Gắn máy', 'Pair')),
              ),
            );
          }
          return _linked(status, tabs);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr('Quay lại', 'Back'),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('IDE'),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: tabs.indexOf(_tab).clamp(0, tabs.length - 1),
              onDestinationSelected: (i) => setState(() => _tab = tabs[i]),
              destinations: [
                for (final t in tabs)
                  NavigationDestination(
                    icon: Icon(_tabIcon(t)),
                    label: _tabLabel(t),
                  ),
              ],
            ),
    );
  }

  Widget _linked(IdeLinkStatus? status, List<IdeTab> tabs) {
    final phase = status?.phase ?? IdeLinkPhase.connecting;
    final Widget content = switch (phase) {
      IdeLinkPhase.revoked => _Message(
        icon: Icons.link_off_rounded,
        title: tr('Máy này đã bị gỡ', 'This phone was removed'),
        message: tr(
          'IDE đã gỡ điện thoại này. Hãy gắn lại bằng mã QR mới.',
          'The IDE removed this phone. Pair again with a new QR code.',
        ),
        action: FilledButton(
          onPressed: () => context.push('/ide/pair'),
          child: Text(tr('Gắn lại', 'Pair again')),
        ),
      ),
      IdeLinkPhase.offline => _Message(
        icon: Icons.cloud_off_rounded,
        title: tr('IDE đang ngoại tuyến', 'IDE is offline'),
        message: tr(
          'Hãy mở IDE trên máy tính và kiểm tra mạng.',
          'Open the IDE on your computer and check the network.',
        ),
        action: OutlinedButton(
          onPressed: _connection.retryNow,
          child: Text(tr('Thử lại', 'Retry')),
        ),
      ),
      IdeLinkPhase.ready when tabs.isEmpty => _Message(
        icon: Icons.construction_rounded,
        title: tr('IDE chưa có chức năng', 'IDE has no features yet'),
        message: tr(
          'Bản IDE trên máy tính chưa hỗ trợ điện thoại. Hãy cập nhật IDE.',
          'The desktop IDE does not support phones yet. Update the IDE.',
        ),
      ),
      IdeLinkPhase.ready => switch (_tab) {
        IdeTab.ai => const IdeAiSessionsTab(),
        IdeTab.files => const IdeFilesTab(),
        IdeTab.terminal => const IdeTerminalTab(),
        _ => _Message(
          icon: Icons.hourglass_empty_rounded,
          title: tr('Sắp có', 'Coming soon'),
          message: tr(
            'Chức năng này đang được hoàn thiện.',
            'This feature is being finished.',
          ),
        ),
      },
      IdeLinkPhase.idle when status?.reason == 'unauthorized' => _Message(
        icon: Icons.key_off_rounded,
        title: tr('IDE từ chối khoá máy', 'The IDE rejected this phone'),
        message: tr(
          'Thử lại; vẫn lỗi thì gắn lại bằng mã QR mới.',
          'Try again; if it keeps failing, pair again with a new QR code.',
        ),
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton(
              onPressed: _connection.retryNow,
              child: Text(tr('Thử lại', 'Retry')),
            ),
            FilledButton(
              onPressed: () => context.push('/ide/pair'),
              child: Text(tr('Gắn lại', 'Pair again')),
            ),
          ],
        ),
      ),
      IdeLinkPhase.idle when status?.reason != null => _Message(
        icon: Icons.pause_circle_outline_rounded,
        title: tr('Đã ngắt vì lâu không dùng', 'Disconnected after being idle'),
        message: tr('Bấm để nối lại với IDE.', 'Tap to reconnect to the IDE.'),
        action: FilledButton(
          onPressed: _connection.retryNow,
          child: Text(tr('Nối lại', 'Reconnect')),
        ),
      ),
      _ => WebTuiLoadingState(
        message: phase == IdeLinkPhase.reconnecting
            ? tr('Đang nối lại...', 'Reconnecting...')
            : tr('Đang kết nối IDE...', 'Connecting to the IDE...'),
      ),
    };
    return Column(
      children: [
        _StatusBar(phase: phase),
        Expanded(child: content),
      ],
    );
  }
}

IconData _tabIcon(IdeTab t) => switch (t) {
  IdeTab.ai => Icons.auto_awesome_rounded,
  IdeTab.files => Icons.folder_outlined,
  IdeTab.terminal => Icons.terminal_rounded,
  IdeTab.projects => Icons.account_tree_outlined,
  IdeTab.more => Icons.more_horiz_rounded,
};

String _tabLabel(IdeTab t) => switch (t) {
  IdeTab.ai => 'AI',
  IdeTab.files => tr('Tệp', 'Files'),
  IdeTab.terminal => 'Terminal',
  IdeTab.projects => tr('Dự án', 'Projects'),
  IdeTab.more => tr('Thêm', 'More'),
};

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.phase});

  final IdeLinkPhase phase;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (phase) {
      IdeLinkPhase.ready => (
        tr('Đã kết nối IDE', 'Connected to the IDE'),
        WebTuiColors.accentGreen,
      ),
      IdeLinkPhase.offline => (
        tr('IDE ngoại tuyến', 'IDE offline'),
        WebTuiColors.accentAmber,
      ),
      IdeLinkPhase.revoked => (tr('Đã bị gỡ', 'Removed'), WebTuiColors.danger),
      IdeLinkPhase.reconnecting => (
        tr('Đang nối lại', 'Reconnecting'),
        WebTuiColors.accentAmber,
      ),
      _ => (tr('Đang kết nối', 'Connecting'), WebTuiColors.textMuted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.lg,
        vertical: WebTuiSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: WebTuiSpacing.sm),
          Text(
            label,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WebTuiSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: WebTuiColors.textMuted),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: WebTuiTypography.titleMedium,
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: WebTuiSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
