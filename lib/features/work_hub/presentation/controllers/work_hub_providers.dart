import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../conversations/domain/entities/collaboration_room.dart';
import '../../application/use_cases/work_hub_use_cases.dart';
import '../../domain/entities/work_hub.dart';

/// Máy chủ có API lối tắt, đếm việc và lịch họp chung (`work_hub`).
final workHubEnabledProvider = Provider<bool>((ref) {
  return ref.watch(activeServerDiscoveryProvider)?.capabilities.workHub == true;
});

T _unwrap<T>(Result<T> result) {
  return result.when(
    success: (value) => value,
    failure: (failure) => throw FailureException(failure),
  );
}

/// Câu báo lỗi tiếng Việt cho màn Công việc.
String workHubErrorText(Object error) {
  if (error is FailureException) return userFacingErrorMessage(error.failure);
  return userFacingErrorMessage(error);
}

/// Lối tắt + quyền quản lý. Máy chủ cũ (không `work_hub`): danh sách rỗng,
/// không quản lý được, không gọi API.
final appShortcutsProvider = FutureProvider.autoDispose
    .family<AppShortcutList, String>((ref, workspaceId) async {
      if (!ref.watch(workHubEnabledProvider)) {
        return const AppShortcutList(shortcuts: [], canManage: false);
      }
      return _unwrap(
        await ref
            .watch(listAppShortcutsUseCaseProvider)
            .execute(workspaceId: workspaceId),
      );
    });

/// Số đếm + 3 việc gần hạn cho thẻ "Việc của tôi".
final myTasksOverviewProvider = FutureProvider.autoDispose
    .family<MyTasksOverview, String>((ref, workspaceId) async {
      return _unwrap(
        await ref
            .watch(loadMyTasksOverviewUseCaseProvider)
            .execute(
              workspaceId: workspaceId,
              serverSummary: ref.watch(workHubEnabledProvider),
            ),
      );
    });

/// Toàn bộ việc giao cho tôi (gồm đã xong) cho màn "Việc của tôi".
final myAssignedTasksProvider = FutureProvider.autoDispose
    .family<List<CollaborationTask>, String>((ref, workspaceId) async {
      return _unwrap(
        await ref
            .watch(listAssignedTasksUseCaseProvider)
            .execute(workspaceId: workspaceId, includeFinished: true),
      );
    });

final upcomingMeetingsProvider = FutureProvider.autoDispose
    .family<List<UpcomingMeeting>, String>((ref, workspaceId) async {
      return _unwrap(
        await ref
            .watch(listUpcomingMeetingsUseCaseProvider)
            .execute(workspaceId: workspaceId),
      );
    });

final sharedFilesProvider = FutureProvider.autoDispose
    .family<List<SharedFile>, String>((ref, workspaceId) async {
      return _unwrap(
        await ref
            .watch(listSharedFilesUseCaseProvider)
            .execute(workspaceId: workspaceId),
      );
    });
