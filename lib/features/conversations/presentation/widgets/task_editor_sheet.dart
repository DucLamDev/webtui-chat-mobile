import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/use_cases/collaboration_task_use_cases.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/repositories/collaboration_task_repository.dart';
import '../controllers/collaboration_task_controller.dart';
import '../models/task_due_label.dart';

/// Mở bảng tạo việc (task == null) hoặc xem / sửa một việc. Trả câu thông báo
/// kết quả để màn gọi hiện SnackBar (null khi đóng không làm gì).
Future<String?> showTaskEditorSheet(
  BuildContext context, {
  required CollaborationTaskScope scope,
  CollaborationTask? task,
  CollaborationTaskDraft? initialDraft,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: WebTuiColors.surface,
    builder: (_) =>
        TaskEditorSheet(scope: scope, task: task, initialDraft: initialDraft),
  );
}

class TaskEditorSheet extends ConsumerStatefulWidget {
  const TaskEditorSheet({
    required this.scope,
    this.task,
    this.initialDraft,
    super.key,
  });

  final CollaborationTaskScope scope;
  final CollaborationTask? task;
  final CollaborationTaskDraft? initialDraft;

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  String? _assigneeUserId;
  DateTime? _dueAt;
  late CollaborationTaskStatus _status;
  bool _saving = false;
  String? _error;

