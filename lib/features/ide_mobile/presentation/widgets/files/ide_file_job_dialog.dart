import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_files_service.dart';
import '../../../domain/ide_errors.dart';
import '../../controllers/ide_files_controllers.dart';
import '../ide_wb.dart';
import 'ide_files_ui.dart';

/// Hộp theo dõi một việc nền của tệp (nén zip, đổi Office ra PDF, lấy từ liên
/// kết). Trả kết quả khi việc kết thúc; `null` khi người dùng đóng hộp (việc
/// vẫn chạy trên máy IDE, xem ở mục Việc nền).
Future<IdeFileJobOutcome?> showIdeFileJobDialog(
  BuildContext context, {
  required String job,
  required String title,
  Duration pollInterval = const Duration(seconds: 1),
}) {
  return showDialog<IdeFileJobOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _JobDialog(job: job, title: title, pollInterval: pollInterval),
  );
}

class _JobDialog extends ConsumerStatefulWidget {
  const _JobDialog({
    required this.job,
    required this.title,
    required this.pollInterval,
  });

  final String job;
  final String title;
  final Duration pollInterval;

  @override
  ConsumerState<_JobDialog> createState() => _JobDialogState();
}

class _JobDialogState extends ConsumerState<_JobDialog> {
  Timer? _timer;
  bool _polling = false;
  bool _cancelling = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
    _timer = Timer.periodic(widget.pollInterval, (_) => unawaited(_poll()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final s = await ref.read(ideFilesServiceProvider).jobState(widget.job);
      if (!mounted) return;
      if (ideJobFinished(s.status)) {
        _timer?.cancel();
        Navigator.of(
          context,
        ).pop(IdeFileJobOutcome(status: s.status, path: s.path));
      }
    } on Object catch (e) {
      // Mất mạng thoáng qua: thử lại lượt sau; lỗi khác báo ra.
      if (mounted && e is! IdeOffline && e is! IdeTimeout) {
        setState(() => _error = e);
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await ref.read(ideFilesServiceProvider).cancelJob(widget.job);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _cancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return WebTuiDialog(
      title: widget.title,
      icon: Icons.hourglass_top_rounded,
      content: error != null
          ? Text(
              ideFilesErrorText(error),
              style: IdeType.bodyMedium.copyWith(color: IdeWb.danger),
            )
          : Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: WebTuiSpacing.md),
                Expanded(
                  child: Text(
                    tr(
                      'Đang chạy trên máy tính...',
                      'Running on your computer...',
                    ),
                    style: IdeType.bodyMedium,
                  ),
                ),
              ],
            ),
      actions: [
        WebTuiDialogAction(
          key: const Key('ide_job_cancel'),
          label: tr('Huỷ việc', 'Cancel job'),
          destructive: true,
          onPressed: _cancelling ? null : () => unawaited(_cancel()),
        ),
        WebTuiDialogAction(
          key: const Key('ide_job_hide'),
          label: tr('Ẩn', 'Hide'),
          primary: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
