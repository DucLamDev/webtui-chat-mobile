import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../../conversations/domain/repositories/collaboration_task_repository.dart';
import '../../domain/entities/work_hub.dart';
import '../../domain/repositories/work_hub_repository.dart';

const maxShortcutTitleLength = 40;
const maxShortcutUrlLength = 2048;
const maxShortcutCount = 24;

/// Tên lối tắt: bỏ khoảng trắng hai đầu, 1–40 ký tự. Trả câu báo lỗi hoặc `null`.
String? validateShortcutTitle(String raw) {
  final title = raw.trim();
  if (title.isEmpty) {
    return tr('Hãy nhập tên lối tắt.', 'Enter a shortcut name.');
  }
  if (title.runes.length > maxShortcutTitleLength) {
    return tr(
      'Tên lối tắt tối đa $maxShortcutTitleLength ký tự.',
      'Shortcut names can be up to $maxShortcutTitleLength characters.',
    );
  }
  return null;
}

/// Đường dẫn lối tắt: chỉ https, có địa chỉ máy chủ, không kèm tài khoản.
String? validateShortcutUrl(String raw) {
  final url = raw.trim();
  final needHttps = tr(
    'Đường dẫn phải bắt đầu bằng https://',
    'The link must start with https://',
  );
  if (url.isEmpty) return needHttps;
  if (url.length > maxShortcutUrlLength) {
    return tr(
      'Đường dẫn tối đa $maxShortcutUrlLength ký tự.',
      'Links can be up to $maxShortcutUrlLength characters.',
    );
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      !url.toLowerCase().startsWith('https://') ||
      uri.host.isEmpty) {
    return needHttps;
  }
  if (uri.userInfo.isNotEmpty) {
    return tr(
      'Đường dẫn không được chứa tên đăng nhập hoặc mật khẩu.',
      'The link can\'t contain a username or password.',
    );
  }
  return null;
}

/// Đổi lỗi máy chủ của lối tắt sang câu dễ hiểu.
Failure _friendlyShortcutFailure(Failure failure) {
  if (failure.kind == FailureKind.forbidden) {
    return failure.copyWith(
      message: tr(
        'Chỉ quản trị viên mới được thay đổi lối tắt.',
        'Only administrators can change shortcuts.',
      ),
    );
  }
  if (failure.hasCode('SHORTCUT_LIMIT_REACHED')) {
    return failure.copyWith(
      message: tr(
        'Đã đủ $maxShortcutCount lối tắt. Hãy xoá bớt trước khi thêm.',
        'You have $maxShortcutCount shortcuts already. Delete some before adding more.',
      ),
    );
  }
  if (failure.hasCode('SHORTCUT_NOT_FOUND')) {
    return failure.copyWith(
      message: tr(
        'Lối tắt này không còn nữa. Hãy kéo để tải lại.',
        'This shortcut no longer exists. Pull to reload.',
      ),
    );
  }
  if (failure.kind == FailureKind.validation) {
    final lower = failure.message.toLowerCase();
    final ascii = !failure.message.runes.any((rune) => rune > 0x7f);
    return failure.copyWith(
      message: ascii || lower.isEmpty
          ? tr(
              'Thông tin lối tắt chưa hợp lệ. Hãy kiểm tra tên và đường dẫn.',
              'The shortcut details are invalid. Check the name and link.',
            )
          : failure.message,
    );
  }
  return failure;
}

Result<T> _friendly<T>(Result<T> result) {
  return switch (result) {
    FailureResult<T>(failure: final failure) => FailureResult(
      _friendlyShortcutFailure(failure),
    ),
    _ => result,
  };
}

final class ListAppShortcutsUseCase {
  const ListAppShortcutsUseCase(this._repository);

  final WorkHubRepository _repository;

  Future<Result<AppShortcutList>> execute({required String workspaceId}) async {
    return _friendly(await _repository.listShortcuts(workspaceId: workspaceId));
  }
}

/// Thêm (khi `shortcutId == null`) hoặc sửa lối tắt, kiểm đầu vào trước.
final class SaveAppShortcutUseCase {
  const SaveAppShortcutUseCase(this._repository);

  final WorkHubRepository _repository;

  Future<Result<AppShortcut>> execute({
    required String workspaceId,
    required AppShortcutDraft draft,
    String? shortcutId,
  }) async {
    final titleError = validateShortcutTitle(draft.title);
    if (titleError != null) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: titleError,
          code: 'SHORTCUT_TITLE_INVALID',
        ),
      );
    }
    final urlError = validateShortcutUrl(draft.url);
    if (urlError != null) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: urlError,
          code: 'SHORTCUT_URL_INVALID',
        ),
      );
    }
    final clean = AppShortcutDraft(
      title: draft.title.trim(),
      url: draft.url.trim(),
      icon: draft.icon,
      color: draft.color,
    );
    final result = shortcutId == null
        ? await _repository.createShortcut(
            workspaceId: workspaceId,
            draft: clean,
          )
        : await _repository.updateShortcut(
            workspaceId: workspaceId,
            shortcutId: shortcutId,
            draft: clean,
          );
    return _friendly(result);
  }
}

final class DeleteAppShortcutUseCase {
  const DeleteAppShortcutUseCase(this._repository);

