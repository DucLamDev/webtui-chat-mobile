import '../../../../core/result/result.dart';
import '../entities/mobile_notification.dart';

abstract interface class ChannelNotificationPreferenceRepository {
  Future<Result<ChannelNotificationPreference>> getChannelPreference({
    required String workspaceId,
    required String channelId,
  });

  Future<Result<ChannelNotificationPreference>> saveChannelPreference(
    ChannelNotificationPreference preference,
  );
}
