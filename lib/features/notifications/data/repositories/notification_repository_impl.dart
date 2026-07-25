import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/mobile_notification.dart';
import '../../domain/repositories/notification_repository.dart';
import '../datasources/notification_remote_data_source.dart';

final class NotificationRepositoryImpl implements NotificationRepository {
  const NotificationRepositoryImpl(this._remote);

  final NotificationRemoteDataSource _remote;

  @override
  Future<Result<List<MobileNotification>>> listNotifications({
    required String workspaceId,
    int limit = 50,
  }) {
    return guardResult(
      () => _remote.listNotifications(workspaceId: workspaceId, limit: limit),
    );
  }

  @override
  Future<Result<void>> markRead({required String notificationId}) {
    return guardResult(() => _remote.markRead(notificationId: notificationId));
  }

  @override
  Future<Result<void>> markAllRead({required String workspaceId}) {
    return guardResult(() => _remote.markAllRead(workspaceId: workspaceId));
  }

  @override
  Future<Result<NotificationPreference>> getPreference({
    required String workspaceId,
  }) {
    return guardResult(() => _remote.getPreference(workspaceId: workspaceId));
  }

  @override
  Future<Result<NotificationPreference>> savePreference(
    NotificationPreference preference,
  ) {
    return guardResult(() => _remote.savePreference(preference));
  }

  @override
  Future<Result<List<PushDeviceRegistration>>> listPushDevices() {
    return guardResult(_remote.listPushDevices);
  }

  @override
  Future<Result<void>> unregisterPushDevice({required String deviceId}) {
    return guardResult(() => _remote.unregisterPushDevice(deviceId: deviceId));
  }
}
