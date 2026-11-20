import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_task_models.dart';
import '../../controllers/ide_more_controllers.dart';
import '../../widgets/ide_wb.dart';
import 'ide_more_common.dart';

/// Bảng thêm việc ([task] null) hoặc sửa việc. Trả `true` khi đã lưu.
Future<bool> showIdeTaskForm(
  BuildContext context, {
  required IdeTaskList list,
  IdeTask? task,
  String? defaultProject,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        IdeTaskForm(list: list, task: task, defaultProject: defaultProject),
  );
  return saved ?? false;
}

class IdeTaskForm extends ConsumerStatefulWidget {
  const IdeTaskForm({
    required this.list,
    this.task,
    this.defaultProject,
    super.key,
  });

  final IdeTaskList list;
  final IdeTask? task;
  final String? defaultProject;

  @override
  ConsumerState<IdeTaskForm> createState() => _IdeTaskFormState();
}

class _IdeTaskFormState extends ConsumerState<IdeTaskForm> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late final _detail = TextEditingController(text: widget.task?.detail ?? '');
  late String _project;
  late String _assignee;
  String? _due;
  bool _noAi = false;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final projects = widget.list.projects;
    _project =
        t?.project ??
        (projects.contains(widget.defaultProject)
            ? widget.defaultProject!
            : (projects.isEmpty ? '' : projects.first));
    _due = t?.due;
    final people = widget.list.assigneesOf(_project);
    _assignee =
        t?.assignee ??
        (people.contains(widget.list.viewer)
            ? widget.list.viewer
            : (people.isEmpty ? '' : people.first));
  }

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final picked = await ref.read(ideDatePickerProvider)(
      context,
      ideParseDue(_due),
    );
    if (picked != null && mounted) {
      setState(() => _due = ideFormatDue(picked));
    }
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = tr('Hãy nhập tiêu đề việc.', 'Enter a title.'));
      return;
    }
    if (_project.isEmpty || _assignee.isEmpty) {
      setState(
        () => _error = tr(
          'Chọn dự án và người nhận việc.',
          'Choose a project and an assignee.',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = ref.read(ideMoreServiceProvider);
    try {
      final t = widget.task;
      if (t == null) {
        await service.addTask(
          project: _project,
          assignee: _assignee,
          title: title,
          due: _due,
          detail: _detail.text.trim(),
          noAi: _noAi,
        );
      } else {
        final detail = _detail.text.trim();
        await service.editTask(
          t.id,
          title: title == t.title ? null : title,
          due: _due == t.due ? null : (_due ?? ''),
          assignee: _assignee == t.assignee ? null : _assignee,
          detail: detail == t.detail.trim() ? null : detail,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ideMoreErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.list.assigneesOf(_project);
    final assignee = people.contains(_assignee) ? _assignee : null;
    return Padding(
      padding: EdgeInsets.only(
        left: WebTuiSpacing.lg,
        right: WebTuiSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + WebTuiSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _editing
                  ? tr('Sửa việc', 'Edit task')
                  : tr('Thêm việc', 'New task'),
              style: IdeType.titleLarge.copyWith(color: IdeWb.textStrong),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            if (!_editing)
              DropdownButtonFormField<String>(
                key: const Key('ide_task_project'),
                initialValue: _project.isEmpty ? null : _project,
                decoration: InputDecoration(labelText: tr('Dự án', 'Project')),
                items: [
                  for (final p in widget.list.projects)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                        _project = v ?? _project;
                        final ppl = widget.list.assigneesOf(_project);
                        if (!ppl.contains(_assignee)) {
                          _assignee = ppl.isEmpty ? '' : ppl.first;
                        }
                      }),
              ),
            const SizedBox(height: WebTuiSpacing.sm),
            DropdownButtonFormField<String>(
              key: const Key('ide_task_assignee'),
              initialValue: assignee,
              decoration: InputDecoration(
                labelText: tr('Người nhận', 'Assignee'),
              ),
              items: [
                for (final p in people)
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _assignee = v ?? _assignee),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            TextField(
              key: const Key('ide_task_title'),
              controller: _title,
              maxLength: 200,
              enabled: !_busy,
              decoration: InputDecoration(labelText: tr('Tiêu đề', 'Title')),
            ),
            TextField(
              key: const Key('ide_task_detail'),
              controller: _detail,
              maxLength: 4000,
              maxLines: 4,
              minLines: 2,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: tr(
                  'Chi tiết (không bắt buộc)',
                  'Details (optional)',
                ),
              ),
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('ide_task_due'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    onPressed: _busy ? null : _pickDue,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(
                      _due == null
                          ? tr('Chọn hạn', 'Pick due date')
                          : '${tr('Hạn', 'Due')} ${ideDueDisplay(_due!)}',
                    ),
                  ),
                ),
                if (_due != null)
                  IconButton(
                    key: const Key('ide_task_due_clear'),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    tooltip: tr('Xoá hạn', 'Clear due date'),
                    onPressed: _busy ? null : () => setState(() => _due = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            if (!_editing)
              SwitchListTile(
                key: const Key('ide_task_no_ai'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Không cho AI gợi ý', 'No AI suggestion')),
                value: _noAi,
                onChanged: _busy ? null : (v) => setState(() => _noAi = v),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                child: Text(
                  _error!,
                  key: const Key('ide_task_error'),
                  style: IdeType.bodyMedium.copyWith(color: IdeWb.danger),
                ),
              ),
            const SizedBox(height: WebTuiSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const Key('ide_task_submit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _editing ? tr('Lưu', 'Save') : tr('Thêm việc', 'Add'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
