import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_mergeq.dart';
import '../../../domain/ide_visible_text.dart';
import '../../controllers/ide_controllers.dart';
import '../../controllers/ide_project_ops_controllers.dart';
import '../../widgets/ide_step_sheet.dart';
import '../../widgets/markdown/ide_code_block.dart';
import '../../widgets/projects/ide_project_ui.dart';

String ideMergeModeLabel(String mode) => switch (mode) {
  'day-du' => tr('Đầy đủ', 'Full review'),
  'hang-cho' => tr('Chỉ hàng chờ', 'Queue only'),
  'tat' => tr('Tắt', 'Off'),
  _ => mode,
};

String ideMergeResultLabel(String r) => switch (r) {
  'da-gop' => tr('Đã gộp', 'Merged'),
  'tra-ve' => tr('Bị trả về', 'Returned'),
  'rut' => tr('Đã rút', 'Withdrawn'),
  'da-dong' => tr('Đã đóng', 'Closed'),
  'trien-khai' => tr('Đã triển khai', 'Deployed'),
  ideMergeResultDeployFailed => tr('Triển khai lỗi', 'Deploy failed'),
  'khan-cap' => tr('Khẩn cấp', 'Urgent'),
  'doi-muc' => tr('Đổi chế độ', 'Mode change'),
  _ => r,
};

String ideMergeStateLabel(String s) => switch (s) {
  'duyet' => tr('Đang duyệt', 'In review'),
  'cho' => tr('Đang chờ', 'Waiting'),
  'gop' => tr('Đang gộp', 'Merging'),
  _ => s,
};

Color ideMergeResultColor(String r) => switch (r) {
  'da-gop' || 'trien-khai' => WebTuiColors.accentGreen,
  'tra-ve' || ideMergeResultDeployFailed => WebTuiColors.danger,
  'khan-cap' => WebTuiColors.accentAmber,
  _ => WebTuiColors.textMuted,
};

/// Hàng chờ gộp: của dự án (`project`) hoặc của tôi (không `project`).
/// Tự tải lại mỗi 10 giây khi đang mở; `pr` được nhấn mạnh và cuộn tới.
class IdeMergeqScreen extends ConsumerStatefulWidget {
  const IdeMergeqScreen({
    this.project,
    this.pr,
    this.refreshInterval = const Duration(seconds: 10),
    super.key,
  });

  final String? project;
  final int? pr;
  final Duration refreshInterval;

  @override
  ConsumerState<IdeMergeqScreen> createState() => _MergeqState();
}

class _MergeqState extends ConsumerState<IdeMergeqScreen> {
  late final IdeStepPresenterLease _lease;
  Timer? _timer;
  AppLifecycleListener? _life;
  bool _loading = true;
  Object? _error;
  IdeMergeView? _view;
  List<IdeMergeMineGroup> _mine = const [];
  bool _reloading = false;
  bool _acting = false;
  bool _scrolled = false;
  final _prKey = GlobalKey();
  bool _prKeyUsed = false;

  Key _cardKey(bool highlighted, String name) {
    if (highlighted && !_prKeyUsed) {
      _prKeyUsed = true;
      return _prKey;
    }
    return Key(name);
  }

  bool get _isMine => widget.project == null || widget.project!.isEmpty;

  bool _has(String op) =>
      ref.read(ideLinkStatusProvider).valueOrNull?.ready?.hasOp(op) ?? false;

