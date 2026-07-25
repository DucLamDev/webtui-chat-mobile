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
      )..load();
    });

final class NotificationCenterState {
  const NotificationCenterState({
    this.notifications = const [],
    this.isLoading = false,
    this.isMarkingAll = false,
    this.errorMessage,
  });

  final List<MobileNotification> notifications;
  final bool isLoading;
  final bool isMarkingAll;
  final String? errorMessage;

  int get unreadCount =>
      notifications.where((notification) => !notification.isRead).length;

  NotificationCenterState copyWith({
    List<MobileNotification>? notifications,
    bool? isLoading,
    bool? isMarkingAll,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotificationCenterState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      isMarkingAll: isMarkingAll ?? this.isMarkingAll,
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
  }) : _workspaceId = workspaceId,
       _listUseCase = listUseCase,
       _markReadUseCase = markReadUseCase,
       _markAllReadUseCase = markAllReadUseCase,
       super(const NotificationCenterState());

  final String _workspaceId;
  final ListNotificationsUseCase _listUseCase;
  final MarkNotificationReadUseCase _markReadUseCase;
  final MarkAllNotificationsReadUseCase _markAllReadUseCase;

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
}