  final WorkHubRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String shortcutId,
  }) async {
    final result = await _repository.deleteShortcut(
      workspaceId: workspaceId,
      shortcutId: shortcutId,
    );
    // Đã bị xoá ở nơi khác: coi như xong.
    if (result case FailureResult<void>(
      failure: Failure(code: 'SHORTCUT_NOT_FOUND'),
    )) {
      return const Success(null);
    }
    return _friendly(result);
  }
}

final class ReorderAppShortcutsUseCase {
  const ReorderAppShortcutsUseCase(this._repository);

  final WorkHubRepository _repository;

  Future<Result<List<AppShortcut>>> execute({
    required String workspaceId,
    required List<String> ids,
  }) async {
    return _friendly(
      await _repository.reorderShortcuts(workspaceId: workspaceId, ids: ids),
    );
  }
}

final class ListUpcomingMeetingsUseCase {
  const ListUpcomingMeetingsUseCase(this._repository);

  final WorkHubRepository _repository;

  Future<Result<List<UpcomingMeeting>>> execute({required String workspaceId}) {
    return _repository.upcomingMeetings(workspaceId: workspaceId);
  }
}

final class ListSharedFilesUseCase {
  const ListSharedFilesUseCase(this._repository);

  final WorkHubRepository _repository;

  Future<Result<List<SharedFile>>> execute({required String workspaceId}) {
    return _repository.listFiles(workspaceId: workspaceId);
  }
}

/// Xin đường dẫn phát dần cho một tệp chia sẻ.
final class CreateSharedFileStreamLinkUseCase {
  const CreateSharedFileStreamLinkUseCase(this._repository);

  final WorkHubRepository _repository;

  Future<Result<SharedFileStreamLink>> execute({
    required String workspaceId,
    required String fileId,
  }) {
    return _repository.createFileStreamLink(
      workspaceId: workspaceId,
      fileId: fileId,
    );
  }
}

/// Số đếm + tối đa 3 việc chưa xong gần hạn nhất cho thẻ "Việc của tôi".
final class MyTasksOverview {
  const MyTasksOverview({required this.summary, required this.upcoming});

  final AssignedTaskSummary summary;
  final List<CollaborationTask> upcoming;
}

final class LoadMyTasksOverviewUseCase {
  const LoadMyTasksOverviewUseCase(this._workHub, this._tasks);

  final WorkHubRepository _workHub;
  final CollaborationTaskRepository _tasks;

  /// [serverSummary]: máy chủ có `work_hub` (đếm bằng API riêng); không thì tự
  /// đếm từ danh sách việc.
  Future<Result<MyTasksOverview>> execute({
    required String workspaceId,
    required bool serverSummary,
    DateTime? now,
  }) async {
    final clock = (now ?? DateTime.now()).toUtc();
    final listResult = await _tasks.listAssignedTasks(
      workspaceId: workspaceId,
      status: serverSummary ? 'active' : 'all',
    );
    if (listResult case FailureResult<List<CollaborationTask>>(
      failure: final failure,
    )) {
      return FailureResult(failure);
    }
    final tasks = listResult.valueOrNull ?? const <CollaborationTask>[];
    final AssignedTaskSummary summary;
    if (serverSummary) {
      final summaryResult = await _workHub.assignedTaskSummary(
        workspaceId: workspaceId,
      );
      if (summaryResult case FailureResult<AssignedTaskSummary>(
        failure: final failure,
      )) {
        return FailureResult(failure);
      }
      summary = summaryResult.valueOrNull ?? const AssignedTaskSummary();
    } else {
      summary = countAssignedTasks(tasks, clock);
    }
    return Success(
      MyTasksOverview(summary: summary, upcoming: nearestDueTasks(tasks)),
    );
  }
}

/// Ô "Hoàn thành" chỉ tính việc xong trong 7 ngày qua (máy chủ đếm `done_7d`
/// cùng cách); màn "Việc của tôi" lọc cùng khoảng để hai nơi khớp số.
const recentlyDoneWindow = Duration(days: 7);

/// Việc đã xong trong [recentlyDoneWindow] tính tới [now].
bool isRecentlyDone(CollaborationTask task, DateTime now) {
  if (task.taskStatus != CollaborationTaskStatus.done) return false;
  final completedAt = task.completedAt;
  return completedAt != null &&
      completedAt.toUtc().isAfter(now.toUtc().subtract(recentlyDoneWindow));
}

/// Tự đếm khi máy chủ chưa có API đếm.
AssignedTaskSummary countAssignedTasks(
  List<CollaborationTask> tasks,
  DateTime now,
) {
  var open = 0;
  var inProgress = 0;
  var done = 0;
  for (final task in tasks) {
    switch (task.taskStatus) {
      case CollaborationTaskStatus.open:
        open++;
      case CollaborationTaskStatus.inProgress:
        inProgress++;
      case CollaborationTaskStatus.done:
        if (isRecentlyDone(task, now)) done++;
      case CollaborationTaskStatus.cancelled:
        break;
    }
  }
  return AssignedTaskSummary(
    open: open,
    inProgress: inProgress,
    doneLast7Days: done,
  );
}

/// Tối đa [limit] việc chưa xong, hạn gần nhất trước, việc không hạn xếp sau.
List<CollaborationTask> nearestDueTasks(
  List<CollaborationTask> tasks, {
  int limit = 3,
}) {
  final active = tasks.where((task) => task.isActive).toList();
  active.sort((a, b) {
    final left = a.dueAt;
    final right = b.dueAt;
    if (left == null && right == null) {
      return b.createdAt.compareTo(a.createdAt);
    }
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  });
  return active.take(limit).toList(growable: false);
}