  @override
  void initState() {
    super.initState();
    _lease = IdeStepPresenterLease(ref.read(ideStepPresenterProvider.notifier));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lease.acquire(context, () => mounted);
    });
    unawaited(_load());
    _life = AppLifecycleListener(
      onStateChange: (st) {
        if (st == AppLifecycleState.resumed && mounted && _timer != null) {
          _tick();
        }
      },
    );
    _timer = Timer.periodic(widget.refreshInterval, (_) => _tick());
  }

  bool get _active {
    final st = WidgetsBinding.instance.lifecycleState;
    if (st != null && st != AppLifecycleState.resumed) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  /// Không hỏi máy khi app ở nền hoặc màn bị che; quay về thì tải lại.
  void _tick() {
    if (!mounted) return;
    if (!_active) return;
    unawaited(_load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _life?.dispose();
    _lease.release();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_reloading) return;
    _reloading = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final svc = ref.read(ideProjectServiceProvider);
      if (_isMine) {
        final g = await svc.mergeMine();
        if (!mounted) return;
        setState(() {
          _mine = g;
          _loading = false;
          _error = null;
        });
      } else {
        final v = await svc.mergeView(widget.project!);
        if (!mounted) return;
        setState(() {
          _view = v;
          _loading = false;
          _error = null;
        });
        _scrollToPr();
      }
    } on Object catch (e) {
      // Bị tắt quyền thì thôi hỏi lại.
      if (e is IdeForbidden) {
        _timer?.cancel();
        _timer = null;
        if (mounted) {
          setState(() {
            _loading = false;
            _error = e;
          });
        }
        return;
      }
      // Lần tự tải lại thất bại thì giữ dữ liệu cũ.
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    } finally {
      _reloading = false;
    }
  }

  void _scrollToPr() {
    if (_scrolled || widget.pr == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _prKey.currentContext;
      if (ctx == null || _scrolled) return;
      _scrolled = true;
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.2,
        ),
      );
    });
  }

  Future<void> _withdraw(IdeMergeEntry e) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final name = ideVisibleText(widget.project!);
      final ok = await showWebTuiConfirmDialog(
        context,
        title: tr('Rút PR #${e.number}?', 'Withdraw PR #${e.number}?'),
        message: tr(
          'PR #${e.number} của dự án $name sẽ rời hàng chờ. Cần xác nhận bằng vân tay.',
          'PR #${e.number} of project $name leaves the queue. Needs fingerprint.',
        ),
        confirmLabel: tr('Rút PR', 'Withdraw'),
        cancelLabel: tr('Giữ lại', 'Keep'),
        destructive: true,
        icon: Icons.undo_rounded,
      );
      if (!ok || !mounted) return;
      final done = await ideProjectGuard(context, () async {
        await ref
            .read(ideProjectServiceProvider)
            .withdraw(widget.project!, e.number);
        return true;
      });
      if (done == true && mounted) {
        ideProjectSnack(context, tr('Đã rút PR', 'PR withdrawn'));
        await _load(silent: true);
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _changeMode(String mode) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final name = ideVisibleText(widget.project!);
      final ok = await showWebTuiConfirmDialog(
        context,
        title: tr('Đổi chế độ duyệt?', 'Change review mode?'),
        message: tr(
          'Dự án $name sẽ chuyển sang chế độ "${ideMergeModeLabel(mode)}".',
          'Project $name will switch to "${ideMergeModeLabel(mode)}".',
        ),
        confirmLabel: tr('Đổi', 'Change'),
        cancelLabel: tr('Huỷ', 'Cancel'),
      );
      if (!ok || !mounted) return;
      final done = await ideProjectGuard(context, () async {
        await ref
            .read(ideProjectServiceProvider)
            .setMergeMode(widget.project!, mode);
        return true;
      });
      if (done == true && mounted) await _load(silent: true);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _showLog(IdeMergeRecent r) {
    return showWebTuiSheet<void>(
      context: context,
      builder: (_) => _LogSheet(project: widget.project!, recent: r),
    );
  }

  Future<void> _showLight() {
    return showWebTuiSheet<void>(
      context: context,
      builder: (_) => _LightSheet(
        project: widget.project!,
        canClear: (_view?.canLight ?? false) && _has('mergeq.light_clear'),
        onChanged: () => _load(silent: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(ideLinkStatusProvider); // giữ nguồn trạng thái sống
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isMine
              ? tr('Hàng chờ của tôi', 'My merge queue')
              : '${tr('Hàng chờ gộp', 'Merge queue')} · ${ideVisibleText(widget.project!)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return WebTuiLoadingState(
        message: tr('Đang tải hàng chờ...', 'Loading the queue...'),
      );
    }
    final error = _error;
    if (error != null) {
      return ideProjectErrorView(
        error,
        title: tr('Không tải được hàng chờ', 'Could not load the queue'),
        onRetry: _load,
      );
    }
    _prKeyUsed = false;
    if (_isMine) return _mineBody();
    final v = _view ?? const IdeMergeView();
    final empty = v.queue.isEmpty && v.recent.isEmpty;
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, WebTuiSpacing.md, 0, 96),
        children: [
          _modeCard(v),
          if (_has('mergeq.light_list') && (v.lightCount > 0 || v.canLight))
            IdeProjectCard(
              child: InkWell(
                key: const Key('ide_mergeq_light'),
                onTap: _showLight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, size: 20),
                      const SizedBox(width: WebTuiSpacing.sm),
                      Expanded(
                        child: Text(
                          '${tr('Việc nhẹ', 'Light jobs')} (${v.lightCount})',
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            ),
          if (empty)
            SizedBox(
              height: 240,
              child: WebTuiEmptyState(
                key: const Key('ide_mergeq_empty'),
                title: tr('Hàng chờ trống', 'The queue is empty'),
                message: tr(
                  'Chưa có PR nào đang chờ hoặc vừa gộp.',
                  'No PR is waiting or was merged recently.',
                ),
                icon: Icons.queue_rounded,
              ),
            ),
          if (v.queue.isNotEmpty) ...[
            WebTuiSectionLabel(tr('Đang chờ', 'Waiting')),
            for (final e in v.queue) _entryCard(e),
          ],
          if (v.recent.isNotEmpty) ...[
            WebTuiSectionLabel(tr('Gần đây', 'Recent')),
            for (final r in v.recent) _recentCard(r),
          ],
        ],
      ),
    );
  }

  Widget _modeCard(IdeMergeView v) {
    return IdeProjectCard(
      title: tr('Chế độ duyệt', 'Review mode'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            v.modeName.isNotEmpty ? v.modeName : ideMergeModeLabel(v.mode),
            key: const Key('ide_mergeq_mode'),
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
          if (v.canChangeMode && _has('mergeq.mode')) ...[
            const SizedBox(height: WebTuiSpacing.sm),
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.sm,
              children: [
                for (final m in {v.mode, ...v.changeableModes})
                  if (ideMergeModeKey(m) != null)
                    ChoiceChip(
                      key: Key('ide_mergeq_mode_$m'),
                      label: Text(ideMergeModeLabel(m)),
                      selected: m == v.mode,
                      // Không để null: chip đang chọn sẽ bị vẽ như nút bị khoá.
                      onSelected: (_) {
                        if (m != v.mode) _changeMode(m);
                      },
                    ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: Text(
                tr(
                  'Chỉ trưởng / phó dự án đổi được.',
                  'Only leads can change it.',
                ),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _entryCard(IdeMergeEntry e, {bool allowWithdraw = true}) {
    final hi = widget.pr == e.number;
    return Container(
      key: _cardKey(hi, 'ide_mergeq_entry_${e.number}'),
      margin: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        0,
        WebTuiSpacing.lg,
        WebTuiSpacing.sm,
      ),
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: hi ? WebTuiColors.primarySoft : WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(
          color: hi ? WebTuiColors.primary : WebTuiColors.border,
          width: hi ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${e.number} ${ideVisibleText(e.title)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
              WebTuiStatusPill(label: ideMergeStateLabel(e.state)),
            ],
          ),
          Text(
            [
              ideVisibleText(e.branch),
              ideVisibleText(e.by),
              ideFormatUnix(e.joinedAt),
            ].where((s) => s.isNotEmpty).join(' · '),
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textMuted,
            ),
          ),
          if (e.step.isNotEmpty || e.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: Text(
                [e.step, e.note]
                    .where((s) => s.isNotEmpty)
                    .map(ideVisibleText)
                    .join(' · '),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ),
          if (allowWithdraw && e.withdrawable && _has('mergeq.withdraw'))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('ide_mergeq_withdraw_${e.number}'),
                onPressed: _acting ? null : () => _withdraw(e),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: Text(tr('Rút PR', 'Withdraw')),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: WebTuiColors.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _recentCard(IdeMergeRecent r, {bool allowLog = true}) {
    final hi = widget.pr == r.number;
    return Container(
      key: _cardKey(hi, 'ide_mergeq_recent_${r.number}'),
      margin: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        0,
        WebTuiSpacing.lg,
        WebTuiSpacing.sm,
      ),
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: hi ? WebTuiColors.primarySoft : WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(
          color: hi ? WebTuiColors.primary : WebTuiColors.border,
          width: hi ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${r.number} ${ideVisibleText(r.title)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
              WebTuiStatusPill(
                label: ideMergeResultLabel(r.result),
                color: ideMergeResultColor(r.result),
              ),
            ],
          ),
          Text(
            [
              ideVisibleText(r.branch),
              ideVisibleText(r.by),
              ideFormatUnix(r.closedAt),
            ].where((s) => s.isNotEmpty).join(' · '),
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textMuted,
            ),
          ),
          if (r.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: Text(
                ideVisibleText(r.note),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ),
          if (allowLog && r.rejected && _has('mergeq.log'))
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('ide_mergeq_log_${r.number}'),
                onPressed: () => _showLog(r),
                icon: const Icon(Icons.article_outlined, size: 18),
                label: Text(tr('Xem nhật ký', 'View log')),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mineBody() {
    final entries = [for (final g in _mine) ...g.entries];
    final recents = [for (final g in _mine) ...g.recent];
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _mine.isEmpty || (entries.isEmpty && recents.isEmpty)
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 360,
                  child: WebTuiEmptyState(
                    key: const Key('ide_mergeq_empty'),
                    title: tr('Chưa có PR nào của bạn', 'No PRs of yours'),
                    message: tr(
                      'PR bạn xếp vào hàng chờ sẽ hiện ở đây.',
                      'PRs you queue will show here.',
                    ),
                    icon: Icons.queue_rounded,
                  ),
                ),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
              children: [
                for (final g in _mine)
                  if (g.entries.isNotEmpty || g.recent.isNotEmpty) ...[
                    WebTuiSectionLabel(g.queue),
                    for (final e in g.entries)
                      _entryCard(e, allowWithdraw: false),
                    for (final r in g.recent) _recentCard(r, allowLog: false),
                  ],
              ],
            ),
    );
  }
}

class _LogSheet extends ConsumerStatefulWidget {
  const _LogSheet({required this.project, required this.recent});

  final String project;
  final IdeMergeRecent recent;

  @override
  ConsumerState<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<_LogSheet> {
  bool _loading = true;
  Object? _error;
  String _text = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await ref
          .read(ideProjectServiceProvider)
          .mergeLog(widget.project, widget.recent.number);
      if (mounted) {
        setState(() {
          _text = t;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = WebTuiLoadingState(
        message: tr('Đang tải nhật ký...', 'Loading the log...'),
      );
    } else if (_error != null) {
      body = ideProjectErrorView(_error!, onRetry: _load);
    } else if (_text.trim().isEmpty) {
      body = WebTuiEmptyState(
        key: const Key('ide_mergeq_log_empty'),
        title: tr('Chưa có nhật ký', 'No log yet'),
        message: tr(
          'PR này chưa ghi lý do bị trả về.',
          'No reason was recorded for this PR.',
        ),
        icon: Icons.article_outlined,
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        child: SelectableText(
          _text,
          key: const Key('ide_mergeq_log_text'),
          style: ideMonoStyle.copyWith(color: WebTuiColors.textPrimary),
        ),
      );
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          WebTuiSheetHeader(
            title: tr(
              'Nhật ký PR #${widget.recent.number}',
              'PR #${widget.recent.number} log',
            ),
            subtitle: ideMergeResultLabel(widget.recent.result),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _LightSheet extends ConsumerStatefulWidget {
  const _LightSheet({
    required this.project,
    required this.canClear,
    required this.onChanged,
  });

  final String project;
  final bool canClear;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_LightSheet> createState() => _LightSheetState();
}

class _LightSheetState extends ConsumerState<_LightSheet> {
  bool _loading = true;
  Object? _error;
  List<IdeLightItem> _items = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await ref
          .read(ideProjectServiceProvider)
          .lightList(widget.project);
      if (mounted) {
        setState(() {
          _items = l;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _clear({String? code, String? label}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final yes = code == null
          ? await showWebTuiConfirmDialog(
              context,
              title: tr('Xoá hết việc nhẹ?', 'Clear all light jobs?'),
              message: tr(
                'Tất cả việc nhẹ của dự án sẽ bị xoá.',
                'All light jobs of the project will be cleared.',
              ),
              confirmLabel: tr('Xoá hết', 'Clear all'),
              cancelLabel: tr('Giữ lại', 'Keep'),
              destructive: true,
              icon: Icons.delete_sweep_rounded,
            )
          : await showWebTuiConfirmDialog(
              context,
              title: tr('Xong việc này?', 'Clear this job?'),
              message: tr(
                'Việc "${label ?? code}" sẽ bị xoá khỏi danh sách việc nhẹ.',
                'The job "${label ?? code}" will be removed from the light jobs.',
              ),
              confirmLabel: tr('Xong việc', 'Clear'),
              cancelLabel: tr('Giữ lại', 'Keep'),
              icon: Icons.done_rounded,
            );
      if (!yes || !mounted) return;
      final ok = await ideProjectGuard(context, () async {
        await ref
            .read(ideProjectServiceProvider)
            .lightClear(widget.project, code: code);
        return true;
      });
      if (ok == true && mounted) {
        await _load();
        unawaited(widget.onChanged());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = WebTuiLoadingState(
        message: tr('Đang tải việc nhẹ...', 'Loading light jobs...'),
      );
    } else if (_error != null) {
      body = ideProjectErrorView(_error!, onRetry: _load);
    } else if (_items.isEmpty) {
      body = WebTuiEmptyState(
        key: const Key('ide_light_empty'),
        title: tr('Không có việc nhẹ', 'No light jobs'),
        message: tr('Chưa có việc nào cần dọn.', 'Nothing to clear.'),
        icon: Icons.bolt_rounded,
      );
    } else {
      body = ListView(
        children: [
          for (final i in _items)
            ListTile(
              key: Key('ide_light_${i.code}'),
              minTileHeight: 56,
              title: Text(
                ideVisibleText(i.title.isEmpty ? i.content : i.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (i.number > 0) '#${i.number}',
                  ideVisibleText(i.branch),
                  ideVisibleText(i.by),
                  ideFormatUnix(i.at),
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
              trailing: widget.canClear
                  ? IconButton(
                      key: Key('ide_light_clear_${i.code}'),
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      onPressed: _busy
                          ? null
                          : () => _clear(
                              code: i.code,
                              label: ideVisibleText(
                                i.title.isEmpty ? i.content : i.title,
                              ),
                            ),
                      icon: const Icon(Icons.done_rounded),
                      tooltip: tr('Xong việc này', 'Clear'),
                    )
                  : null,
            ),
        ],
      );
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          WebTuiSheetHeader(
            title: tr('Việc nhẹ', 'Light jobs'),
            trailing: widget.canClear && _items.isNotEmpty
                ? TextButton(
                    key: const Key('ide_light_clear_all'),
                    onPressed: _busy ? null : () => _clear(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(tr('Xoá hết', 'Clear all')),
                  )
                : null,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
