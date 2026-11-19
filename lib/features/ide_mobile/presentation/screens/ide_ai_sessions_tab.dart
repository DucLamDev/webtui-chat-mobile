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
import '../../data/ide_connection.dart';
import '../../domain/ide_errors.dart';
import '../controllers/ide_controllers.dart';
import '../widgets/ai/ide_new_session_sheet.dart';

/// Nhóm trạng thái phiên AI hiện cho người dùng.
enum IdeSessionState { running, approval, plan, done, stuck, other }

IdeSessionState ideSessionState(String status) {
  final s = status.toLowerCase();
  if (s.contains('plan')) {
    return IdeSessionState.plan;
  }
  return switch (s) {
    'running' || 'working' || 'busy' => IdeSessionState.running,
    'waiting' ||
    'approval' ||
    'pending' ||
    'awaiting_approval' => IdeSessionState.approval,
    'idle' ||
    'done' ||
    'finished' ||
    'completed' ||
    'stopped' => IdeSessionState.done,
    'stuck' || 'error' || 'failed' || 'blocked' => IdeSessionState.stuck,
    _ => IdeSessionState.other,
  };
}

String ideSessionStateLabel(IdeSessionState s, String raw) => switch (s) {
  IdeSessionState.running => tr('Đang làm', 'Working'),
  IdeSessionState.approval => tr('Chờ duyệt', 'Needs approval'),
  IdeSessionState.plan => tr('Kế hoạch chờ duyệt', 'Plan needs approval'),
  IdeSessionState.done => tr('Xong', 'Done'),
  IdeSessionState.stuck => tr('Kẹt', 'Stuck'),
  IdeSessionState.other => raw.isEmpty ? tr('Không rõ', 'Unknown') : raw,
};

Color ideSessionStateColor(IdeSessionState s) => switch (s) {
  IdeSessionState.running => WebTuiColors.primary,
  IdeSessionState.approval || IdeSessionState.plan => WebTuiColors.accentAmber,
  IdeSessionState.done => WebTuiColors.accentGreen,
  IdeSessionState.stuck => WebTuiColors.danger,
  IdeSessionState.other => WebTuiColors.textMuted,
};

String ideTimeAgo(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return tr('vừa xong', 'just now');
  if (d.inMinutes < 60) {
    return tr('${d.inMinutes} phút trước', '${d.inMinutes} min ago');
  }
  if (d.inHours < 24) return tr('${d.inHours} giờ trước', '${d.inHours} h ago');
  return tr('${d.inDays} ngày trước', '${d.inDays} d ago');
}

/// Nhóm theo dự án, giữ thứ tự xuất hiện đầu tiên.
Map<String, List<IdeAiSessionItem>> ideGroupByProject(
  List<IdeAiSessionItem> items,
) {
  final out = <String, List<IdeAiSessionItem>>{};
  for (final i in items) {
    out.putIfAbsent(i.project.isEmpty ? '—' : i.project, () => []).add(i);
  }
  return out;
}

/// Tab AI của IDE: phiên theo dự án, bấm mở, nhấn giữ để dừng, nút "Phiên mới".
class IdeAiSessionsTab extends ConsumerWidget {
  const IdeAiSessionsTab({super.key});

