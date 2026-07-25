import '../../../../core/result/result.dart';
import '../entities/mobile_notification.dart';

abstract interface class NotificationRepository {
  Future<Result<List<MobileNotification>>> listNotifications({
    required String workspaceId,
    int limit = 50,
  });

  Future<Result<void>> markRead({required String notificationId});

  Future<Result<void>> markAllRead({required String workspaceId});

  Future<Result<NotificationPreference>> getPreference({
    required String workspaceId,
  });

  Future<Result<NotificationPreference>> savePreference(
    NotificationPreference preference,
  );

  Future<Result<List<PushDeviceRegistration>>> listPushDevices();

  Future<Result<void>> unregisterPushDevice({required String deviceId});
}
