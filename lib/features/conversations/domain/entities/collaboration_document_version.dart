/// Một bản trong lịch sử ghi chú / bảng trắng (danh sách, không kèm nội dung).
final class CollaborationDocumentVersion {
  const CollaborationDocumentVersion({
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.authorId,
    this.authorName,
    this.sizeBytes = 0,
  });

  final int version;
  final String? authorId;
  final String? authorName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sizeBytes;
}

/// Một bản kèm nội dung để xem trước.
final class CollaborationDocumentVersionDetail {
  const CollaborationDocumentVersionDetail({
    required this.version,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.authorId,
    this.authorName,
  });

  final int version;
  final Map<String, Object?> content;
  final String? authorId;
  final String? authorName;
  final DateTime createdAt;
  final DateTime updatedAt;
}
