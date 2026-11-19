import '../../../../core/result/result.dart';
import '../entities/message_sync.dart';

/// Luồng thay đổi tin của máy chủ:
/// `GET /api/v1/workspaces/{ws}/channels/{ch}/messages/changes?since=&limit=`.
///
/// - [since] rỗng / null: không trả tin, chỉ trả mốc "từ bây giờ" để bắt đầu
///   (lấy mốc này TRƯỚC khi tải trang tin mới nhất để không lỡ thay đổi).
/// - Máy chủ cũ chưa có API: `FailureResult` với `FailureKind.notFound`; bên
///   gọi quay về cách cũ (tải trang tin mới nhất).
abstract interface class MessageChangesRepository {
  Future<Result<MessageChangesPage>> listMessageChanges({
    required String workspaceId,
    required String channelId,
    String? since,
    int limit = 200,
  });
}
