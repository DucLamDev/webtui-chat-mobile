import '../../../../core/result/result.dart';
import '../entities/channel_exit.dart';

/// Rời nhóm / xoá nhóm và bỏ nhóm khỏi bộ nhớ đệm trên máy.
abstract interface class ChannelExitRepository {
  /// `POST .../channels/{id}/leave`. Thành công thì đã bỏ nhóm khỏi bộ nhớ đệm.
  Future<Result<ChannelLeaveResult>> leave({
    required String workspaceId,
    required String channelId,
  });

  /// `DELETE .../channels/{id}` (lưu trữ cho mọi thành viên). Thành công thì đã
  /// bỏ nhóm khỏi bộ nhớ đệm.
  Future<Result<void>> delete({
    required String workspaceId,
    required String channelId,
  });

  /// Bỏ nhóm khỏi bộ nhớ đệm (nhận sự kiện nhóm bị xoá / mình đã rời ở máy
  /// khác). Lỗi ghi bộ nhớ đệm bị bỏ qua.
  Future<void> forgetLocally({
    required String workspaceId,
    required String channelId,
  });
}
