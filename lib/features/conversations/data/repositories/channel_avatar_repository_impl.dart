import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../../profile/domain/entities/avatar_upload.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/channel_avatar_repository.dart';
import '../datasources/conversation_remote_data_source.dart';

final class ChannelAvatarRepositoryImpl implements ChannelAvatarRepository {
  const ChannelAvatarRepositoryImpl(this._remote);

  final ConversationRemoteDataSource _remote;

  @override
  Future<Result<ConversationSummary>> upload({
    required String workspaceId,
    required String channelId,
    required PickedAvatar avatar,
  }) {
    return guardResult(
      () => _remote.uploadChannelAvatar(
        workspaceId: workspaceId,
        channelId: channelId,
        filePath: avatar.path,
        fileName: avatar.fileName,
        mimeType: avatar.mimeType,
      ),
    );
  }
}
