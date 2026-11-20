import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/ide_access.dart';
import '../../data/ide_connection.dart';
import '../../domain/ide_ready.dart';
import '../../domain/ide_term.dart';
import '../controllers/ide_controllers.dart';
import '../widgets/ide_step_sheet.dart';
import '../widgets/ide_wb.dart';
import 'files/ide_files_tab.dart';
import 'ide_ai_sessions_tab.dart';
import 'more/ide_more_tab.dart';
import 'projects/ide_projects_tab.dart';
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
    // Tab Dự án đọc `projects.list` trước tiên: thiếu op đó thì không hiện.
    if (ready.hasOp('projects.list')) IdeTab.projects,
    if (ideMoreVisibleKeys(ready).isNotEmpty) IdeTab.more,
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

    final phase = enabled && credentials.valueOrNull != null
        ? (status?.phase ?? IdeLinkPhase.connecting)
        : null;
    final ready = phase == IdeLinkPhase.ready;
    // Bố cục như IDE web: thanh biểu tượng trên (đổi chức năng), vùng làm việc
    // ở giữa, thanh trạng thái dưới (kết nối, phiên bản IDE).
    return Scaffold(
      backgroundColor: IdeWb.bg,
      body: Column(
        children: [
          _ActivityBar(
            tabs: ready && tabs.length > 1 ? tabs : const [],
            current: _tab,
            onBack: () => context.canPop() ? context.pop() : context.go('/'),
            onSelect: (t) => setState(() => _tab = t),
          ),
          Expanded(child: SafeArea(top: false, bottom: false, child: body)),
          _StatusBar(phase: phase, version: status?.ready?.ideVersion ?? ''),
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
        IdeTab.projects => const IdeProjectsTab(),
        IdeTab.more => const IdeMoreTab(),
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
    return content;
  }
}

IconData _tabIcon(IdeTab t) => switch (t) {
  IdeTab.ai => Icons.chat_bubble_outline_rounded,
  IdeTab.files => Icons.folder_open_outlined,
  IdeTab.terminal => Icons.terminal_rounded,
  IdeTab.projects => Icons.account_tree_outlined,
  IdeTab.more => Icons.apps_rounded,
};

String _tabLabel(IdeTab t) => switch (t) {
  IdeTab.ai => 'AI',
  IdeTab.files => tr('Tệp', 'Files'),
  IdeTab.terminal => 'Terminal',
  IdeTab.projects => tr('Dự án', 'Projects'),
  IdeTab.more => tr('Thêm', 'More'),
};

/// Thanh biểu tượng trên cùng (như thanh hoạt động của IDE web): nút quay lại
/// rồi một biểu tượng cho mỗi chức năng; mục đang mở có gạch tím dưới chân.
class _ActivityBar extends StatelessWidget {
  const _ActivityBar({
    required this.tabs,
    required this.current,
    required this.onBack,
    required this.onSelect,
  });

  final List<IdeTab> tabs;
  final IdeTab current;
  final VoidCallback onBack;
  final ValueChanged<IdeTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IdeWb.bar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: IdeWb.border)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  key: const Key('ide_back'),
                  tooltip: tr('Quay lại', 'Back'),
                  onPressed: onBack,
                  color: IdeWb.text,
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                ),
                if (tabs.isEmpty)
                  Text(
                    'IDE',
                    style: IdeType.titleMedium.copyWith(
                      color: IdeWb.textStrong,
                    ),
                  ),
                for (final t in tabs)
                  Expanded(
                    child: _ActivityButton(
                      tab: t,
                      selected: t == current,
                      onTap: () => onSelect(t),
                    ),
                  ),
                if (tabs.isNotEmpty) const SizedBox(width: WebTuiSpacing.xs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityButton extends StatelessWidget {
  const _ActivityButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final IdeTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = _tabLabel(tab);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: Key('ide_tab_${tab.name}'),
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                _tabIcon(tab),
                size: 22,
                color: selected ? IdeWb.textStrong : IdeWb.text2,
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 2,
                  decoration: BoxDecoration(
                    color: selected ? IdeWb.accentInk : Colors.transparent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thanh trạng thái dưới cùng (như IDE web): ô tím trạng thái kết nối bên
/// trái, phiên bản IDE và ngôn ngữ bên phải.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.phase, required this.version});

  /// null: chưa gắn máy / IDE chưa bật.
  final IdeLinkPhase? phase;
  final String version;

  @override
  Widget build(BuildContext context) {
    final p = phase;
    final (label, dot) = switch (p) {
      null => (tr('Chưa kết nối', 'Not connected'), Colors.white70),
      IdeLinkPhase.ready => (
        tr('Đã kết nối', 'Connected'),
        const Color(0xFF7EE2A8),
      ),
      IdeLinkPhase.offline => (
        tr('IDE ngoại tuyến', 'IDE offline'),
        const Color(0xFFFFD27A),
      ),
      IdeLinkPhase.revoked => (
        tr('Đã bị gỡ', 'Removed'),
        const Color(0xFFFF9C9C),
      ),
      IdeLinkPhase.reconnecting => (
        tr('Đang nối lại', 'Reconnecting'),
        const Color(0xFFFFD27A),
      ),
      _ => (tr('Đang kết nối', 'Connecting'), Colors.white70),
    };
    final style = WebTuiTypography.labelSmall.copyWith(
      fontWeight: FontWeight.w500,
      color: IdeWb.text,
      height: 1.2,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: IdeWb.bar,
        border: Border(top: BorderSide(color: IdeWb.border)),
      ),
      child: SafeArea(
        top: false,
        // Lề ngang: trên điện thoại góc màn hình bo tròn, sát mép sẽ bị cắt.
        minimum: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Semantics(
                key: const Key('ide_link_status'),
                label: tr('Trạng thái IDE: $label', 'IDE status: $label'),
                excludeSemantics: true,
                child: Container(
                  // Tối thiểu 20, chữ máy to thì cao theo chữ.
                  constraints: const BoxConstraints(minHeight: 20),
                  decoration: BoxDecoration(
                    color: IdeWb.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: WebTuiSpacing.sm,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        maxLines: 1,
                        style: style.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (version.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WebTuiSpacing.sm,
                  ),
                  child: Text(
                    'IDE v$version',
                    maxLines: 1,
                    style: style.copyWith(
                      fontFamily: WebTuiTypography.monoFamily,
                    ),
                  ),
                ),
              Text(tr('VI', 'EN'), style: style),
            ],
          ),
        ),
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
            Icon(icon, size: 40, color: IdeWb.text2),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: IdeType.titleMedium,
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: IdeType.bodyMedium.copyWith(color: IdeWb.text),
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
