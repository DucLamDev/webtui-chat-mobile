import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/notification_use_cases.dart';
import '../../domain/entities/mobile_notification.dart';

final notificationCenterControllerProvider = StateNotifierProvider.autoDispose
    .family<NotificationCenterController, NotificationCenterState, String>((
      ref,
      workspaceId,
    ) {
      return NotificationCenterController(
        workspaceId: workspaceId,
        listUseCase: ref.watch(listNotificationsUseCaseProvider),
        markReadUseCase: ref.watch(markNotificationReadUseCaseProvider),
        markAllReadUseCase: ref.watch(markAllNotificationsReadUseCaseProvider),
        deleteUseCase: ref.watch(deleteNotificationUseCaseProvider),
        deleteAllUseCase: ref.watch(deleteAllNotificationsUseCaseProvider),
      )..load();
    });

final class NotificationCenterState {
  const NotificationCenterState({
    this.notifications = const [],
    this.isLoading = false,
    this.isMarkingAll = false,
    this.isDeletingAll = false,
    this.errorMessage,
  });

  final List<MobileNotification> notifications;
  final bool isLoading;
  final bool isMarkingAll;
  final bool isDeletingAll;
  final String? errorMessage;

  int get unreadCount =>
      notifications.where((notification) => !notification.isRead).length;

  NotificationCenterState copyWith({
    List<MobileNotification>? notifications,
    bool? isLoading,
    bool? isMarkingAll,
    bool? isDeletingAll,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotificationCenterState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      isMarkingAll: isMarkingAll ?? this.isMarkingAll,
      isDeletingAll: isDeletingAll ?? this.isDeletingAll,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final class NotificationCenterController
    extends StateNotifier<NotificationCenterState> {
  NotificationCenterController({
    required String workspaceId,
    required ListNotificationsUseCase listUseCase,
    required MarkNotificationReadUseCase markReadUseCase,
    required MarkAllNotificationsReadUseCase markAllReadUseCase,
    required DeleteNotificationUseCase deleteUseCase,
    required DeleteAllNotificationsUseCase deleteAllUseCase,
  }) : _workspaceId = workspaceId,
       _listUseCase = listUseCase,
       _markReadUseCase = markReadUseCase,
       _markAllReadUseCase = markAllReadUseCase,
       _deleteUseCase = deleteUseCase,
       _deleteAllUseCase = deleteAllUseCase,
       super(const NotificationCenterState());

  final String _workspaceId;
  final ListNotificationsUseCase _listUseCase;
  final MarkNotificationReadUseCase _markReadUseCase;
  final MarkAllNotificationsReadUseCase _markAllReadUseCase;
  final DeleteNotificationUseCase _deleteUseCase;
  final DeleteAllNotificationsUseCase _deleteAllUseCase;

  Future<void> load() async {
    if (_workspaceId.trim().isEmpty) {
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _listUseCase.execute(workspaceId: _workspaceId);
    switch (result) {
      case Success<List<MobileNotification>>(value: final notifications):
        state = state.copyWith(
          notifications: notifications,
          isLoading: false,
          clearError: true,
        );
      case FailureResult<List<MobileNotification>>(failure: final failure):
        state = state.copyWith(isLoading: false, errorMessage: failure.message);
    }
  }

  Future<void> markRead(MobileNotification notification) async {
    if (notification.isRead) {
      return;
    }
    final readAt = DateTime.now().toUtc();
    state = state.copyWith(
      notifications: state.notifications
          .map(
            (item) => item.id == notification.id
                ? item.copyWith(readAt: readAt)
                : item,
          )
          .toList(growable: false),
      clearError: true,
    );
    final result = await _markReadUseCase.execute(
      notificationId: notification.id,
    );
    switch (result) {
      case Success<void>():
        return;
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> markAllRead() async {
    if (state.notifications.every((notification) => notification.isRead)) {
      return;
    }
    state = state.copyWith(isMarkingAll: true, clearError: true);
    final result = await _markAllReadUseCase.execute(workspaceId: _workspaceId);
    switch (result) {
      case Success<void>():
        final readAt = DateTime.now().toUtc();
        state = state.copyWith(
          isMarkingAll: false,
          notifications: state.notifications
              .map((notification) => notification.copyWith(readAt: readAt))
              .toList(growable: false),
          clearError: true,
        );
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(
          isMarkingAll: false,
          errorMessage: failure.message,
        );
    }
  }

  /// Xoá một thông báo: ẩn ngay khỏi danh sách, lỗi thì trả lại đúng chỗ cũ.
  /// Trả câu báo lỗi cho màn hình hiện (null là xoá xong).
  Future<String?> delete(MobileNotification notification) async {
    final index = state.notifications.indexWhere(
      (item) => item.id == notification.id,
    );
    if (index < 0) return null;
    final removed = state.notifications[index];
    state = state.copyWith(
      notifications: [
        for (final item in state.notifications)
          if (item.id != notification.id) item,
      ],
      clearError: true,
    );
    final result = await _deleteUseCase.execute(
      notificationId: notification.id,
    );
    switch (result) {
      case Success<void>():
        return null;
      case FailureResult<void>(failure: final failure):
        if (!mounted) return failure.message;
        final restored = [...state.notifications];
        restored.insert(index.clamp(0, restored.length), removed);
        state = state.copyWith(notifications: restored);
        return failure.message;
    }
  }

  /// Xoá mọi thông báo của workspace đang xem. Trả câu báo lỗi (null là xong).
  Future<String?> deleteAll() async {
    if (state.notifications.isEmpty || state.isDeletingAll) return null;
    state = state.copyWith(isDeletingAll: true, clearError: true);
    final result = await _deleteAllUseCase.execute(workspaceId: _workspaceId);
    if (!mounted) return null;
    switch (result) {
      case Success<void>():
        state = state.copyWith(isDeletingAll: false, notifications: const []);
        return null;
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(isDeletingAll: false);
        return failure.message;
    }
  }
}
