import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/ide_errors.dart';
import '../widgets/ide_step_sheet.dart';
import '../widgets/markdown/ide_code_block.dart';

/// Giữ tối đa chừng này ký tự log trên màn hình (phần cũ nhất bị cắt).
const ideJobLogLimit = 200000;

/// Việc nền trên IDE: trạng thái, log chạy dần (`jobs.tail`), nút huỷ.
class IdeJobScreen extends ConsumerStatefulWidget {
  const IdeJobScreen({
    required this.jobId,
    this.pollInterval = const Duration(milliseconds: 1500),
    super.key,
  });

  final String jobId;
  final Duration pollInterval;

  @override
  ConsumerState<IdeJobScreen> createState() => _IdeJobScreenState();
}

class _IdeJobScreenState extends ConsumerState<IdeJobScreen> {
  final _scroll = ScrollController();
  Timer? _timer;
  String _log = '';
  int _next = 0;
  String _status = '';
  String _op = '';
  String _project = '';
  bool _loading = true;
  bool _done = false;
  bool _cancelling = false;
  bool _polling = false;
  late final IdeStepPresenterLease _lease;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _lease = IdeStepPresenterLease(ref.read(ideStepPresenterProvider.notifier));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lease.acquire(context, () => mounted);
    });
    unawaited(_start());
  }

  @override
  void dispose() {
    _lease.release();
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(ideRpcClientProvider)
          .call('jobs.list', const {});
      if (!mounted) return;
      final items = data is Map ? data['items'] : null;
      if (items is List) {
        for (final e in items) {
          if (e is Map && e['job'] == widget.jobId) {
            _op = e['op'] is String ? e['op'] as String : '';
            _project = e['project'] is String ? e['project'] as String : '';
            _status = e['status'] is String ? e['status'] as String : '';
          }
        }
      }
      await _poll();
      if (!mounted) return;
      setState(() => _loading = false);
      _schedule();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_done || !mounted) return;
    _timer = Timer(widget.pollInterval, () async {
      try {
        await _poll();
      } on Object catch (e) {
        if (mounted && e is IdeNotFound) setState(() => _error = e);
        // Lỗi mạng thoáng qua: giữ log cũ, thử lại lượt sau.
      }
      _schedule();
    });
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final data = await ref.read(ideRpcClientProvider).call('jobs.tail', {
        'job': widget.jobId,
        'from': _next,
      });
      if (!mounted || data is! Map) return;
      final text = data['text'] is String ? data['text'] as String : '';
      final next = data['next'];
      setState(() {
        if (text.isNotEmpty) {
          _log += text;
          if (_log.length > ideJobLogLimit) {
            _log = _log.substring(_log.length - ideJobLogLimit);
          }
        }
        if (next is num) _next = next.toInt();
        if (data['status'] is String) _status = data['status'] as String;
        _done = data['done'] == true;
      });
      if (text.isNotEmpty) _stickToBottom();
    } finally {
      _polling = false;
    }
  }

  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      if (p.maxScrollExtent - p.pixels < 120) {
        _scroll.jumpTo(p.maxScrollExtent);
      }
    });
  }

  Future<void> _cancel() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Huỷ việc này?', 'Cancel this job?'),
      message: tr(
        'Việc đang chạy trên máy tính sẽ bị dừng.',
        'The job running on your computer will be stopped.',
      ),
      confirmLabel: tr('Huỷ việc', 'Cancel job'),
      cancelLabel: tr('Giữ lại', 'Keep'),
      destructive: true,
      icon: Icons.stop_circle_outlined,
    );
    if (!ok || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(ideRpcClientProvider).call('jobs.cancel', {
        'job': widget.jobId,
      });
      await _poll();
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Đã gửi lệnh huỷ', 'Cancel sent'))),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is IdeForbidden
                ? tr(
                    'Bạn không có quyền huỷ việc này.',
                    'You cannot cancel this job.',
                  )
                : tr('Chưa huỷ được, thử lại.', 'Could not cancel, try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
      _schedule();
    }
  }

  (String, Color) get _statusView => switch (_status) {
    'running' => (tr('Đang chạy', 'Running'), WebTuiColors.primary),
    'done' ||
    'ok' ||
    'success' ||
    'finished' => (tr('Xong', 'Done'), WebTuiColors.accentGreen),
    'cancelled' ||
    'canceled' => (tr('Đã huỷ', 'Cancelled'), WebTuiColors.textMuted),
    'failed' || 'error' => (tr('Lỗi', 'Failed'), WebTuiColors.danger),
    '' => (tr('Không rõ', 'Unknown'), WebTuiColors.textMuted),
    final s => (s, WebTuiColors.textMuted),
  };

  @override
  Widget build(BuildContext context) {
    final running = _status == 'running' && !_done;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Việc nền', 'Background job')),
        actions: [
          if (running)
            TextButton.icon(
              key: const Key('ide_job_cancel'),
              onPressed: _cancelling ? null : _cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(tr('Huỷ', 'Cancel')),
              style: TextButton.styleFrom(
                foregroundColor: WebTuiColors.danger,
                minimumSize: const Size(44, 44),
              ),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return WebTuiLoadingState(
        message: tr('Đang tải việc nền...', 'Loading job...'),
      );
    }
    final error = _error;
    if (error != null) {
      return switch (error) {
        IdeNotFound() => WebTuiEmptyState(
          title: tr('Không tìm thấy việc này', 'Job not found'),
          message: tr(
            'Việc đã bị xoá hoặc IDE đã khởi động lại.',
            'The job was removed or the IDE restarted.',
          ),
          icon: Icons.search_off_rounded,
        ),
        IdeForbidden() => WebTuiEmptyState(
          title: tr('Không có quyền', 'No permission'),
          message: tr(
            'Tài khoản này không được xem việc nền.',
            'This account cannot view background jobs.',
          ),
          icon: Icons.lock_outline_rounded,
        ),
        _ => WebTuiErrorState(
          title: tr('Không tải được việc nền', 'Could not load the job'),
          message: error is IdeOffline
              ? tr('IDE vừa mất kết nối.', 'The IDE just disconnected.')
              : tr('Hãy thử lại.', 'Please try again.'),
          onRetry: _start,
        ),
      };
    }
    final (label, color) = _statusView;
    final running = _status == 'running' && !_done;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: Row(
            children: [
              WebTuiStatusPill(label: label, color: color),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: Text(
                  [_op, _project].where((e) => e.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              0,
              WebTuiSpacing.lg,
              WebTuiSpacing.lg,
            ),
            padding: const EdgeInsets.all(WebTuiSpacing.md),
            decoration: BoxDecoration(
              color: WebTuiColors.backgroundMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WebTuiColors.border),
            ),
            child: _log.isEmpty
                ? Center(
                    child: Text(
                      running
                          ? tr(
                              'Chưa có dòng log nào...',
                              'No log output yet...',
                            )
                          : tr(
                              'Việc này không có log.',
                              'This job has no log.',
                            ),
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.textMuted,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _scroll,
                    child: SelectableText(
                      _log,
                      key: const Key('ide_job_log'),
                      style: ideMonoStyle.copyWith(
                        color: WebTuiColors.textPrimary,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