  bool get _creating => widget.task == null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    final draft = widget.initialDraft;
    _title = TextEditingController(text: task?.title ?? draft?.title ?? '');
    _description = TextEditingController(
      text: task?.description ?? draft?.description ?? '',
    );
    _assigneeUserId = task?.assigneeUserId ?? draft?.assigneeUserId;
    _dueAt = (task?.dueAt ?? draft?.dueAt)?.toLocal();
    _status = task?.taskStatus ?? CollaborationTaskStatus.open;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = collaborationTaskControllerProvider(widget.scope);
    final state = ref.watch(provider);
    final task = widget.task;
    final canEdit = _creating || (task != null && state.canEdit(task));
    final canChangeStatus =
        _creating || (task != null && state.canChangeStatus(task));
    final assignee = state.member(_assigneeUserId);
    final now = DateTime.now();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          0,
          WebTuiSpacing.lg,
          WebTuiSpacing.xl,
        ),
        children: [
          Text(
            _creating
                ? tr('Giao việc mới', 'New task')
                : (canEdit
                      ? tr('Sửa công việc', 'Edit task')
                      : tr('Chi tiết công việc', 'Task details')),
            style: WebTuiTypography.titleMedium.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!_creating && !canEdit) ...[
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              canChangeStatus
                  ? tr(
                      'Bạn được giao việc này: chỉ đổi được trạng thái.',
                      'This task is assigned to you: you can only change its status.',
                    )
                  : tr(
                      'Chỉ người tạo việc, người tạo phòng hoặc quản trị mới sửa được việc này.',
                      'Only the task creator, the room creator or an admin can edit this task.',
                    ),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: WebTuiSpacing.md),
          TextField(
            key: const Key('task_editor_title'),
            controller: _title,
            enabled: canEdit,
            maxLength: maxTaskTitleLength,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: tr('Tên công việc', 'Task name'),
              hintText: tr(
                'Ví dụ: Gửi báo giá cho khách',
                'For example: Send the quote to the client',
              ),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          TextField(
            key: const Key('task_editor_description'),
            controller: _description,
            enabled: canEdit,
            minLines: 2,
            maxLines: 6,
            maxLength: maxTaskDescriptionLength,
            decoration: InputDecoration(
              labelText: tr('Mô tả (không bắt buộc)', 'Description (optional)'),
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          _FieldLabel(text: tr('Người làm', 'Assignee')),
          Material(
            color: WebTuiColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WebTuiRadii.md),
              side: BorderSide(color: WebTuiColors.border),
            ),
            child: ListTile(
              key: const Key('task_editor_assignee'),
              enabled: canEdit,
              minTileHeight: 52,
              leading: assignee == null
                  ? const Icon(WebTuiIcons.addFriend)
                  : WebTuiAvatar(
                      label: assignee.name,
                      imageUrl: assignee.avatarUrl,
                      size: 32,
                    ),
              title: Text(
                assignee?.name ?? tr('Chưa giao cho ai', 'Unassigned'),
              ),
              subtitle: assignee == null && canEdit
                  ? Text(
                      tr(
                        'Chạm để chọn người trong phòng',
                        'Tap to pick someone in the room',
                      ),
                    )
                  : null,
              trailing: canEdit ? const Icon(WebTuiIcons.forward) : null,
              onTap: () => _pickAssignee(state.members),
            ),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          _FieldLabel(text: tr('Hạn chót', 'Due date')),
          Wrap(
            spacing: WebTuiSpacing.xs,
            runSpacing: WebTuiSpacing.xs,
            children: [
              ChoiceChip(
                label: Text(tr('Không có hạn', 'No due date')),
                selected: _dueAt == null,
                onSelected: canEdit
                    ? (_) => setState(() => _dueAt = null)
                    : null,
              ),
              for (final option in quickTaskDueOptions(now))
                ChoiceChip(
                  label: Text(option.label),
                  selected: _dueAt == option.value,
                  onSelected: canEdit
                      ? (_) => setState(() => _dueAt = option.value)
                      : null,
                ),
              ActionChip(
                key: const Key('task_editor_pick_due'),
                avatar: const Icon(WebTuiIcons.meetings, size: 18),
                label: Text(
                  _dueAt == null
                      ? tr('Chọn ngày giờ', 'Pick date and time')
                      : formatTaskDue(_dueAt!, now),
                ),
                onPressed: canEdit ? _pickDue : null,
              ),
            ],
          ),
          if (!_creating) ...[
            const SizedBox(height: WebTuiSpacing.md),
            _FieldLabel(text: tr('Trạng thái', 'Status')),
            Wrap(
              spacing: WebTuiSpacing.xs,
              runSpacing: WebTuiSpacing.xs,
              children: [
                for (final status in CollaborationTaskStatus.values)
                  ChoiceChip(
                    key: Key('task_editor_status_${status.apiValue}'),
                    label: Text(status.label),
                    selected: _status == status,
                    onSelected: canChangeStatus
                        ? (_) => setState(() => _status = status)
                        : null,
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: WebTuiSpacing.sm),
            Text(
              _error!,
              key: const Key('task_editor_error'),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.danger,
              ),
            ),
          ],
          const SizedBox(height: WebTuiSpacing.lg),
          Row(
            children: [
              if (!_creating && task != null && state.canEdit(task))
                TextButton.icon(
                  key: const Key('task_editor_delete'),
                  onPressed: _saving ? null : () => _delete(task),
                  style: TextButton.styleFrom(
                    foregroundColor: WebTuiColors.danger,
                  ),
                  icon: const Icon(WebTuiIcons.delete),
                  label: Text(tr('Xoá', 'Delete')),
                ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(tr('Đóng', 'Close')),
              ),
              const SizedBox(width: WebTuiSpacing.xs),
              if (canEdit || canChangeStatus)
                FilledButton(
                  key: const Key('task_editor_save'),
                  onPressed: _saving ? null : () => _save(task),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _creating
                              ? tr('Giao việc', 'Assign')
                              : tr('Lưu', 'Save'),
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAssignee(List<TaskAssigneeOption> members) async {
    final selected = await showWebTuiSheet<String>(
      context: context,
      builder: (_) =>
          _AssigneePicker(members: members, selectedUserId: _assigneeUserId),
    );
    if (selected == null || !mounted) return;
    setState(() => _assigneeUserId = selected.isEmpty ? null : selected);
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final initial = _dueAt ?? DateTime(now.year, now.month, now.day + 1, 9);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: tr('Chọn ngày hạn', 'Pick due date'),
      cancelText: tr('Huỷ', 'Cancel'),
      confirmText: tr('Chọn', 'Select'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: tr('Chọn giờ hạn', 'Pick due time'),
      cancelText: tr('Huỷ', 'Cancel'),
      confirmText: tr('Chọn', 'Select'),
    );
    if (time == null || !mounted) return;
    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save(CollaborationTask? task) async {
    final controller = ref.read(
      collaborationTaskControllerProvider(widget.scope).notifier,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final String? error;
    if (task == null) {
      error = await controller.create(
        CollaborationTaskDraft(
          title: _title.text,
          description: _description.text,
          assigneeUserId: _assigneeUserId,
          dueAt: _dueAt,
          sourceMessageId: widget.initialDraft?.sourceMessageId,
        ),
      );
    } else {
      final changes = _changesFor(task);
      error = changes == null ? null : await controller.update(task, changes);
    }
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(
      task == null
          ? tr('Đã giao việc.', 'Task assigned.')
          : tr('Đã lưu việc.', 'Task saved.'),
    );
  }

  /// Chỉ gửi phần thật sự đổi để người được giao (chỉ đổi trạng thái) không bị chặn.
  CollaborationTaskChanges? _changesFor(CollaborationTask task) {
    final title = _title.text.trim();
    final description = _description.text.trim();
    final dueChanged = !_sameMinute(_dueAt, task.dueAt);
    final changes = CollaborationTaskChanges(
      status: _status == task.taskStatus ? null : _status,
      title: title == task.title ? null : title,
      description: description == (task.description ?? '').trim()
          ? null
          : description,
      assigneeUserId: (_assigneeUserId ?? '') == (task.assigneeUserId ?? '')
          ? null
          : (_assigneeUserId ?? ''),
      dueAt: dueChanged ? _dueAt : null,
      clearDueAt: dueChanged && _dueAt == null,
    );
    if (changes.status == null && !changes.changesDetails) return null;
    return changes;
  }

  Future<void> _delete(CollaborationTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => WebTuiDialog(
        title: tr('Xoá công việc?', 'Delete task?'),
        message: tr(
          '"${task.title}" sẽ bị xoá và không khôi phục được.',
          '"${task.title}" will be deleted and can\'t be restored.',
        ),
        icon: WebTuiIcons.delete,
        tone: WebTuiDialogTone.danger,
        actions: [
          WebTuiDialogAction(
            label: tr('Huỷ', 'Cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WebTuiDialogAction(
            key: const Key('task_editor_delete_confirm'),
            label: tr('Xoá', 'Delete'),
            primary: true,
            destructive: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final error = await ref
        .read(collaborationTaskControllerProvider(widget.scope).notifier)
        .delete(task);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(tr('Đã xoá việc.', 'Task deleted.'));
  }
}

bool _sameMinute(DateTime? left, DateTime? right) {
  if (left == null || right == null) return left == right;
  return left.toUtc().difference(right.toUtc()).inMinutes.abs() < 1;
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
      child: Text(
        text,
        style: WebTuiTypography.labelSmall.copyWith(
          color: WebTuiColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Chọn người làm trong thành viên phòng; trả '' khi bỏ giao.
class _AssigneePicker extends StatefulWidget {
  const _AssigneePicker({required this.members, this.selectedUserId});

  final List<TaskAssigneeOption> members;
  final String? selectedUserId;

  @override
  State<_AssigneePicker> createState() => _AssigneePickerState();
}

class _AssigneePickerState extends State<_AssigneePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final members = [
      for (final member in widget.members)
        if (query.isEmpty || member.name.toLowerCase().contains(query)) member,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          const WebTuiSheetHeader(title: 'Giao cho ai'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              0,
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
            ),
            child: TextField(
              key: const Key('task_assignee_search'),
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: Icon(WebTuiIcons.search),
                hintText: tr(
                  'Tìm người trong phòng',
                  'Search people in the room',
                ),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                WebTuiSheetActionTile(
                  icon: WebTuiIcons.close,
                  title: tr('Chưa giao cho ai', 'Unassigned'),
                  selected: widget.selectedUserId == null,
                  onTap: () => Navigator.of(context).pop(''),
                ),
                if (members.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(WebTuiSpacing.lg),
                    child: Text(
                      tr(
                        'Không tìm thấy thành viên phù hợp.',
                        'No matching members found.',
                      ),
                    ),
                  ),
                for (final member in members)
                  ListTile(
                    key: Key('task_assignee_${member.userId}'),
                    leading: WebTuiAvatar(
                      label: member.name,
                      imageUrl: member.avatarUrl,
                      size: 36,
                    ),
                    title: Text(member.name),
                    selected: member.userId == widget.selectedUserId,
                    trailing: member.userId == widget.selectedUserId
                        ? const Icon(WebTuiIcons.check)
                        : null,
                    onTap: () => Navigator.of(context).pop(member.userId),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
