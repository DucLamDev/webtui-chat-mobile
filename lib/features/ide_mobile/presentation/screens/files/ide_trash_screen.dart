import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_file_models.dart';
import '../../controllers/ide_files_controllers.dart';
import '../../widgets/files/ide_file_card.dart' show ideFormatSize;
import '../../widgets/files/ide_files_ui.dart';
import '../../widgets/ide_step_sheet.dart';

/// Thùng rác của dự án: khôi phục, xoá hẳn một mục, dọn hết. Xoá hẳn là thao
/// tác nhạy cảm: IDE đòi xác nhận vân tay (`need_step`), app còn hỏi lại.
class IdeTrashScreen extends ConsumerStatefulWidget {
  const IdeTrashScreen({required this.root, super.key});

  final String root;

  @override
  ConsumerState<IdeTrashScreen> createState() => _IdeTrashScreenState();
}

class _IdeTrashScreenState extends ConsumerState<IdeTrashScreen> {
  late final IdeStepPresenterLease _lease;
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  List<IdeTrashItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _lease = IdeStepPresenterLease(ref.read(ideStepPresenterProvider.notifier));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lease.acquire(context, () => mounted);
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _lease.release();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref.read(ideFilesServiceProvider).trash(widget.root);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ideSnack(context, done);
      await _load();
    } on Object catch (e) {
      if (mounted) ideSnack(context, ideFilesErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(IdeTrashItem it) => _run(() async {
    await ref.read(ideFilesServiceProvider).restore(it.id);
  }, tr('Đã khôi phục ${it.name}', 'Restored ${it.name}'));

  Future<void> _purge(IdeTrashItem it) async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Xoá hẳn "${it.name}"?', 'Delete "${it.name}" forever?'),
      message: tr(
        'Không khôi phục lại được. Bạn sẽ được hỏi vân tay để xác nhận.',
        'This cannot be undone. You will be asked for your fingerprint.',
      ),
      confirmLabel: tr('Xoá hẳn', 'Delete forever'),
      destructive: true,
      icon: Icons.delete_forever_outlined,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref.read(ideFilesServiceProvider).purge(it.id),
      tr('Đã xoá hẳn', 'Deleted forever'),
    );
  }

  Future<void> _purgeAll() async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Dọn sạch thùng rác?', 'Empty the trash?'),
      message: tr(
        'Tất cả ${_items.length} mục sẽ bị xoá hẳn, không khôi phục lại được. Bạn sẽ được hỏi vân tay để xác nhận.',
        'All ${_items.length} items will be deleted forever. You will be asked for your fingerprint.',
      ),
      confirmLabel: tr('Dọn sạch', 'Empty'),
      destructive: true,
      icon: Icons.delete_forever_outlined,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref.read(ideFilesServiceProvider).trashPurge(widget.root),
      tr('Đã dọn thùng rác', 'Trash emptied'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = WebTuiLoadingState(
        message: tr('Đang mở thùng rác...', 'Opening the trash...'),
      );
    } else if (_error != null) {
      body = WebTuiErrorState(
        title: tr('Không mở được thùng rác', 'Could not open the trash'),
        message: ideFilesErrorText(_error!),
        onRetry: _load,
      );
    } else if (_items.isEmpty) {
      body = WebTuiEmptyState(
        icon: Icons.delete_outline_rounded,
        title: tr('Thùng rác trống', 'The trash is empty'),
        message: tr(
          'Tệp bạn xoá sẽ nằm ở đây để khôi phục.',
          'Files you delete appear here so you can restore them.',
        ),
      );
    } else {
      body = ListView.separated(
        key: const Key('ide_trash_list'),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const WebTuiHairline(),
        itemBuilder: (_, i) => _row(_items[i]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(tr('Thùng rác', 'Trash')),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              key: const Key('ide_trash_purge_all'),
              onPressed: _busy ? null : _purgeAll,
              child: Text(
                tr('Dọn hết', 'Empty'),
                style: TextStyle(color: WebTuiColors.danger),
              ),
            ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _row(IdeTrashItem it) {
    final when = it.deletedAt == null
        ? ''
        : ideFormatDate(it.deletedAt!.millisecondsSinceEpoch);
    final rel = ideIsInside(widget.root, it.path)
        ? ideParentPath(
            it.path,
          ).replaceFirst(widget.root, '').replaceFirst(RegExp('^/'), '')
        : ideParentPath(it.path);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.lg,
        vertical: WebTuiSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            it.isDir ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
            color: WebTuiColors.textSecondary,
          ),
          const SizedBox(width: WebTuiSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    if (rel.isNotEmpty) rel,
                    if (!it.isDir) ideFormatSize(it.size),
                    when,
                  ].where((e) => e.isNotEmpty).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('ide_trash_restore_${it.id}'),
            tooltip: tr('Khôi phục', 'Restore'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(Icons.restore_rounded, color: WebTuiColors.primary),
            onPressed: _busy ? null : () => unawaited(_restore(it)),
          ),
          IconButton(
            key: Key('ide_trash_purge_${it.id}'),
            tooltip: tr('Xoá hẳn', 'Delete forever'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(
              Icons.delete_forever_outlined,
              color: WebTuiColors.danger,
            ),
            onPressed: _busy ? null : () => unawaited(_purge(it)),
          ),
        ],
      ),
    );
  }
}
