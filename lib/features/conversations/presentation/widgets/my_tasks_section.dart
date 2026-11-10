import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/entities/conversation_summary.dart';
import '../models/task_due_label.dart';
import 'collaboration_room_sheet.dart';

/// Việc giao cho tôi ở mọi phòng (đang mở; `includeFinished` thì cả việc đã xong).
final myAssignedTasksProvider = FutureProvider.autoDispose
    .family<
      Result<List<CollaborationTask>>,
      ({String workspaceId, bool includeFinished})
    >((ref, key) {
      return ref
          .watch(listAssignedTasksUseCaseProvider)
          .execute(
            workspaceId: key.workspaceId,
            includeFinished: key.includeFinished,
          );
    });

/// Đầu tab Công việc: tối đa 3 việc gần hạn nhất giao cho tôi, "Xem tất cả".
/// Máy chủ cũ chưa có API thì ẩn hẳn.
class MyTasksSection extends ConsumerWidget {
  const MyTasksSection({
    required this.workspaceId,
    this.rooms = const [],
    super.key,
  });

  final String workspaceId;
  final List<ConversationSummary> rooms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (workspaceId: workspaceId, includeFinished: false);
    final async = ref.watch(myAssignedTasksProvider(key));
    final result = async.valueOrNull;
    if (result case FailureResult(
      failure: final failure,
    ) when failure.code == 'TASK_FEATURE_UNSUPPORTED') {
      return const SizedBox.shrink();
    }
    final tasks = result?.valueOrNull ?? const <CollaborationTask>[];
    final now = DateTime.now();

    return Container(
      key: const Key('my_tasks_section'),
      margin: const EdgeInsets.only(bottom: WebTuiSpacing.lg),
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        border: Border.all(color: WebTuiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.assignment_ind_outlined,
                color: WebTuiColors.primary,
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: Text(
                  tasks.isEmpty
                      ? 'Việc của tôi'
                      : 'Việc của tôi · ${tasks.length}',
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (tasks.isNotEmpty)
                TextButton(
                  key: const Key('my_tasks_show_all'),
                  onPressed: () => _showAll(context),
                  child: const Text('Xem tất cả'),
                ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          if (async.isLoading && result == null)
            const Padding(
              padding: EdgeInsets.all(WebTuiSpacing.md),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (result case FailureResult(failure: final failure))
            Row(
              children: [
                Expanded(
                  child: Text(
                    failure.message,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.danger,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(myAssignedTasksProvider(key)),
                  child: const Text('Thử lại'),
                ),
              ],
            )
          else if (tasks.isEmpty)
            Text(
              'Chưa có việc nào giao cho bạn.',
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            )
          else
            for (final task in tasks.take(3))
              AssignedTaskTile(
                task: task,
                now: now,
                onTap: () => _openTask(context, ref, task),
              ),
        ],
      ),
    );
  }

  Future<void> _openTask(
    BuildContext context,
    WidgetRef ref,
    CollaborationTask task,
  ) async {
    await openAssignedTask(context, task: task, rooms: rooms);
    ref.invalidate(myAssignedTasksProvider);
  }

  Future<void> _showAll(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: WebTuiColors.surface,
      builder: (_) =>
          _AllAssignedTasksSheet(workspaceId: workspaceId, rooms: rooms),
    );
  }
}

/// Mở phòng của việc ở tab Task, mở sẵn việc đó.
Future<void> openAssignedTask(
  BuildContext context, {
  required CollaborationTask task,
  List<ConversationSummary> rooms = const [],
}) {
  final room = rooms
      .where((item) => item.channelId == task.channelId)
      .firstOrNull;
  return showCollaborationRoomSheet(
    context,
    workspaceId: task.workspaceId,
    channelId: task.channelId,
    title: room?.title ?? task.channelName ?? 'Phòng làm việc',
    conversation: room,
    initialTab: collaborationTasksTabIndex,
    focusTaskId: task.id,
  );
}

class AssignedTaskTile extends StatelessWidget {
  const AssignedTaskTile({
    required this.task,
    required this.now,
    required this.onTap,
    super.key,
  });

