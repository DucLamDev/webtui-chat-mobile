import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../data/ide_connection.dart';
import '../../domain/ide_errors.dart';
import '../controllers/ide_controllers.dart';
import '../widgets/ai/ide_new_session_sheet.dart';
import '../widgets/ide_wb.dart';

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
  IdeSessionState.running => IdeWb.accentInk,
  IdeSessionState.approval || IdeSessionState.plan => IdeWb.warn,
  IdeSessionState.done => IdeWb.ok,
  IdeSessionState.stuck => IdeWb.danger,
  IdeSessionState.other => IdeWb.text2,
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
              backgroundColor: IdeWb.accent,
              foregroundColor: Colors.white,
              elevation: 2,
              extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
              icon: const Icon(Icons.edit_square, size: 20),
              label: Text(tr('Phiên mới', 'New session')),
            )
          : null,
    );
  }
}

/// Bộ lọc nhanh của tab AI (thứ tự = thứ tự chip).
enum _Filter { all, needsYou, running, done }

bool _matches(_Filter f, IdeSessionState s) => switch (f) {
  _Filter.all => true,
  _Filter.needsYou =>
    s == IdeSessionState.approval ||
        s == IdeSessionState.plan ||
        s == IdeSessionState.stuck,
  _Filter.running => s == IdeSessionState.running,
  _Filter.done => s == IdeSessionState.done,
};

/// Danh sách phiên kiểu hộp thư: ô tìm, chip lọc (có số đếm), nhóm theo dự án
/// trong thẻ bo góc.
class _List extends StatefulWidget {
  const _List({
    required this.items,
    required this.onStop,
    required this.onRefresh,
  });

  final List<IdeAiSessionItem> items;
  final void Function(IdeAiSessionItem) onStop;
  final Future<void> Function() onRefresh;

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  _Filter _filter = _Filter.all;
  String _query = '';

  int _count(_Filter f) =>
      widget.items.where((i) => _matches(f, ideSessionState(i.status))).length;

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = widget.items.where((i) {
      if (!_matches(_filter, ideSessionState(i.status))) return false;
      if (q.isEmpty) return true;
      return '${i.title} ${i.project} ${i.worktree}'.toLowerCase().contains(q);
    }).toList();
    final groups = ideGroupByProject(shown);
    final chips = [
      WebTuiFilterChipData(label: tr('Tất cả', 'All')),
      WebTuiFilterChipData(
        label: tr('Cần bạn', 'Needs you'),
        count: _count(_Filter.needsYou),
      ),
      WebTuiFilterChipData(
        label: tr('Đang chạy', 'Running'),
        count: _count(_Filter.running),
      ),
      WebTuiFilterChipData(label: tr('Xong', 'Done')),
    ];
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
              WebTuiSpacing.lg,
              0,
            ),
            child: WebTuiSearchBar(
              hintText: tr('Tìm phiên, dự án...', 'Search sessions...'),
              fillColor: IdeWb.chip,
              accentColor: IdeWb.accentInk,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          WebTuiFilterChipBar(
            palette: (
              fill: IdeWb.chip,
              text: IdeWb.text,
              selectedFill: IdeWb.accentSoft,
              selectedText: IdeWb.accentInk,
            ),
            chips: chips,
            selectedIndex: _filter.index,
            onSelected: (i) => setState(() => _filter = _Filter.values[i]),
            semanticLabel: tr('Lọc phiên AI', 'Filter AI sessions'),
          ),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(WebTuiSpacing.xxl),
              child: Text(
                tr('Không có phiên nào khớp.', 'No matching sessions.'),
                textAlign: TextAlign.center,
                style: IdeType.bodyMedium.copyWith(color: IdeWb.text2),
              ),
            ),
          for (final g in groups.entries) ...[
            _GroupHeader(name: g.key, count: g.value.length),
            _GroupCard(
              children: [
                for (final item in g.value)
                  _Tile(item: item, onStop: widget.onStop),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name, required this.count});

  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.xl,
        WebTuiSpacing.lg,
        WebTuiSpacing.xl,
        WebTuiSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 16, color: IdeWb.text2),
            const SizedBox(width: WebTuiSpacing.xs + 2),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IdeType.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: IdeWb.text,
                ),
              ),
            ),
            const SizedBox(width: WebTuiSpacing.xs + 2),
            ExcludeSemantics(
              child: Text(
                '$count',
                style: WebTuiTypography.labelSmall.copyWith(color: IdeWb.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ bo góc chứa các hàng, kẻ mảnh giữa các hàng (thụt theo ảnh đầu hàng).
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: IdeWb.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: IdeWb.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, indent: 64, color: IdeWb.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Ảnh đầu hàng theo loại trợ lý: Claude cam đất, Codex màu chữ, khác xanh.
(IconData, Color) _kindBadge(String kind) => switch (kind.toLowerCase()) {
  'claude' => (Icons.auto_awesome_rounded, const Color(0xFFD97757)),
  'codex' => (Icons.code_rounded, IdeWb.textStrong),
  _ => (Icons.smart_toy_outlined, IdeWb.accentInk),
};

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onStop});

  final IdeAiSessionItem item;
  final void Function(IdeAiSessionItem) onStop;

  @override
  Widget build(BuildContext context) {
    final state = ideSessionState(item.status);
    final label = ideSessionStateLabel(state, item.status);
    final color = ideSessionStateColor(state);
    final (icon, kindColor) = _kindBadge(item.kind);
    final time = ideTimeAgo(item.updatedAt);
    final meta = [
      if (item.kind.isNotEmpty) item.kind,
      if (item.worktree.isNotEmpty) item.worktree,
    ].join(' · ');
    return Semantics(
      onLongPressHint: tr('Dừng phiên', 'Stop session'),
      child: InkWell(
        onLongPress: () => onStop(item),
        onTap: () => unawaited(
          context.push('/ide/ai/${Uri.encodeComponent(item.key)}', extra: item),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.md,
              WebTuiSpacing.md,
              WebTuiSpacing.sm,
              WebTuiSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kindColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: kindColor),
                ),
                const SizedBox(width: WebTuiSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title.isEmpty ? item.project : item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: IdeType.bodyMedium.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: IdeWb.textStrong,
                              ),
                            ),
                          ),
                          if (time.isNotEmpty) ...[
                            const SizedBox(width: WebTuiSpacing.sm),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                time,
                                style: WebTuiTypography.labelSmall.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: IdeWb.text2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: WebTuiSpacing.xs),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: WebTuiSpacing.xs + 2),
                          Text(
                            label,
                            style: IdeType.bodySmall.copyWith(
                              fontWeight: FontWeight.w600,
                              color: IdeWb.text,
                            ),
                          ),
                          if (meta.isNotEmpty) ...[
                            Text(
                              '  ·  ',
                              style: IdeType.bodySmall.copyWith(
                                color: IdeWb.text2,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: IdeType.bodySmall.copyWith(
                                  color: IdeWb.text2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: IdeWb.text2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
