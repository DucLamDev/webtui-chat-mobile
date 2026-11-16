import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/meeting_calendar_providers.dart';
import '../../application/meeting_calendar_use_cases.dart';
import '../../domain/entities/calendar_meeting.dart';
import '../controllers/meeting_calendar_controllers.dart';
import '../widgets/meeting_dialogs.dart';
import '../widgets/meeting_widgets.dart';

enum _RepeatEnd { none, until, count }

/// Tạo (không có [existing]) hoặc sửa cuộc họp. Trả về cuộc họp vừa tạo, hoặc
/// [existing] khi sửa xong; `null` khi người dùng bỏ.
class MeetingFormScreen extends ConsumerStatefulWidget {
  const MeetingFormScreen({
    required this.workspaceId,
    this.existing,
    this.initialStart,
    this.now,
    super.key,
  });

  final String workspaceId;
  final CalendarMeeting? existing;

  /// Giờ bắt đầu gợi ý (mặc định: tròn giờ kế tiếp).
  final DateTime? initialStart;

  /// Chỉ để test cố định "bây giờ".
  final DateTime? now;

  @override
  ConsumerState<MeetingFormScreen> createState() => _MeetingFormScreenState();
}

class _MeetingFormScreenState extends ConsumerState<MeetingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _url;
  late final TextEditingController _count;

  bool _peopleMode = false;
  String? _channelId;
  String _channelName = '';

  /// Người tham dự trong nhóm; `null` = cả nhóm (mặc định của máy chủ).
  Set<String>? _groupAttendees;
  final Set<String> _people = {};

  late DateTime _start;
  late DateTime _end;
  late List<int> _reminders;

  MeetingRecurrenceFrequency? _frequency;
  final Set<int> _weekdays = {};
  _RepeatEnd _repeatEnd = _RepeatEnd.none;
  DateTime? _until;

  List<MeetingConflict> _conflicts = const [];
  bool _checkingConflicts = false;
  Timer? _conflictTimer;
  int _conflictSerial = 0;

  bool _saving = false;
  String? _error;

  /// Nhóm riêng đã tạo ở lần lưu trước (lưu lỗi sau khi tạo nhóm): thử lại
  /// thì dùng nhóm này, không tạo thêm.
  String? _createdGroupId;

  bool get _isEdit => widget.existing != null;

  DateTime _now() => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _url = TextEditingController(text: existing?.externalUrl ?? '');
    _count = TextEditingController();
    if (existing != null) {
      _channelId = existing.channelId;
      _channelName = existing.channelName;
      _start = existing.startsAt.toLocal();
      _end = existing.effectiveEnd.toLocal();
      _reminders = [...existing.reminderOffsets];
      if (existing.attendees.isNotEmpty) {
        _groupAttendees = {for (final item in existing.attendees) item.userId};
      }
      final recurrence = existing.recurrence;
      if (recurrence != null) {
        _frequency = recurrence.frequency;
        _weekdays.addAll(recurrence.byWeekday);
      }
    } else {
      final now = _now();
      _start =
          widget.initialStart?.toLocal() ??
          DateTime(now.year, now.month, now.day, now.hour + 1);
      _end = _start.add(defaultMeetingDuration);
      _reminders = [...defaultReminderOffsets];
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleConflicts());
  }

  @override
  void dispose() {
    _conflictTimer?.cancel();
    _title.dispose();
    _description.dispose();
    _url.dispose();
    _count.dispose();
    super.dispose();
  }

  ({String workspaceId, String channelId})? get _membersKey {
    final channelId = _channelId;
    if (_peopleMode || channelId == null || channelId.isEmpty) return null;
    return (workspaceId: widget.workspaceId, channelId: channelId);
  }

  List<MeetingPerson> get _groupMembers {
    final key = _membersKey;
    if (key == null) return const [];
    return ref.read(meetingGroupMembersProvider(key)).valueOrNull ?? const [];
  }

  /// Người được mời hiện tại (để kiểm trùng lịch).
  List<String> get _attendeeIds {
    if (_peopleMode) return _people.toList();
    final chosen = _groupAttendees;
    if (chosen != null) return chosen.toList();
    return [for (final person in _groupMembers) person.userId];
  }

  Map<String, String> get _names {
    final names = <String, String>{};
    for (final attendee in widget.existing?.attendees ?? const []) {
      names[attendee.userId] = attendee.displayName;
    }
    for (final person in _groupMembers) {
      names[person.userId] = person.displayName;
    }
    final people =
        ref
            .read(meetingWorkspacePeopleProvider(widget.workspaceId))
            .valueOrNull ??
        const [];
    for (final person in people) {
      names.putIfAbsent(person.userId, () => person.displayName);
    }
    return names;
  }

  void _scheduleConflicts() {
    _conflictTimer?.cancel();
    _conflictTimer = Timer(const Duration(milliseconds: 350), _checkConflicts);
  }

  Future<void> _checkConflicts() async {
    if (!mounted) return;
    final ids = _attendeeIds;
    final serial = ++_conflictSerial;
    if (ids.isEmpty || !_end.isAfter(_start)) {
      setState(() {
        _conflicts = const [];
        _checkingConflicts = false;
      });
      return;
    }
    setState(() => _checkingConflicts = true);
    final result = await ref
        .read(checkMeetingConflictsUseCaseProvider)
        .execute(
          workspaceId: widget.workspaceId,
          userIds: ids,
          startsAt: _start,
          endsAt: _end,
          excludeMeetingId: widget.existing?.id,
        );
    if (!mounted || serial != _conflictSerial) return;
    setState(() {
      _checkingConflicts = false;
      // Không kiểm được (máy chủ cũ / mất mạng) thì không cảnh báo, vẫn cho lưu.
      _conflicts = result.valueOrNull ?? const [];
    });
  }

  Future<void> _pickDate() async {
    final today = meetingDayStart(_now());
    final first = _start.isBefore(today) ? meetingDayStart(_start) : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: first,
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (picked == null || !mounted) return;
    final duration = _end.difference(_start);
    setState(() {
      _start = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _start.hour,
        _start.minute,
      );
      _end = _start.add(duration);
    });
    _scheduleConflicts();
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        final duration = _end.difference(_start);
        _start = DateTime(
          _start.year,
          _start.month,
          _start.day,
          picked.hour,
          picked.minute,
        );
        _end = _start.add(
          duration.isNegative ? defaultMeetingDuration : duration,
        );
      } else {
        var end = DateTime(
          _start.year,
          _start.month,
          _start.day,
          picked.hour,
          picked.minute,
        );
        // Giờ kết thúc nhỏ hơn giờ bắt đầu: họp qua nửa đêm.
        if (!end.isAfter(_start)) end = end.add(const Duration(days: 1));
        _end = end;
      }
    });
    _scheduleConflicts();
  }

  Future<void> _pickUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _until ?? _start.add(const Duration(days: 30)),
      firstDate: meetingDayStart(_start),
      lastDate: DateTime(_start.year + 1, _start.month, _start.day),
    );
    if (picked == null || !mounted) return;
    setState(() => _until = picked);
  }

  Future<void> _pickGroup() async {
    final picked = await showModalBottomSheet<MeetingGroupOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _GroupPickerSheet(workspaceId: widget.workspaceId),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _channelId = picked.channelId;
      _channelName = picked.name;
      _groupAttendees = null;
      _createdGroupId = null;
    });
    _scheduleConflicts();
  }

  Future<void> _pickPeople() async {
    final List<MeetingPerson> people;
    final Set<String> initial;
    if (_peopleMode) {
      people = await ref.read(
        meetingWorkspacePeopleProvider(widget.workspaceId).future,
      );
      initial = {..._people};
    } else {
      final key = _membersKey;
      if (key == null) return;
      people = await ref.read(meetingGroupMembersProvider(key).future);
      initial = _groupAttendees ?? {for (final p in people) p.userId};
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PeoplePickerSheet(people: people, selected: initial),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (_peopleMode) {
        _people
          ..clear()
          ..addAll(picked);
        _createdGroupId = null;
      } else {
        final everyone = {for (final p in people) p.userId};
        _groupAttendees =
            picked.length == everyone.length && picked.containsAll(everyone)
            ? null
            : picked;
      }
    });
    _scheduleConflicts();
  }

  MeetingRecurrence? _recurrence() {
    final frequency = _frequency;
    if (frequency == null) return null;
    return MeetingRecurrence(
      frequency: frequency,
      interval: widget.existing?.recurrence?.interval ?? 1,
      byWeekday: frequency == MeetingRecurrenceFrequency.weekly
          ? (_weekdays.toList()..sort())
          : const [],
      until: _repeatEnd == _RepeatEnd.until ? _until : null,
      count: _repeatEnd == _RepeatEnd.count
          ? int.tryParse(_count.text.trim()) ?? 0
          : null,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_isEdit && !_peopleMode && (_channelId ?? '').isEmpty) {
      setState(() => _error = tr('Hãy chọn nhóm.', 'Choose a group.'));
      return;
    }
    if (!_isEdit && _peopleMode && _people.isEmpty) {
      setState(
        () => _error = tr(
          'Hãy chọn ít nhất một người.',
          'Choose at least one person.',
        ),
      );
      return;
    }
    if (_repeatEnd == _RepeatEnd.until &&
        _frequency != null &&
        _until == null) {
      setState(
        () => _error = tr(
          'Hãy chọn ngày kết thúc lặp.',
          'Choose when the repeat ends.',
        ),
      );
      return;
    }
    final existing = widget.existing;
    MeetingScope scope = MeetingScope.occurrence;
    if (existing != null && existing.isRecurring) {
      final picked = await askMeetingScope(
        context,
        title: tr('Lưu thay đổi cho', 'Save changes to'),
      );
      if (picked == null || !mounted) return;
      scope = picked;
    }
    final draft = MeetingDraft(
      title: _title.text,
      description: _description.text,
      startsAt: _start,
      endsAt: _end,
      externalUrl: _url.text,
      reminderOffsets: _reminders,
      attendeeUserIds: _peopleMode
          ? _people.toList()
          : _groupAttendees?.toList(),
      recurrence: _isEdit && scope == MeetingScope.occurrence
          ? null
          : _recurrence(),
      timezone: ref.read(meetingTimezoneProvider),
    );
    setState(() => _saving = true);
    if (existing == null) {
      final createdGroup = _createdGroupId;
      final MeetingTarget target = createdGroup != null
          ? ExistingGroupTarget(createdGroup)
          : _peopleMode
          ? NewGroupTarget(memberIds: _people.toList())
          : ExistingGroupTarget(_channelId ?? '');
      final result = await ref
          .read(createMeetingUseCaseProvider)
          .execute(
            workspaceId: widget.workspaceId,
            target: target,
            draft: draft,
            onGroupCreated: (id) => _createdGroupId = id,
            now: widget.now,
          );
      if (!mounted) return;
      switch (result) {
        case Success(value: final meeting):
          bumpMeetingCalendar(ref.read);
          Navigator.of(context).pop(meeting);
        case FailureResult(failure: final failure):
          setState(() {
            _saving = false;
            _error = userFacingErrorMessage(failure);
          });
      }
      return;
    }
    final result = await ref
        .read(updateMeetingUseCaseProvider)
        .execute(
          workspaceId: widget.workspaceId,
          channelId: existing.channelId,
          meetingId: existing.id,
          draft: draft,
          scope: scope,
          now: widget.now,
        );
    if (!mounted) return;
    switch (result) {
      case Success():
        bumpMeetingCalendar(ref.read);
        Navigator.of(context).pop(existing);
      case FailureResult(failure: final failure):
        setState(() {
          _saving = false;
          _error = userFacingErrorMessage(failure);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersKey = _membersKey;
    final membersAsync = membersKey == null
        ? null
        : ref.watch(meetingGroupMembersProvider(membersKey));
    if (_peopleMode) {
      ref.watch(meetingWorkspacePeopleProvider(widget.workspaceId));
    }
    // Danh sách thành viên tải xong thì kiểm trùng lịch với cả nhóm.
    if (membersKey != null) {
      ref.listen(meetingGroupMembersProvider(membersKey), (_, next) {
        if (next.hasValue) _scheduleConflicts();
      });
    }
    final memberCount = membersAsync?.valueOrNull?.length;
    final attendeeSummary = _peopleMode
        ? tr('${_people.length} người', '${_people.length} people')
        : _groupAttendees == null
        ? (memberCount == null
              ? tr('Cả nhóm', 'Whole group')
              : tr('Cả nhóm ($memberCount)', 'Whole group ($memberCount)'))
        : tr(
            '${_groupAttendees!.length} người',
            '${_groupAttendees!.length} people',
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit
              ? tr('Sửa cuộc họp', 'Edit meeting')
              : tr('Tạo họp', 'New meeting'),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              TextFormField(
                key: const Key('meeting_title'),
                controller: _title,
                textInputAction: TextInputAction.next,
                maxLength: maxMeetingTitleLength,
                decoration: InputDecoration(
                  labelText: tr('Tiêu đề', 'Title'),
                  counterText: '',
                ),
                validator: (value) => validateMeetingTitle(value ?? ''),
              ),
              const SizedBox(height: 8),
              if (!_isEdit) ...[
                _ModeSwitch(
                  peopleMode: _peopleMode,
                  onChanged: (people) {
                    setState(() {
                      _peopleMode = people;
                      _createdGroupId = null;
                    });
                    _scheduleConflicts();
                  },
                ),
                const SizedBox(height: 4),
              ],
              if (!_peopleMode)
                _PickerTile(
                  key: const Key('meeting_group'),
                  icon: WebTuiIcons.group,
                  label: tr('Nhóm', 'Group'),
                  value: _channelName.isNotEmpty
                      ? _channelName
                      : tr('Chọn nhóm', 'Choose a group'),
                  onTap: _isEdit ? null : _pickGroup,
                ),
              if (_peopleMode || (_channelId ?? '').isNotEmpty)
                _PickerTile(
                  key: const Key('meeting_attendees'),
                  icon: WebTuiIcons.friends,
                  label: tr('Người tham dự', 'Attendees'),
                  value: attendeeSummary,
                  onTap: _pickPeople,
                ),
              if (_peopleMode)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(
                    tr(
                      'Một nhóm riêng tư mới sẽ được tạo cho buổi họp.',
                      'A new private group will be created for this meeting.',
                    ),
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                ),
              const Divider(height: 20),
              _PickerTile(
                key: const Key('meeting_date'),
                icon: WebTuiIcons.meetings,
                label: tr('Ngày', 'Date'),
                value: meetingLongDate(_start),
                onTap: _pickDate,
              ),
              Row(
                children: [
                  Expanded(
                    child: _PickerTile(
                      key: const Key('meeting_start_time'),
                      icon: WebTuiIcons.scheduleSend,
                      label: tr('Bắt đầu', 'Starts'),
                      value: meetingClock(_start),
                      onTap: () => _pickTime(start: true),
                    ),
                  ),
                  Expanded(
                    child: _PickerTile(
                      key: const Key('meeting_end_time'),
                      icon: WebTuiIcons.scheduleSend,
                      label: tr('Kết thúc', 'Ends'),
                      value: meetingSameDay(_start, _end)
                          ? meetingClock(_end)
                          : '${meetingClock(_end)} (+1)',
                      onTap: () => _pickTime(start: false),
                    ),
                  ),
                ],
              ),
              _ConflictBox(
                checking: _checkingConflicts,
                conflicts: _conflicts,
                names: _names,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('meeting_description'),
                controller: _description,
                minLines: 2,
                maxLines: 6,
                maxLength: maxMeetingDescriptionLength,
                decoration: InputDecoration(
                  labelText: tr('Nội dung', 'Description'),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('meeting_url'),
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: tr(
                    'Link họp ngoài (không bắt buộc)',
                    'External meeting link (optional)',
                  ),
                  hintText: 'https://meet.google.com/…',
                  helperText: tr(
                    'Để trống: dùng phòng video có sẵn.',
                    'Leave empty to use the built-in video room.',
                  ),
                ),
                validator: (value) => validateMeetingExternalUrl(value ?? ''),
              ),
              MeetingSectionTitle(tr('Nhắc họp', 'Reminders')),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final minutes in allowedReminderOffsets)
                    FilterChip(
                      key: Key('meeting_reminder_$minutes'),
                      label: Text(meetingReminderLabel(minutes)),
                      selected: _reminders.contains(minutes),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected:
                          !_reminders.contains(minutes) &&
                              _reminders.length >= maxReminderOffsets
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                _reminders.add(minutes);
                              } else {
                                _reminders.remove(minutes);
                              }
                            }),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(
                  tr(
                    'Chọn tối đa $maxReminderOffsets mốc.',
                    'Choose up to $maxReminderOffsets.',
                  ),
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
              if (!_isEdit) ..._recurrenceSection(),
              if (_isEdit && widget.existing!.recurrence != null) ...[
                MeetingSectionTitle(tr('Lặp lại', 'Repeat')),
                Text(
                  meetingRecurrenceLabel(widget.existing!.recurrence!),
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    key: const Key('meeting_form_error'),
                    style: WebTuiTypography.bodyMedium.copyWith(
                      color: MeetingTones.dangerText,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('meeting_save'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(meetingMinTapSize),
                  backgroundColor: MeetingTones.actionBackground,
                  foregroundColor: Colors.white,
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _isEdit
                            ? tr('Lưu thay đổi', 'Save changes')
                            : tr('Tạo họp', 'Create meeting'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _recurrenceSection() {
    final frequency = _frequency;
    return [
      MeetingSectionTitle(tr('Lặp lại', 'Repeat')),
      DropdownButtonFormField<MeetingRecurrenceFrequency?>(
        key: const Key('meeting_repeat'),
        initialValue: frequency,
        decoration: InputDecoration(labelText: tr('Lặp lại', 'Repeat')),
        items: [
          DropdownMenuItem(value: null, child: Text(tr('Không lặp', 'Never'))),
          DropdownMenuItem(
            value: MeetingRecurrenceFrequency.daily,
            child: Text(tr('Hằng ngày', 'Daily')),
          ),
          DropdownMenuItem(
            value: MeetingRecurrenceFrequency.weekly,
            child: Text(tr('Hằng tuần', 'Weekly')),
          ),
          DropdownMenuItem(
            value: MeetingRecurrenceFrequency.monthly,
            child: Text(tr('Hằng tháng', 'Monthly')),
          ),
        ],
        onChanged: (value) => setState(() {
          _frequency = value;
          if (value == MeetingRecurrenceFrequency.weekly && _weekdays.isEmpty) {
            _weekdays.add(_start.weekday);
          }
        }),
      ),
      if (frequency == MeetingRecurrenceFrequency.weekly) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                key: Key('meeting_weekday_$day'),
                label: Text(meetingWeekdayShort(day)),
                tooltip: meetingWeekdayLong(day),
                selected: _weekdays.contains(day),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (selected) => setState(() {
                  if (selected) {
                    _weekdays.add(day);
                  } else {
                    _weekdays.remove(day);
                  }
                }),
              ),
          ],
        ),
      ],
      if (frequency != null) ...[
        const SizedBox(height: 8),
        RadioGroup<_RepeatEnd>(
          groupValue: _repeatEnd,
          onChanged: (value) =>
              setState(() => _repeatEnd = value ?? _RepeatEnd.none),
          child: Column(
            children: [
              RadioListTile<_RepeatEnd>(
                key: const Key('meeting_repeat_end_none'),
                contentPadding: EdgeInsets.zero,
                value: _RepeatEnd.none,
                title: Text(tr('Không đặt ngày kết thúc', 'No end date')),
                subtitle: Text(
                  tr('Tối đa 1 năm', 'Up to 1 year'),
                  style: TextStyle(color: WebTuiColors.textSecondary),
                ),
              ),
              RadioListTile<_RepeatEnd>(
                key: const Key('meeting_repeat_end_until'),
                contentPadding: EdgeInsets.zero,
                value: _RepeatEnd.until,
                title: Text(
                  _until == null
                      ? tr('Đến ngày…', 'Until…')
                      : tr(
                          'Đến ${meetingLongDate(_until!)}',
                          'Until ${meetingLongDate(_until!)}',
                        ),
                ),
                secondary: IconButton(
                  tooltip: tr('Chọn ngày', 'Pick date'),
                  onPressed: () {
                    setState(() => _repeatEnd = _RepeatEnd.until);
                    _pickUntil();
                  },
                  icon: const Icon(WebTuiIcons.meetings),
                ),
              ),
              RadioListTile<_RepeatEnd>(
                key: const Key('meeting_repeat_end_count'),
                contentPadding: EdgeInsets.zero,
                value: _RepeatEnd.count,
                title: Text(tr('Sau số buổi', 'After a number of times')),
              ),
            ],
          ),
        ),
        if (_repeatEnd == _RepeatEnd.count)
          TextFormField(
            key: const Key('meeting_repeat_count'),
            controller: _count,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: tr('Số buổi (1–100)', 'Occurrences (1–100)'),
            ),
            validator: (value) {
              final count = int.tryParse(value?.trim() ?? '');
              if (count == null || count < 1 || count > maxMeetingOccurrences) {
                return tr(
                  'Số buổi từ 1 đến $maxMeetingOccurrences.',
                  'Enter 1 to $maxMeetingOccurrences.',
                );
              }
              return null;
            },
          ),
        if (frequency == MeetingRecurrenceFrequency.weekly && _weekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr(
                'Hãy chọn ít nhất một thứ trong tuần.',
                'Choose at least one day of the week.',
              ),
              style: WebTuiTypography.bodySmall.copyWith(
                color: MeetingTones.dangerText,
              ),
            ),
          ),
      ],
    ];
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.peopleMode, required this.onChanged});

  final bool peopleMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      key: const Key('meeting_target_mode'),
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(meetingMinTapSize, meetingMinTapSize),
        selectedForegroundColor: MeetingTones.accentText,
      ),
      segments: [
        ButtonSegment(
          value: false,
          label: Text(tr('Nhóm có sẵn', 'Existing group')),
        ),
        ButtonSegment(value: true, label: Text(tr('Chọn người', 'People'))),
      ],
      selected: {peopleMode},
      showSelectedIcon: false,
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      minTileHeight: 56,
      leading: Icon(icon, color: WebTuiColors.textSecondary),
      title: Text(
        label,
        style: WebTuiTypography.bodySmall.copyWith(
          color: WebTuiColors.textSecondary,
        ),
      ),
      subtitle: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: WebTuiTypography.bodyMedium.copyWith(
          color: WebTuiColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: onTap == null
          ? null
          : Icon(WebTuiIcons.forward, color: WebTuiColors.textSecondary),
      onTap: onTap,
    );
  }
}

