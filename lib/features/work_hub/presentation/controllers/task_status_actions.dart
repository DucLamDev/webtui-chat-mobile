import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../../conversations/domain/repositories/collaboration_task_repository.dart';

/// Trạng thái kế tiếp khi bấm ô vuông: chưa nhận → đã nhận → hoàn thành.
CollaborationTaskStatus? nextAssignedTaskStatus(CollaborationTaskStatus now) {
  return switch (now) {
    CollaborationTaskStatus.open => CollaborationTaskStatus.inProgress,
    CollaborationTaskStatus.inProgress => CollaborationTaskStatus.done,
    _ => null,
  };
}

/// Đổi trạng thái một việc của tôi, báo bằng SnackBar có "Hoàn tác". [onChanged]
/// chạy sau mỗi lần đổi (kể cả hoàn tác) để màn tải lại số đếm.
Future<void> advanceAssignedTask(
  BuildContext context,
  WidgetRef ref,
  CollaborationTask task, {
  required VoidCallback onChanged,
}) async {
  final previous = task.taskStatus;
  final next = nextAssignedTaskStatus(previous);
  if (next == null) return;
  final messenger = ScaffoldMessenger.of(context);
  Future<String?> apply(CollaborationTaskStatus status) async {
    final result = await ref
        .read(updateChannelTaskUseCaseProvider)
        .execute(
          workspaceId: task.workspaceId,
          channelId: task.channelId,
          taskId: task.id,
          changes: CollaborationTaskChanges(status: status),
        );
    return result.failureOrNull == null
        ? null
        : userFacingErrorMessage(result.failureOrNull!);
  }

  final error = await apply(next);
  onChanged();
  messenger.hideCurrentSnackBar();
  if (error != null) {
    messenger.showSnackBar(SnackBar(content: Text(error)));
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        next == CollaborationTaskStatus.done
            ? 'Đã hoàn thành "${task.title}"'
            : 'Đã nhận việc "${task.title}"',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      action: SnackBarAction(
        label: 'Hoàn tác',
        onPressed: () async {
          final undoError = await apply(previous);
          onChanged();
          if (undoError != null) {
            messenger.showSnackBar(SnackBar(content: Text(undoError)));
          }
        },
      ),
    ),
  );
}
