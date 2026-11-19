import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_task_models.dart';
import '../../controllers/ide_more_controllers.dart';
import '../../controllers/ide_project_controllers.dart';
import '../../widgets/markdown/ide_markdown.dart';
import '../ide_ai_chat_screen.dart';
import 'ide_more_common.dart';
import 'ide_task_form.dart';
import 'ide_tasks_screen.dart';

/// Chi tiết một việc: đổi trạng thái kèm ghi chú, sửa, xoá, gợi ý AI, giao AI.
class IdeTaskDetailScreen extends ConsumerStatefulWidget {
  const IdeTaskDetailScreen({
    required this.taskId,
    this.suggestPoll = const Duration(seconds: 3),
    this.suggestMax = const Duration(minutes: 5),
    super.key,
  });

  final String taskId;

  /// Khoảng tải lại `tasks.get` khi chờ AI gợi ý, và thời gian chờ tối đa.
  final Duration suggestPoll;
  final Duration suggestMax;

  @override
  ConsumerState<IdeTaskDetailScreen> createState() =>
      _IdeTaskDetailScreenState();
}

class _IdeTaskDetailScreenState extends ConsumerState<IdeTaskDetailScreen> {
  IdeTask? _task;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  bool _waiting = false;
  bool _gaveUp = false;
  Timer? _timer;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _task == null;
      _error = null;
    });
    try {
      final t = await ref.read(ideMoreServiceProvider).task(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = t;
        _loading = false;
      });
      if (t.suggestion?.pending ?? false) _startWaiting();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _startWaiting() {
    if (_timer?.isActive ?? false) return;
    setState(() {
      _waiting = true;
      _gaveUp = false;
    });
    _polls = 0;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.suggestPoll, () async {
      if (!mounted) return;
      _polls++;
      final maxPolls =
          (widget.suggestMax.inMilliseconds /
                  widget.suggestPoll.inMilliseconds.clamp(1, 1 << 30))
              .ceil();
      try {
        final t = await ref.read(ideMoreServiceProvider).task(widget.taskId);
        if (!mounted) return;
        setState(() => _task = t);
        if (!(t.suggestion?.pending ?? false)) {
          setState(() => _waiting = false);
          return;
        }
      } on Object {
        // Mạng chập chờn: thử lại lượt sau.
      }
      if (!mounted) return;
      if (_polls >= maxPolls) {
        setState(() {
          _waiting = false;
          _gaveUp = true;
        });
        return;
      }
      _schedule();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ideMoreErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeStatus(IdeTask t, String status) async {
    if (status == t.status) return;
    final note = await _askNote(status);
    if (note == null || !mounted) return;
    await _run(() async {
      await ref
          .read(ideMoreServiceProvider)
          .setTaskStatus(t.id, status, note: note);
      await _load();
    });
  }

  /// Hỏi ghi chú (không bắt buộc, ≤ 500 ký tự); `null` = huỷ. Không dispose
  /// bộ điều khiển ở đây: hộp thoại còn đang chạy hiệu ứng đóng.
  Future<String?> _askNote(String status) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => WebTuiDialog(
        title:
            '${tr('Chuyển sang', 'Move to')} "${ideTaskStatusLabel(status)}"',
        content: WebTuiDialogTextField(
          controller: c,
          label: tr('Ghi chú (không bắt buộc)', 'Note (optional)'),
          maxLength: 500,
          autofocus: true,
        ),
        actions: [
          WebTuiDialogAction(
            key: const Key('webtui_dialog_cancel'),
            label: tr('Huỷ', 'Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          WebTuiDialogAction(
            key: const Key('webtui_dialog_confirm'),
            label: tr('Đổi', 'Change'),
            primary: true,
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(IdeTask t) async {
    await _run(() async {
      final list = await ref
          .read(ideMoreServiceProvider)
          .tasks(project: t.project);
      if (!mounted) return;
      final saved = await showIdeTaskForm(context, list: list, task: t);
      if (saved) await _load();
    });
  }

  Future<void> _delete(IdeTask t) async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Xoá việc này?', 'Delete this task?'),
      message: tr(
        'Việc sẽ bị xoá khỏi dự án. IDE sẽ hỏi xác nhận bằng khoá của bạn.',
        'The task will be deleted. The IDE will ask you to confirm with your key.',
      ),
      confirmLabel: tr('Xoá việc', 'Delete'),
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await ref.read(ideMoreServiceProvider).deleteTask(t.id);
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _suggest(IdeTask t) async {
    await _run(() async {
      await ref.read(ideMoreServiceProvider).suggestTask(t.id);
      await _load();
      if (mounted && !_waiting && !(_task?.suggestion?.pending ?? false)) {
        // IDE chưa kịp đánh dấu chạy nền: vẫn chờ.
        _startWaiting();
      }
    });
  }

  Future<void> _giveToAi(IdeTask t) async {
    final prompt = ideTaskAiPrompt(t);
    final projects = ref.read(ideProjectsProvider).valueOrNull ?? const [];
    final root = [
      for (final p in projects)
        if (p.name == t.project) p.root,
    ];
    if (root.isEmpty) {
      await Clipboard.setData(ClipboardData(text: prompt));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Không tìm thấy thư mục dự án. Đã chép nội dung việc vào bộ nhớ tạm.',
              'Project folder not found. The task text was copied.',
            ),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => IdeAiChatScreen.newSession(
          kind: 'claude',
          root: root.first,
          initialText: prompt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;
    return IdeMorePage(
      title: tr('Việc', 'Task'),
      actions: [
        if (t != null && t.canManage) ...[
          IconButton(
            key: const Key('ide_task_edit'),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: tr('Sửa', 'Edit'),
            onPressed: _busy ? null : () => _edit(t),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: const Key('ide_task_delete'),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: tr('Xoá', 'Delete'),
            onPressed: _busy ? null : () => _delete(t),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ],
      body: t != null
          ? _content(t)
          : _loading
          ? WebTuiLoadingState(message: tr('Đang tải...', 'Loading...'))
          : IdeMoreErrorView(
              error: _error ?? const FormatException(),
              onRetry: _load,
            ),
    );
  }

  Widget _content(IdeTask t) {
    final state = ideDueState(t.due, DateTime.now(), done: t.isDone);
    final sug = t.suggestion;
    final muted = WebTuiTypography.bodySmall.copyWith(
      color: WebTuiColors.textMuted,
    );
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        Text(
          t.title,
          key: const Key('ide_task_title_text'),
          style: WebTuiTypography.titleLarge.copyWith(
            color: WebTuiColors.textPrimary,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.sm),
        Text(
          [
            if (t.project.isNotEmpty) t.project,
            if (t.assignee.isNotEmpty)
              '${tr('Người nhận', 'Assignee')}: ${t.assignee}',
            if (t.by.isNotEmpty) '${tr('Giao bởi', 'From')}: ${t.by}',
          ].join(' · '),
          style: muted,
        ),
        const SizedBox(height: WebTuiSpacing.xs),
        Text(
          [
            if (t.due != null)
              '${state == IdeDueState.overdue ? tr('Quá hạn', 'Overdue') : tr('Hạn', 'Due')} ${ideDueDisplay(t.due!)}'
            else
              tr('Không có hạn', 'No due date'),
            if (t.updated != null)
              '${tr('Cập nhật', 'Updated')} ${ideFormatDateTime(t.updated!)}',
          ].join(' · '),
          style: muted.copyWith(
            color: state == IdeDueState.overdue
                ? WebTuiColors.danger
                : WebTuiColors.textMuted,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.md),
        WebTuiSegmentedTabs(
          key: const Key('ide_task_status'),
          tabs: [for (final s in ideTaskStatuses) ideTaskStatusLabel(s)],
          selectedIndex: ideTaskStatuses.indexOf(t.status).clamp(0, 99),
          onChanged: (i) {
            if (!_busy) _changeStatus(t, ideTaskStatuses[i]);
          },
        ),
        if (t.note.isNotEmpty) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          Text('${tr('Ghi chú', 'Note')}: ${t.note}', style: muted),
        ],
        if (t.detail.trim().isNotEmpty) ...[
          const SizedBox(height: WebTuiSpacing.lg),
          IdeCard(child: IdeMarkdown(text: t.detail)),
        ],
        const SizedBox(height: WebTuiSpacing.lg),
        _suggestion(t, sug),
        const SizedBox(height: WebTuiSpacing.md),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            key: const Key('ide_task_give_ai'),
            onPressed: _busy ? null : () => _giveToAi(t),
            icon: const Icon(Icons.smart_toy_outlined),
            label: Text(tr('Giao cho AI', 'Give to AI')),
          ),
        ),
      ],
    );
  }

  Widget _suggestion(IdeTask t, IdeTaskSuggestion? sug) {
    final off = sug == null || sug.state == IdeSuggestionState.off;
    final text = sug?.text.trim() ?? '';
    return IdeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: WebTuiColors.primary,
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: Text(
                  tr('Gợi ý của AI', 'AI suggestion'),
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          if (_waiting || (sug?.pending ?? false))
            Row(
              key: const Key('ide_task_suggest_waiting'),
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                Expanded(
                  child: Text(
                    tr(
                      'AI đang nghĩ, thường mất 1-3 phút...',
                      'The AI is working, usually 1-3 minutes...',
                    ),
                  ),
                ),
              ],
            )
          else if (text.isNotEmpty)
            IdeMarkdown(text: text)
          else if (sug?.state == IdeSuggestionState.error)
            Text(
              sug!.error.isEmpty
                  ? tr('AI chưa gợi ý được.', 'The AI could not suggest.')
                  : sug.error,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: WebTuiColors.danger,
              ),
            )
          else if (_gaveUp)
            Text(
              tr(
                'AI chưa trả lời sau vài phút. Hãy mở lại việc này sau.',
                'The AI has not answered yet. Reopen this task later.',
              ),
            )
          else
            Text(
              off
                  ? tr(
                      'Nhờ AI gợi ý cách làm việc này.',
                      'Ask the AI how to approach this task.',
                    )
                  : '',
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
          if (!_waiting && !(sug?.pending ?? false))
            TextButton.icon(
              key: const Key('ide_task_suggest'),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: _busy ? null : () => _suggest(t),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                text.isEmpty
                    ? tr('Gợi ý bằng AI', 'Suggest with AI')
                    : tr('Gợi ý lại', 'Suggest again'),
              ),
            ),
        ],
      ),
    );
  }
}
