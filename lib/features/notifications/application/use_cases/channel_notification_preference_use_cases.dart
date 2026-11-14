import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/mobile_notification.dart';
import '../../domain/repositories/channel_notification_preference_repository.dart';

final class LoadChannelNotificationPreferenceUseCase {
  const LoadChannelNotificationPreferenceUseCase(this._repository);

  final ChannelNotificationPreferenceRepository _repository;

  Future<Result<ChannelNotificationPreference>> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.getChannelPreference(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

/// Tắt / bật báo của cả kênh: đọc cài đặt hiện có rồi chỉ đổi chế độ, để không
/// làm mất các trường khác máy chủ đã lưu.
final class SetChannelNotificationMutedUseCase {
  const SetChannelNotificationMutedUseCase(this._repository);

  final ChannelNotificationPreferenceRepository _repository;

  Future<Result<ChannelNotificationPreference>> execute({
    required String workspaceId,
    required String channelId,
    required bool muted,
  }) async {
    if (workspaceId.trim().isEmpty || channelId.trim().isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Không xác định được kênh cần đổi cài đặt thông báo.',
          code: 'CHANNEL_REQUIRED',
        ),
      );
    }
    final current = await _repository.getChannelPreference(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    return switch (current) {
      Success<ChannelNotificationPreference>(value: final preference) =>
        _repository.saveChannelPreference(preference.withMuted(muted)),
      FailureResult<ChannelNotificationPreference>() => current,
    };
  }
}
