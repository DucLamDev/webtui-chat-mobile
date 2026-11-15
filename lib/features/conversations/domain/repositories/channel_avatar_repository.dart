import '../../../../core/result/result.dart';
import '../../../profile/domain/entities/avatar_upload.dart';
import '../entities/conversation_summary.dart';

/// Tải ảnh đại diện của kênh / nhóm lên máy chủ.
abstract interface class ChannelAvatarRepository {
  Future<Result<ConversationSummary>> upload({
    required String workspaceId,
    required String channelId,
    required PickedAvatar avatar,
  });
}
