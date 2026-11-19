import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_deploy.dart';
import '../../../domain/ide_project.dart';
import '../../controllers/ide_controllers.dart';
import '../../controllers/ide_project_ops_controllers.dart';
import '../../widgets/projects/ide_project_ui.dart';

/// Lịch sử triển khai. Trả mã job khi người dùng chọn "Quay lại bản này".
Future<String?> showIdeDeployHistorySheet(
  BuildContext context, {
  required IdeProject project,
  required String target,
}) => showWebTuiSheet<String>(
  context: context,
  builder: (_) => IdeDeployHistorySheet(project: project, target: target),
);

class IdeDeployHistorySheet extends ConsumerStatefulWidget {
  const IdeDeployHistorySheet({
    required this.project,
    required this.target,
    super.key,
  });

  final IdeProject project;
  final String target;

  @override
  ConsumerState<IdeDeployHistorySheet> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<IdeDeployHistorySheet> {
  bool _loading = true;
  Object? _error;
  List<IdeHistoryItem> _items = const [];
  String _kind = '';

  IdeDeployOps get _ops => IdeDeployOps.of(widget.project);

  bool _has(String op) =>
      ref.read(ideLinkStatusProvider).valueOrNull?.ready?.hasOp(op) ?? false;

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
      final data = await ref
          .read(ideProjectServiceProvider)
          .call(_ops.history, {
            'project': widget.project.name,
            if (!_ops.isMy && widget.target.isNotEmpty) 'target': widget.target,
          });
      if (!mounted) return;
      setState(() {
        _items = IdeHistoryItem.parseList(data);
        _kind = data is Map && data['kind'] is String
            ? data['kind'] as String
            : '';
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

  Future<void> _rollback(IdeHistoryItem item) async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Quay lại bản cũ?', 'Roll back?'),
      message: tr(
        'Máy chủ${widget.target.isNotEmpty ? ' "${widget.target}"' : ''} sẽ chạy lại bản "${item.subject.isEmpty ? item.id : item.subject}". Cần xác nhận bằng vân tay.',
        'The server${widget.target.isNotEmpty ? ' "${widget.target}"' : ''} will run "${item.subject.isEmpty ? item.id : item.subject}" again. Needs fingerprint.',
      ),
      confirmLabel: tr('Quay lại bản này', 'Roll back'),
      cancelLabel: tr('Huỷ', 'Cancel'),
      destructive: true,
      icon: Icons.history_rounded,
    );
    if (!ok || !mounted) return;
    final job = await ideProjectGuard(
      context,
      () => ref.read(ideProjectServiceProvider).startJob(_ops.rollback, {
        'project': widget.project.name,
        if (!_ops.isMy && widget.target.isNotEmpty) 'target': widget.target,
        'id': item.id,
      }),
    );
    if (job != null && mounted) Navigator.of(context).pop(job);
  }

  Future<void> _restore(IdeHistoryItem item) async {
    final path = await showWebTuiTextInputDialog(
      context,
      title: tr('Khôi phục một tệp', 'Restore one file'),
      message: tr(
        'Nhập đường dẫn tệp trong dự án (ví dụ src/app.php).',
        'Enter the file path inside the project (e.g. src/app.php).',
      ),
      label: tr('Đường dẫn tệp', 'File path'),
      confirmLabel: tr('Khôi phục', 'Restore'),
      validator: (v) => ideRelativePathError(v) == null
          ? null
          : tr(
              'Đường dẫn phải tính từ thư mục dự án, không có "..".',
              'Use a path inside the project, without "..".',
            ),
    );
    if (path == null || !mounted) return;
    final done = await ideProjectGuard(
      context,
      () => ref.read(ideProjectServiceProvider).call(_ops.restore, {
        'project': widget.project.name,
        if (!_ops.isMy && widget.target.isNotEmpty) 'target': widget.target,
        'id': item.id,
        'path': path.trim(),
      }),
    );
    if (done != null && mounted) {
      ideProjectSnack(context, tr('Đã khôi phục tệp', 'File restored'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRollback = _has(_ops.rollback);
    final canRestore =
        _has(_ops.restore) &&
        (_ops.isMy || widget.project.kind == IdeProjectKind.vps) &&
        _kind != 'run';
    final Widget body;
    if (_loading) {
      body = WebTuiLoadingState(
        message: tr('Đang tải lịch sử...', 'Loading history...'),
      );
    } else if (_error != null) {
      body = ideProjectErrorView(_error!, onRetry: _load);
    } else if (_items.isEmpty) {
      body = WebTuiEmptyState(
        key: const Key('ide_history_empty'),
        title: tr('Chưa có lịch sử', 'No history yet'),
        message: tr(
          'Chưa có lần triển khai nào được ghi lại.',
          'No deploy has been recorded yet.',
        ),
        icon: Icons.history_rounded,
      );
    } else {
      body = ListView(
        children: [
          for (final i in _items)
            Padding(
              key: Key('ide_history_${i.id}'),
              padding: const EdgeInsets.symmetric(
                horizontal: WebTuiSpacing.lg,
                vertical: WebTuiSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i.subject.isEmpty ? i.id : i.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    [
                      i.id.length > 8 ? i.id.substring(0, 8) : i.id,
                      i.by,
                      ideFormatUnix(i.at),
                      i.stat,
                    ].where((e) => e.isNotEmpty).join(' · '),
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
                  if (canRollback || canRestore)
                    Wrap(
                      spacing: WebTuiSpacing.sm,
                      children: [
                        if (canRollback)
                          TextButton(
                            key: Key('ide_history_rollback_${i.id}'),
                            onPressed: () => _rollback(i),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 44),
                            ),
                            child: Text(tr('Quay lại bản này', 'Roll back')),
                          ),
                        if (canRestore)
                          TextButton(
                            key: Key('ide_history_restore_${i.id}'),
                            onPressed: () => _restore(i),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 44),
                            ),
                            child: Text(
                              tr('Khôi phục một tệp', 'Restore a file'),
                            ),
                          ),
                      ],
                    ),
                  const Divider(height: 1),
                ],
              ),
            ),
        ],
      );
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          WebTuiSheetHeader(
            title: tr('Lịch sử triển khai', 'Deploy history'),
            subtitle: widget.project.title,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
