import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';

final class MeetingScheduleDraft {
  const MeetingScheduleDraft({
    required this.title,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.lobbyOpensAt,
    required this.roomPolicy,
    this.cleanupAfter,
  });

  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime? lobbyOpensAt;
  final String roomPolicy;
  final DateTime? cleanupAfter;
}

Future<MeetingScheduleDraft?> showMeetingSchedulerSheet(
  BuildContext context, {
  required String conversationTitle,
}) {
  return showModalBottomSheet<MeetingScheduleDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: WebTuiColors.surface,
    builder: (_) =>
        _MeetingSchedulerSheet(conversationTitle: conversationTitle),
  );
}

class _MeetingSchedulerSheet extends StatefulWidget {
  const _MeetingSchedulerSheet({required this.conversationTitle});

  final String conversationTitle;

  @override
  State<_MeetingSchedulerSheet> createState() => _MeetingSchedulerSheetState();
}

class _MeetingSchedulerSheetState extends State<_MeetingSchedulerSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late DateTime _startsAt;
  int _durationMinutes = 60;
  int _lobbyMinutes = 10;
  String _roomPolicy = 'keep';
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _startsAt = _roundUpToQuarter(
      DateTime.now().add(const Duration(minutes: 30)),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? get _validationMessage {
    if (_titleController.text.trim().isEmpty) {
      return _submitted ? 'Hãy nhập tên cuộc họp.' : null;
    }
    if (!_startsAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return 'Thời gian bắt đầu phải sau hiện tại ít nhất 1 phút.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final endsAt = _startsAt.add(Duration(minutes: _durationMinutes));
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                0,
                WebTuiSpacing.sm,
                WebTuiSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: WebTuiColors.primary.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                    ),
                    child: const Icon(
                      Icons.event_available_rounded,
                      color: WebTuiColors.primary,
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lên lịch cuộc họp',
                          style: WebTuiTypography.titleMedium.copyWith(
                            color: WebTuiColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.conversationTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: WebTuiColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(WebTuiSpacing.lg),
                children: [
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    maxLength: 160,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Tên cuộc họp',
                      hintText: 'Ví dụ: Họp sprint tuần',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: WebTuiSpacing.sm),
                  TextField(
                    controller: _descriptionController,
                    maxLength: 2000,
                    maxLines: 4,
                    minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nội dung / chương trình họp',
                      hintText:
                          'Mục tiêu, nội dung cần chuẩn bị hoặc đường dẫn tài liệu…',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: WebTuiSpacing.sm),
                  _ScheduleCard(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.calendar_month_outlined,
                          color: WebTuiColors.primary,
                        ),
                        title: const Text('Ngày bắt đầu'),
                        subtitle: Text(localizations.formatFullDate(_startsAt)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _pickDate,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.schedule_rounded,
                          color: WebTuiColors.primary,
                        ),
                        title: const Text('Giờ bắt đầu'),
                        subtitle: Text(
                          localizations.formatTimeOfDay(
                            TimeOfDay.fromDateTime(_startsAt),
                            alwaysUse24HourFormat: true,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _pickTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: WebTuiSpacing.md),
                  DropdownButtonFormField<int>(
                    initialValue: _durationMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Thời lượng dự kiến',
                      prefixIcon: Icon(Icons.timelapse_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 phút')),
                      DropdownMenuItem(value: 30, child: Text('30 phút')),
                      DropdownMenuItem(value: 45, child: Text('45 phút')),
                      DropdownMenuItem(value: 60, child: Text('1 giờ')),
                      DropdownMenuItem(value: 90, child: Text('1 giờ 30 phút')),
                      DropdownMenuItem(value: 120, child: Text('2 giờ')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _durationMinutes = value);
                      }
                    },
                  ),
                  const SizedBox(height: WebTuiSpacing.md),
                  DropdownButtonFormField<int>(
                    initialValue: _lobbyMinutes,
                    decoration: const InputDecoration(
                      labelText: 'Mở phòng chờ',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 0,
                        child: Text('Khi cuộc họp bắt đầu'),
                      ),
                      DropdownMenuItem(value: 5, child: Text('Trước 5 phút')),
                      DropdownMenuItem(value: 10, child: Text('Trước 10 phút')),
                      DropdownMenuItem(value: 15, child: Text('Trước 15 phút')),
                      DropdownMenuItem(value: 30, child: Text('Trước 30 phút')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _lobbyMinutes = value);
                      }
                    },
                  ),
                  const SizedBox(height: WebTuiSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _roomPolicy,
                    decoration: const InputDecoration(
                      labelText: 'Sau cuộc họp',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'keep',
                        child: Text('Giữ phòng và nội dung'),
                      ),
                      DropdownMenuItem(
                        value: 'archive',
                        child: Text('Lưu trữ sau 24 giờ'),
                      ),
                      DropdownMenuItem(
                        value: 'delete',
                        child: Text('Dọn phòng sau 24 giờ'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _roomPolicy = value);
                      }
                    },
                  ),
                  const SizedBox(height: WebTuiSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(WebTuiSpacing.md),
                    decoration: BoxDecoration(
                      color: WebTuiColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: WebTuiColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: WebTuiSpacing.sm),
                        Expanded(
                          child: Text(
                            'Dự kiến kết thúc lúc '
                            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(endsAt), alwaysUse24HourFormat: true)}'
                            '${_lobbyMinutes > 0 ? ' · Phòng chờ mở trước $_lobbyMinutes phút' : ''}.',
                            style: WebTuiTypography.bodySmall.copyWith(
                              color: WebTuiColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_validationMessage case final message?) ...[
                    const SizedBox(height: WebTuiSpacing.md),
                    Text(
                      message,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.event_available_rounded),
                  label: const Text('Tạo lịch họp'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startsAt.hour,
        _startsAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(
        _startsAt.year,
        _startsAt.month,
        _startsAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _submit() {
    setState(() => _submitted = true);
    if (_validationMessage != null) return;
    final endsAt = _startsAt.add(Duration(minutes: _durationMinutes));
    Navigator.of(context).pop(
      MeetingScheduleDraft(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        startsAt: _startsAt,
        endsAt: endsAt,
        lobbyOpensAt: _lobbyMinutes > 0
            ? _startsAt.subtract(Duration(minutes: _lobbyMinutes))
            : null,
        roomPolicy: _roomPolicy,
        cleanupAfter: _roomPolicy == 'keep'
            ? null
            : endsAt.add(const Duration(hours: 24)),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: WebTuiColors.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
      ),
      child: Column(children: children),
    );
  }
}

DateTime _roundUpToQuarter(DateTime value) {
  final nextQuarter = ((value.minute + 14) ~/ 15) * 15;
  return DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
  ).add(Duration(minutes: nextQuarter));
}
