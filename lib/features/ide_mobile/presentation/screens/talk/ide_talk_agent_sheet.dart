import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_talk_models.dart';
import '../more/ide_more_common.dart';
import 'ide_talk_providers.dart';

/// Lưu cuộc chat thành AI Agent (tên, nhiệm vụ, lịch). Trả lời báo kết quả.
Future<String?> showIdeTalkAgentSheet(
  BuildContext context, {
  required String talkId,
  required String initialName,
  required String initialTask,
  IdeTalkAgentInfo? agent,
  bool canDraft = true,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => IdeTalkAgentSheet(
    talkId: talkId,
    initialName: initialName,
    initialTask: initialTask,
    agent: agent,
    canDraft: canDraft,
  ),
);

class IdeTalkAgentSheet extends ConsumerStatefulWidget {
  const IdeTalkAgentSheet({
    required this.talkId,
    required this.initialName,
    required this.initialTask,
    this.agent,
    this.canDraft = true,
    super.key,
  });

  final String talkId;
  final String initialName;
  final String initialTask;
  final IdeTalkAgentInfo? agent;
  final bool canDraft;

  @override
  ConsumerState<IdeTalkAgentSheet> createState() => _IdeTalkAgentSheetState();
}

class _IdeTalkAgentSheetState extends ConsumerState<IdeTalkAgentSheet> {
  late final _name = TextEditingController(
    text: widget.agent?.name.isNotEmpty == true
        ? widget.agent!.name
        : widget.initialName,
  );
  late final _task = TextEditingController(text: widget.initialTask);
  late final _custom = TextEditingController();
  late int _mode; // 0 thủ công, 1 mỗi giờ, 2 tuỳ chỉnh
  late bool _enabled = widget.agent?.enabled ?? true;
  bool _saving = false;
  bool _drafting = false;
  String? _error;
  String _label = '';

  @override
  void initState() {
    super.initState();
    final s = widget.agent?.schedule ?? '';
    _mode = s.isEmpty ? 0 : (s == 'hourly' ? 1 : 2);
    if (_mode == 2) _custom.text = s;
    _label = widget.agent?.scheduleLabel ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _task.dispose();
    _custom.dispose();
    super.dispose();
  }

  String get _schedule => switch (_mode) {
    1 => 'hourly',
    2 => _custom.text.trim(),
    _ => '',
  };

  Future<void> _draft() async {
    if (_drafting) return;
    final text = _task.text.trim();
    if (text.isEmpty) {
      setState(
        () => _error = tr('Hãy mô tả việc trước.', 'Describe the job first.'),
      );
      return;
    }
    setState(() {
      _drafting = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(ideTalkServiceProvider)
          .agentDraft(text.length > 4000 ? text.substring(0, 4000) : text);
      if (!mounted) return;
      setState(() {
        if (d.name.isNotEmpty) {
          _name.text = d.name.length > 60 ? d.name.substring(0, 60) : d.name;
        }
        if (d.task.isNotEmpty) _task.text = d.task;
        _label = d.scheduleLabel;
        if (d.schedule.isEmpty) {
          _mode = 0;
        } else if (d.schedule == 'hourly') {
          _mode = 1;
        } else {
          _mode = 2;
          _custom.text = d.schedule;
        }
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = ideMoreErrorText(e));
    } finally {
      if (mounted) setState(() => _drafting = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final task = _task.text.trim();
    if (name.isEmpty || name.length > 60) {
      setState(
        () =>
            _error = tr('Tên dài 1–60 ký tự.', 'Name must be 1–60 characters.'),
      );
      return;
    }
    if (task.isEmpty || task.length > 8000) {
      setState(
        () => _error = tr(
          'Nhiệm vụ dài 1–8000 ký tự.',
          'Task must be 1–8000 characters.',
        ),
      );
      return;
    }
    if (_mode == 2 && _schedule.isEmpty) {
      setState(() => _error = tr('Hãy nhập lịch.', 'Enter a schedule.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(ideTalkServiceProvider)
          .agentSave(
            id: widget.talkId,
            name: name,
            task: task,
            schedule: _schedule,
            scheduleLabel: _mode == 2 && _label.length <= 100 ? _label : '',
            enabled: _enabled,
          );
      if (!mounted) return;
      final parts = [
        tr('Đã lưu AI Agent.', 'AI Agent saved.'),
        if (r.nextAt != null)
          tr(
            'Lần chạy kế: ${ideFormatDateTime(r.nextAt!)}.',
            'Next run: ${ideFormatDateTime(r.nextAt!)}.',
          )
        else if (r.next.isNotEmpty)
          tr('Lần chạy kế: ${r.next}.', 'Next run: ${r.next}.'),
        if (r.warning.isNotEmpty) r.warning,
      ];
      Navigator.of(context).pop(parts.join(' '));
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ideMoreErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          0,
          WebTuiSpacing.lg,
          WebTuiSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Lưu thành AI Agent', 'Save as AI Agent'),
              style: WebTuiTypography.titleMedium.copyWith(
                color: WebTuiColors.textPrimary,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            TextField(
              key: const Key('agent_name'),
              controller: _name,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: tr('Tên', 'Name'),
                border: const OutlineInputBorder(),
              ),
            ),
            TextField(
              key: const Key('agent_task'),
              controller: _task,
              minLines: 3,
              maxLines: 8,
              maxLength: 8000,
              decoration: InputDecoration(
                labelText: tr('Nhiệm vụ', 'Task'),
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.canDraft)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('agent_draft'),
                  onPressed: _drafting ? null : _draft,
                  icon: _drafting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    _drafting
                        ? tr(
                            'AI đang soạn (tới 90 giây)...',
                            'Drafting (up to 90 s)...',
                          )
                        : tr('AI soạn nháp từ mô tả', 'Draft with AI'),
                  ),
                ),
              ),
            const SizedBox(height: WebTuiSpacing.sm),
            SegmentedButton<int>(
              key: const Key('agent_schedule'),
              segments: [
                ButtonSegment(value: 0, label: Text(tr('Thủ công', 'Manual'))),
                ButtonSegment(value: 1, label: Text(tr('Mỗi giờ', 'Hourly'))),
                ButtonSegment(
                  value: 2,
                  label: Text(tr('Lịch riêng', 'Custom')),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            if (_mode == 2)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                child: TextField(
                  key: const Key('agent_custom'),
                  controller: _custom,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: tr('Lịch (OnCalendar)', 'Schedule (OnCalendar)'),
                    helperText: tr(
                      'Ví dụ: Mon..Fri 08:30',
                      'Example: Mon..Fri 08:30',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Bật chạy theo lịch', 'Run on schedule')),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                child: Text(
                  _error!,
                  style: TextStyle(color: WebTuiColors.danger),
                ),
              ),
            FilledButton(
              key: const Key('agent_save'),
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('Lưu', 'Save')),
            ),
          ],
        ),
      ),
    );
  }
}