  final CollaborationTask task;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final urgency = taskDueUrgency(task.dueAt, now, active: task.isActive);
    final dueColor = switch (urgency) {
      TaskDueUrgency.overdue => WebTuiColors.danger,
      TaskDueUrgency.soon => WebTuiColors.accentAmber,
      TaskDueUrgency.none => WebTuiColors.textSecondary,
    };
    final status = task.taskStatus;
    final details = [
      if (task.channelName?.trim().isNotEmpty == true) task.channelName!.trim(),
      status.label,
    ].join(' · ');
    return ListTile(
      key: Key('assigned_task_${task.id}'),
      contentPadding: EdgeInsets.zero,
      minTileHeight: 52,
      onTap: onTap,
      leading: Icon(
        switch (status) {
          CollaborationTaskStatus.inProgress => Icons.timelapse_rounded,
          CollaborationTaskStatus.done => Icons.check_circle_rounded,
          CollaborationTaskStatus.cancelled => Icons.cancel_outlined,
          CollaborationTaskStatus.open => Icons.radio_button_unchecked_rounded,
        },
        color: status == CollaborationTaskStatus.inProgress
            ? WebTuiColors.accentAmber
            : WebTuiColors.textSecondary,
      ),
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: task.dueAt == null
          ? null
          : Text(
              urgency == TaskDueUrgency.overdue
                  ? 'Quá hạn\n${formatTaskDue(task.dueAt!, now)}'
                  : formatTaskDue(task.dueAt!, now),
              textAlign: TextAlign.end,
              style: WebTuiTypography.bodySmall.copyWith(
                color: dueColor,
                fontWeight: urgency == TaskDueUrgency.none
                    ? FontWeight.w400
                    : FontWeight.w700,
              ),
            ),
    );
  }
}

class _AllAssignedTasksSheet extends ConsumerStatefulWidget {
  const _AllAssignedTasksSheet({
    required this.workspaceId,
    required this.rooms,
  });

  final String workspaceId;
  final List<ConversationSummary> rooms;

  @override
  ConsumerState<_AllAssignedTasksSheet> createState() =>
      _AllAssignedTasksSheetState();
}

class _AllAssignedTasksSheetState
    extends ConsumerState<_AllAssignedTasksSheet> {
  bool _includeFinished = false;

  @override
  Widget build(BuildContext context) {
    final key = (
      workspaceId: widget.workspaceId,
      includeFinished: _includeFinished,
    );
    final async = ref.watch(myAssignedTasksProvider(key));
    final result = async.valueOrNull;
    final now = DateTime.now();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Việc của tôi',
                    style: WebTuiTypography.titleMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilterChip(
                  key: const Key('my_tasks_include_finished'),
                  label: const Text('Cả việc đã xong'),
                  selected: _includeFinished,
                  onSelected: (value) =>
                      setState(() => _includeFinished = value),
                ),
              ],
            ),
          ),
          Expanded(child: _body(async.isLoading, result, key, now)),
        ],
      ),
    );
  }

  Widget _body(
    bool loading,
    Result<List<CollaborationTask>>? result,
    ({String workspaceId, bool includeFinished}) key,
    DateTime now,
  ) {
    if (loading && result == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (result case FailureResult(failure: final failure)) {
      return WebTuiErrorState(
        title: 'Chưa tải được việc của bạn',
        message: failure.message,
        onRetry: () => ref.invalidate(myAssignedTasksProvider(key)),
      );
    }
    final tasks = result?.valueOrNull ?? const <CollaborationTask>[];
    if (tasks.isEmpty) {
      return const WebTuiEmptyState(
        title: 'Không có việc nào',
        message: 'Việc được giao cho bạn ở mọi phòng sẽ hiện ở đây.',
        icon: Icons.assignment_turned_in_outlined,
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
      children: [
        for (final task in tasks)
          AssignedTaskTile(
            task: task,
            now: now,
            onTap: () async {
              await openAssignedTask(context, task: task, rooms: widget.rooms);
              ref.invalidate(myAssignedTasksProvider);
            },
          ),
      ],
    );
  }
}
