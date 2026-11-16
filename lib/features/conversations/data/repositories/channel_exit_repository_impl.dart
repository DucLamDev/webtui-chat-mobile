import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/channel_exit.dart';
import '../../domain/repositories/channel_exit_repository.dart';
import '../datasources/conversation_cache_data_source.dart';
import '../datasources/conversation_remote_data_source.dart';

final class ChannelExitRepositoryImpl implements ChannelExitRepository {
  const ChannelExitRepositoryImpl({
    required ConversationRemoteDataSource remote,
    required ConversationCacheDataSource cache,
  }) : _remote = remote,
       _cache = cache;

  final ConversationRemoteDataSource _remote;
  final ConversationCacheDataSource _cache;

  @override
  Future<Result<ChannelLeaveResult>> leave({
    required String workspaceId,
    required String channelId,
  }) async {
    final result = await guardResult(
      () =>
          _remote.leaveChannel(workspaceId: workspaceId, channelId: channelId),
    );
    if (result is Success<ChannelLeaveResult>) {
      await forgetLocally(workspaceId: workspaceId, channelId: channelId);
    }
    return result;
  }

  @override
  Future<Result<void>> delete({
    required String workspaceId,
    required String channelId,
  }) async {
    final result = await guardResult(
      () =>
          _remote.deleteChannel(workspaceId: workspaceId, channelId: channelId),
    );
    if (result is Success<void>) {
      await forgetLocally(workspaceId: workspaceId, channelId: channelId);
    }
    return result;
  }

  @override
  Future<void> forgetLocally({
    required String workspaceId,
    required String channelId,
  }) async {
    try {
      await _cache.removeChannel(
        workspaceId: workspaceId,
        channelId: channelId,
      );
    } on Object {
      // Bộ nhớ đệm chỉ để mở nhanh / khi mất mạng; lần tải sau ghi đè lại.
    }
  }
}