class _ConflictBox extends StatelessWidget {
  const _ConflictBox({
    required this.checking,
    required this.conflicts,
    required this.names,
  });

  final bool checking;
  final List<MeetingConflict> conflicts;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    if (conflicts.isEmpty) {
      return checking
          ? Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Text(
                tr('Đang kiểm tra trùng lịch…', 'Checking for conflicts…'),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            )
          : const SizedBox.shrink();
    }
    return Container(
      key: const Key('meeting_conflicts'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MeetingTones.warningBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Trùng lịch (${conflicts.length}) — vẫn có thể lưu',
              'Schedule conflicts (${conflicts.length}) — you can still save',
            ),
            style: WebTuiTypography.bodyMedium.copyWith(
              color: MeetingTones.warningText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          for (final conflict in conflicts.take(8))
            Text(
              _line(conflict),
              style: WebTuiTypography.bodySmall.copyWith(
                color: MeetingTones.warningText,
              ),
            ),
          if (conflicts.length > 8)
            Text(
              tr(
                '… và ${conflicts.length - 8} cuộc khác',
                '… and ${conflicts.length - 8} more',
              ),
              style: WebTuiTypography.bodySmall.copyWith(
                color: MeetingTones.warningText,
              ),
            ),
        ],
      ),
    );
  }

  String _line(MeetingConflict conflict) {
    final name = names[conflict.userId] ?? tr('Một người', 'Someone');
    final end = conflict.endsAt;
    final time = end == null
        ? meetingClock(conflict.startsAt)
        : '${meetingClock(conflict.startsAt)}–${meetingClock(end)}';
    final title = conflict.title?.trim() ?? '';
    return title.isEmpty
        ? tr('• $name: đã có họp $time', '• $name: busy $time')
        : tr('• $name: «$title» $time', '• $name: “$title” $time');
  }
}

