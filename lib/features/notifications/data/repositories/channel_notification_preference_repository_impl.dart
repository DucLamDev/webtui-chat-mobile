import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/mobile_notification.dart';
import '../../domain/repositories/channel_notification_preference_repository.dart';
import '../datasources/notification_remote_data_source.dart';

final class ChannelNotificationPreferenceRepositoryImpl
    implements ChannelNotificationPreferenceRepository {
  const ChannelNotificationPreferenceRepositoryImpl(this._remote);

  final NotificationRemoteDataSource _remote;

  @override
  Future<Result<ChannelNotificationPreference>> getChannelPreference({
    required String workspaceId,
    required String channelId,
  }) {
    return guardResult(
      () => _remote.getChannelPreference(
        workspaceId: workspaceId,
        channelId: channelId,
      ),
    );
  }

  @override
  Future<Result<ChannelNotificationPreference>> saveChannelPreference(
    ChannelNotificationPreference preference,
  ) {
    return guardResult(() => _remote.saveChannelPreference(preference));
  }
}
