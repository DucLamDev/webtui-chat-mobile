import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_term_gate.dart';
import '../../../data/ide_connection.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_term.dart';
import '../../controllers/ide_controllers.dart';
import '../../controllers/ide_term_controllers.dart';
import '../../widgets/ide_wb.dart';
import '../../widgets/terminal/ide_term_new_sheet.dart';
import 'ide_terminal_screen.dart';

String ideTermKindLabel(String cmd) {
  if (cmd.startsWith('my-ssh:')) {
    return tr(
      'SSH máy của tôi: ${cmd.substring(7)}',
      'My SSH: ${cmd.substring(7)}',
    );
  }
  if (cmd.startsWith('ssh:')) {
    return tr('SSH: ${cmd.substring(4)}', 'SSH: ${cmd.substring(4)}');
  }
  return switch (cmd) {
    'claude' => 'Claude',
    'codex' => 'Codex',
    _ => 'Shell',
  };
}

/// Hỏi vân tay rồi mở màn terminal. `false` khi huỷ / không có sinh trắc.
Future<bool> openIdeTerminal(
  BuildContext context,
  WidgetRef ref,
  IdeTermOpenTarget target, {
  String title = '',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final auth = await askTermFingerprint(
    ref.read(ideDeviceSecurityProvider),
    reason: tr('Mở terminal trên IDE', 'Open a terminal on the IDE'),
  );
  if (auth != IdeTermAuth.ok) {
    if (auth == IdeTermAuth.unavailable) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Cần đặt vân tay hoặc khoá màn hình để mở terminal.',
              'Set up a fingerprint or screen lock to open a terminal.',
            ),
          ),
        ),
      );
    }
    return false;
  }
  await navigator.push<void>(
    IdePageRoute(
      builder: (_) => IdeTerminalScreen(target: target, title: title),
    ),
  );
  ref.invalidate(ideTermListProvider);
  return true;
}

/// Tab Terminal của IDE: các phiên đang chạy và "Terminal mới".
class IdeTerminalTab extends ConsumerWidget {
  const IdeTerminalTab({super.key});

  Future<void> _kill(
    BuildContext context,
    WidgetRef ref,
    IdeTermItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Kết thúc phiên này?', 'End this session?'),
      message: tr(
        '${item.name} sẽ bị tắt, chương trình đang chạy trong đó dừng hẳn.',
        '${item.name} will be closed and everything running in it stops.',
      ),
      confirmLabel: tr('Kết thúc phiên', 'End session'),
      destructive: true,
      icon: Icons.stop_circle_outlined,
    );
    if (!ok) return;
    try {
      await ref.read(ideRpcClientProvider).call('term.kill', {
        'name': item.name,
      });
      ref.invalidate(ideTermListProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Đã kết thúc phiên', 'Session ended'))),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is IdeForbidden
                ? tr(
                    'Bạn không có quyền kết thúc phiên này.',
                    'You cannot end this session.',
                  )
                : tr(
                    'Chưa kết thúc được phiên, thử lại.',
                    'Could not end the session, try again.',
                  ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ideLinkStatusProvider).valueOrNull;
    final phase = status?.phase;
    if (ideTermDisabled(status?.ready)) {
      return WebTuiEmptyState(
        key: const Key('term_disabled'),
        title: tr(
          'Quản trị đã tắt terminal trên điện thoại.',
          'The admin turned terminal off on phones.',
        ),
        message: tr(
          'Hãy dùng terminal trên máy tính.',
          'Use the terminal on your computer.',
        ),
        icon: Icons.terminal_rounded,
      );
    }
    final list = ref.watch(ideTermListProvider);
    final Widget body;
    if (phase != IdeLinkPhase.ready) {
      body = WebTuiEmptyState(
        title: tr('Chưa nối IDE', 'IDE not connected'),
        message: tr(
          'Hãy nối điện thoại với IDE trên máy tính để xem terminal.',
          'Link this phone to the IDE on your computer to see terminals.',
        ),
        icon: Icons.link_off_rounded,
      );
    } else {
      body = list.when(
        loading: () => WebTuiLoadingState(
          message: tr('Đang tải terminal...', 'Loading terminals...'),
        ),
        error: (error, _) => error is IdeForbidden
            ? WebTuiEmptyState(
                key: const Key('term_disabled'),
                title: tr(
                  'Quản trị đã tắt terminal trên điện thoại.',
                  'The admin turned terminal off on phones.',
                ),
                message: tr(
                  'Hãy dùng terminal trên máy tính.',
                  'Use the terminal on your computer.',
                ),
                icon: Icons.terminal_rounded,
              )
            : WebTuiErrorState(
                title: tr(
                  'Không tải được terminal',
                  'Could not load terminals',
                ),
                message: error is IdeOffline
                    ? tr('IDE vừa mất kết nối.', 'The IDE just disconnected.')
                    : tr('Hãy thử lại.', 'Please try again.'),
                onRetry: () => ref.invalidate(ideTermListProvider),
              ),
        data: (items) => items.isEmpty
            ? Align(
                alignment: Alignment.topCenter,
                child: WebTuiEmptyState(
                  title: tr('Chưa có terminal', 'No terminals'),
                  message: tr(
                    'Bấm "Terminal mới" để mở một phiên.',
                    'Tap "New terminal" to start one.',
                  ),
                  icon: Icons.terminal_rounded,
                ),
              )
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(ideTermListProvider);
                  await ref
                      .read(ideTermListProvider.future)
                      .catchError((_) => <IdeTermItem>[]);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (final item in items)
                      _Tile(
                        item: item,
                        onOpen: () => unawaited(
                          openIdeTerminal(
                            context,
                            ref,
                            IdeTermOpenTarget.existing(item.name),
                            title: item.name,
                          ),
                        ),
                        onKill: () => _kill(context, ref, item),
                      ),
                  ],
                ),
              ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: body,
      floatingActionButton: phase == IdeLinkPhase.ready
          ? FloatingActionButton.extended(
              key: const Key('term_new'),
              onPressed: () => showIdeTermNewSheet(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Terminal mới', 'New terminal')),
            )
          : null,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onOpen, required this.onKill});

  final IdeTermItem item;
  final VoidCallback onOpen;
  final VoidCallback onKill;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      onLongPressHint: tr('Kết thúc phiên', 'End session'),
      child: ListTile(
        minVerticalPadding: 10,
        leading: Icon(Icons.terminal_rounded, color: IdeWb.accentInk),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.attached)
                WebTuiStatusPill(
                  label: tr('Máy khác đang gắn', 'Attached elsewhere'),
                  color: IdeWb.warn,
                ),
              Text(
                [
                  if (item.project.isNotEmpty) item.project,
                  ideTermKindLabel(item.cmd),
                ].join(' · '),
                style: IdeType.bodySmall,
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onOpen,
        onLongPress: onKill,
      ),
    );
  }
}