class _GroupPickerSheet extends ConsumerWidget {
  const _GroupPickerSheet({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(meetingGroupsProvider(workspaceId));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                tr('Chọn nhóm', 'Choose a group'),
                style: WebTuiTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: WebTuiColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(meetingErrorText(error)),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(meetingGroupsProvider(workspaceId)),
                        child: Text(tr('Thử lại', 'Retry')),
                      ),
                    ],
                  ),
                ),
                data: (groups) => groups.isEmpty
                    ? Center(
                        child: Text(
                          tr(
                            'Bạn chưa ở nhóm nào. Hãy chọn người.',
                            'You\'re not in any group yet. Choose people instead.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: WebTuiColors.textSecondary),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final group in groups)
                            ListTile(
                              key: Key('meeting_group_${group.channelId}'),
                              minTileHeight: 56,
                              leading: MeetingInitialAvatar(name: group.name),
                              title: Text(group.name),
                              subtitle: group.memberCount > 0
                                  ? Text(
                                      tr(
                                        '${group.memberCount} thành viên',
                                        '${group.memberCount} members',
                                      ),
                                      style: TextStyle(
                                        color: WebTuiColors.textSecondary,
                                      ),
                                    )
                                  : null,
                              onTap: () => Navigator.of(context).pop(group),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeoplePickerSheet extends StatefulWidget {
  const _PeoplePickerSheet({required this.people, required this.selected});

  final List<MeetingPerson> people;
  final Set<String> selected;

  @override
  State<_PeoplePickerSheet> createState() => _PeoplePickerSheetState();
}

class _PeoplePickerSheetState extends State<_PeoplePickerSheet> {
  late final Set<String> _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visible = [
      for (final person in widget.people)
        if (query.isEmpty || person.displayName.toLowerCase().contains(query))
          person,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(
                          'Người tham dự (${_selected.length})',
                          'Attendees (${_selected.length})',
                        ),
                        style: WebTuiTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          color: WebTuiColors.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('meeting_people_done'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          meetingMinTapSize,
                          meetingMinTapSize,
                        ),
                        foregroundColor: MeetingTones.accentText,
                      ),
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: Text(tr('Xong', 'Done')),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(WebTuiIcons.search),
                    hintText: tr('Tìm theo tên', 'Search by name'),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final person in visible)
                      CheckboxListTile(
                        key: Key('meeting_person_${person.userId}'),
                        value: _selected.contains(person.userId),
                        secondary: MeetingInitialAvatar(
                          name: person.displayName,
                        ),
                        title: Text(person.displayName),
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            _selected.add(person.userId);
                          } else {
                            _selected.remove(person.userId);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
