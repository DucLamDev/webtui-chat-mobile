import '../../../../core/result/result.dart';
import '../entities/collaboration_document_version.dart';
import '../entities/collaboration_room.dart';

/// Lịch sử phiên bản ghi chú / bảng trắng của phòng (`kind` = `notes` hoặc
/// `whiteboard`). Quyền như đọc / sửa tài liệu, máy chủ tự kiểm.
abstract interface class CollaborationDocumentHistoryRepository {
  Future<Result<CollaborationDocument>> getDocument({
    required String workspaceId,
    required String channelId,
    required String kind,
  });

  /// Mới nhất trước, không kèm nội dung.
  Future<Result<List<CollaborationDocumentVersion>>> listVersions({
    required String workspaceId,
    required String channelId,
    required String kind,
    int limit = 50,
  });

  Future<Result<CollaborationDocumentVersionDetail>> getVersion({
    required String workspaceId,
    required String channelId,
    required String kind,
    required int version,
  });

  /// Ghi nội dung bản [version] thành tài liệu hiện tại. Tài liệu đã đổi so với
  /// [expectedVersion] thì máy chủ trả `DOCUMENT_VERSION_CONFLICT` (409).
  Future<Result<CollaborationDocument>> restoreVersion({
    required String workspaceId,
    required String channelId,
    required String kind,
    required int version,
    required int expectedVersion,
  });
}
