import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/mobile_notification.dart';
import '../../domain/repositories/notification_repository.dart';

final class ListNotificationsUseCase {
  const ListNotificationsUseCase(this._repository);

  final NotificationRepository _repository;

  Future<Result<List<MobileNotification>>> execute({
    required String workspaceId,
    int limit = 50,
  }) {
    return _repository.listNotifications(
      workspaceId: workspaceId,
      limit: limit,
    );
  }
}

final class MarkNotificationReadUseCase {
  const MarkNotificationReadUseCase(this._repository);

  final NotificationRepository _repository;

  Future<Result<void>> execute({required String notificationId}) {
    return _repository.markRead(notificationId: notificationId);
  }
}

final class MarkAllNotificationsReadUseCase {
  const MarkAllNotificationsReadUseCase(this._repository);

  final NotificationRepository _repository;

  Future<Result<void>> execute({required String workspaceId}) {
    return _repository.markAllRead(workspaceId: workspaceId);
  }
}

/// Máy chủ cũ chưa có API xoá thông báo trả 404 không kèm mã lỗi của thông báo.
const notificationDeleteUnsupportedMessage =
    'Máy chủ chưa hỗ trợ xoá thông báo. Hãy nhờ quản trị cập nhật máy chủ.';

Result<void> _deleteResult(Result<void> result) {
  return switch (result) {
    Success<void>() => result,
    // Thông báo đã bị xoá ở thiết bị khác: coi như xoá xong.
    FailureResult<void>(failure: Failure(code: 'NOTIFICATION_NOT_FOUND')) =>
      const Success(null),
    FailureResult<void>(failure: final failure)
        when failure.kind == FailureKind.notFound =>
      FailureResult(
        failure.copyWith(
          code: 'NOTIFICATION_DELETE_UNSUPPORTED',
          message: notificationDeleteUnsupportedMessage,
        ),
      ),
    FailureResult<void>() => result,
  };
}

final class DeleteNotificationUseCase {
  const DeleteNotificationUseCase(this._repository);

  final NotificationRepository _repository;

  Future<Result<void>> execute({required String notificationId}) async {
    final id = notificationId.trim();
    if (id.isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Không xác định được thông báo cần xoá.',
          code: 'NOTIFICATION_ID_REQUIRED',
        ),
      );
    }
    return _deleteResult(
      await _repository.deleteNotification(notificationId: id),
    );
  }
}

final class DeleteAllNotificationsUseCase {
  const DeleteAllNotificationsUseCase(this._repository);

  final NotificationRepository _repository;

  Future<Result<void>> execute({required String workspaceId}) async {
    return _deleteResult(
      await _repository.deleteAllNotifications(workspaceId: workspaceId),
    );
  }
}

final class LoadNotificationPreferenceUseCase {
  const LoadNotificationPreferenceUseCase(this._repository);

  final NotificationRepository _repository;

  Future<Result<NotificationPreference>> execute({
    required String workspaceId,
  }) {
    return _repository.getPreference(workspaceId: workspaceId);
  }
}

final class SaveNotificationPreferenceUseCase {
  const SaveNotificationPreferenceUseCase(this._repository);

  final NotificationRepository _repository;

  Future<Result<NotificationPreference>> execute(
    NotificationPreference preference,
  ) {
    return _repository.savePreference(preference);
  }

  Future<Result<NotificationPreference>> fromAppSettings({
    required String workspaceId,
    required AppSettings settings,
  }) {
    return execute(settings.toNotificationPreference(workspaceId));
  }
}

final class ListPushDevicesUseCase {
  const ListPushDevicesUseCase(this._repository);

  final NotificationRepository _repository;

  Future<Result<List<PushDeviceRegistration>>> execute() {
    return _repository.listPushDevices();
  }
}

final class UnregisterPushDeviceUseCase {
  const UnregisterPushDeviceUseCase(this._repository);

  final NotificationRepository _repository;

  Future<Result<void>> execute({required String deviceId}) {
    return _repository.unregisterPushDevice(deviceId: deviceId);
  }
}

extension AppSettingsNotificationPreference on AppSettings {
  NotificationPreference toNotificationPreference(String workspaceId) {
    return NotificationPreference(
      workspaceId: workspaceId,
      mode: notificationsEnabled
          ? NotificationMode.all
          : NotificationMode.muted,
      preview: !sensitivePreviewEnabled,
      quietHours: quietHoursEnabled,
      quietStart: quietStart,
      quietEnd: quietEnd,
      sound: notificationsEnabled,
      vibrate: notificationsEnabled,
      callRinging: notificationsEnabled,
      badgeEnabled: notificationsEnabled,
    );
  }

  AppSettings mergeNotificationPreference(NotificationPreference preference) {
    return copyWith(
      notificationsEnabled: preference.mode != NotificationMode.muted,
      sensitivePreviewEnabled: !preference.preview,
      quietHoursEnabled: preference.quietHours,
      quietStart: preference.quietStart,
      quietEnd: preference.quietEnd,
    );
  }
}