  Future<void> _stop(
    BuildContext context,
    WidgetRef ref,
    IdeAiSessionItem item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Dừng phiên này?', 'Stop this session?'),
      message: item.title.isEmpty ? item.project : item.title,
      confirmLabel: tr('Dừng phiên', 'Stop session'),
      destructive: true,
      icon: Icons.stop_circle_outlined,
    );
    if (!ok) return;
    try {
      await ref.read(ideRpcClientProvider).call('ai.sessions_stop', {
        'session_key': item.key,
      });
      ref.invalidate(ideAiSessionsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Đã dừng phiên', 'Session stopped'))),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is IdeForbidden
                ? tr(
                    'Bạn không có quyền dừng phiên này.',
                    'You cannot stop this session.',
                  )
                : tr(
                    'Chưa dừng được phiên, thử lại.',
                    'Could not stop the session, try again.',
                  ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(
      ideLinkStatusProvider.select((v) => v.valueOrNull?.phase),
    );
    final sessions = ref.watch(ideAiSessionsProvider);
    final Widget body;
    if (phase != IdeLinkPhase.ready) {
      body = WebTuiEmptyState(
        title: tr('Chưa nối IDE', 'IDE not connected'),
        message: tr(
          'Hãy nối điện thoại với IDE trên máy tính để xem phiên AI.',
          'Link this phone to the IDE on your computer to see AI sessions.',
        ),
        icon: Icons.link_off_rounded,
      );
    } else {
      body = sessions.when(
        loading: () => WebTuiLoadingState(
          message: tr('Đang tải phiên AI...', 'Loading AI sessions...'),
        ),
        error: (error, _) => error is IdeForbidden
            ? WebTuiEmptyState(
                title: tr('Không có quyền', 'No permission'),
                message: tr(
                  'Tài khoản này không được xem phiên AI trên IDE.',
                  'This account cannot view AI sessions on the IDE.',
                ),
                icon: Icons.lock_outline_rounded,
              )
            : WebTuiErrorState(
                title: tr(
                  'Không tải được phiên AI',
                  'Could not load AI sessions',
                ),
                message: error is IdeOffline
                    ? tr('IDE vừa mất kết nối.', 'The IDE just disconnected.')
                    : tr('Hãy thử lại.', 'Please try again.'),
                onRetry: () => ref.invalidate(ideAiSessionsProvider),
              ),
        data: (items) => items.isEmpty
            ? WebTuiEmptyState(
                title: tr('Chưa có phiên AI', 'No AI sessions'),
                message: tr(
                  'Bấm "Phiên mới" để bắt đầu một phiên Claude hoặc Codex.',
                  'Tap "New session" to start a Claude or Codex session.',
                ),
                icon: Icons.auto_awesome_rounded,
              )
            : _List(
                items: items,
                onStop: (i) => _stop(context, ref, i),
                onRefresh: () async {
                  ref.invalidate(ideAiSessionsProvider);
                  await ref
                      .read(ideAiSessionsProvider.future)
                      .catchError((_) => <IdeAiSessionItem>[]);
                },
              ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: body,
      floatingActionButton: phase == IdeLinkPhase.ready
          ? FloatingActionButton.extended(
              onPressed: () => showIdeNewSessionSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Phiên mới', 'New session')),
            )
          : null,
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.items,
    required this.onStop,
    required this.onRefresh,
  });

  final List<IdeAiSessionItem> items;
  final void Function(IdeAiSessionItem) onStop;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final groups = ideGroupByProject(items);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (final g in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                WebTuiSpacing.md,
                WebTuiSpacing.lg,
                WebTuiSpacing.xs,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  g.key,
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
            ),
            for (final item in g.value) _Tile(item: item, onStop: onStop),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onStop});

  final IdeAiSessionItem item;
  final void Function(IdeAiSessionItem) onStop;

  @override
  Widget build(BuildContext context) {
    final state = ideSessionState(item.status);
    final label = ideSessionStateLabel(state, item.status);
    final sub = [
      if (item.worktree.isNotEmpty) item.worktree,
      item.kind,
      ideTimeAgo(item.updatedAt),
    ].where((e) => e.isNotEmpty).join(' · ');
    return Semantics(
      onLongPressHint: tr('Dừng phiên', 'Stop session'),
      child: ListTile(
        minVerticalPadding: 10,
        title: Text(
          item.title.isEmpty ? item.project : item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WebTuiStatusPill(
                label: label,
                color: ideSessionStateColor(state),
              ),
              Text(sub, style: WebTuiTypography.bodySmall),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onLongPress: () => onStop(item),
        onTap: () =>
            unawaited(context.push('/ide/ai/${Uri.encodeComponent(item.key)}')),
      ),
    );
  }
}
