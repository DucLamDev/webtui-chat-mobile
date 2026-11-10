import '../../../../core/network/api_response.dart';
import '../../domain/entities/my_note.dart';

/// Đọc / ghi JSON My Note. Bản lưu trên máy dùng đúng tên trường của máy chủ
/// (snake_case) để một bộ đọc dùng chung cho cả hai nguồn.

MyNoteSummary myNoteSummaryFromJson(
  JsonMap map, {
  String fallbackWorkspaceId = '',
}) {
  final body = stringField(map, const ['body']);
  final excerpt = stringField(map, const ['excerpt']);
  return MyNoteSummary(
    id: stringField(map, const ['id', 'note_id', 'noteId']),
    workspaceId: stringField(map, const [
      'workspace_id',
      'workspaceId',
    ], fallback: fallbackWorkspaceId),
    folderId: nullableStringField(map, const ['folder_id', 'folderId']),
    title: stringField(map, const ['title']),
    excerpt: excerpt.isNotEmpty ? excerpt : myNoteExcerpt(body),
    tags: _tags(map),
    pinned: boolField(map, const ['pinned', 'is_pinned', 'isPinned']),
    version: intField(map, const ['version'], fallback: 1),
    sourceChannelId: nullableStringField(map, const [
      'source_channel_id',
      'sourceChannelId',
    ]),
    sourceMessageId: nullableStringField(map, const [
      'source_message_id',
      'sourceMessageId',
    ]),
    attachmentCount: intField(map, const [
      'attachment_count',
      'attachmentCount',
    ], fallback: jsonMapList(map['attachments']).length),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
    updatedAt: dateTimeField(map, const ['updated_at', 'updatedAt']),
  );
}

MyNote myNoteFromJson(JsonMap map, {String fallbackWorkspaceId = ''}) {
  final summary = myNoteSummaryFromJson(
    map,
    fallbackWorkspaceId: fallbackWorkspaceId,
  );
  final attachments = jsonMapList(
    map['attachments'],
  ).map(myNoteAttachmentFromJson).toList(growable: false);
  return MyNote(
    id: summary.id,
    workspaceId: summary.workspaceId,
    folderId: summary.folderId,
    title: summary.title,
    body: stringField(map, const ['body']),
    excerpt: summary.excerpt,
    tags: summary.tags,
    pinned: summary.pinned,
    version: summary.version,
    sourceChannelId: summary.sourceChannelId,
    sourceMessageId: summary.sourceMessageId,
    attachments: attachments,
    attachmentCount: attachments.isNotEmpty
        ? attachments.length
        : summary.attachmentCount,
    createdAt: summary.createdAt,
    updatedAt: summary.updatedAt,
  );
}

MyNoteAttachment myNoteAttachmentFromJson(JsonMap map) {
  return MyNoteAttachment(
    fileId: stringField(map, const ['file_id', 'fileId', 'id']),
    originalName: stringField(map, const [
      'original_name',
      'originalName',
      'name',
    ], fallback: 'Tệp đính kèm'),
    mimeType: stringField(map, const ['mime_type', 'mimeType']),
    byteSize: intField(map, const ['byte_size', 'byteSize', 'size']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

MyNoteFolder myNoteFolderFromJson(
  JsonMap map, {
  String fallbackWorkspaceId = '',
}) {
  return MyNoteFolder(
    id: stringField(map, const ['id', 'folder_id', 'folderId']),
    workspaceId: stringField(map, const [
      'workspace_id',
      'workspaceId',
    ], fallback: fallbackWorkspaceId),
    parentId: nullableStringField(map, const ['parent_id', 'parentId']),
    name: stringField(map, const ['name']),
    position: intField(map, const ['position']),
    noteCount: intField(map, const ['note_count', 'noteCount']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
    updatedAt: dateTimeField(map, const ['updated_at', 'updatedAt']),
  );
}

MyNoteTag myNoteTagFromJson(JsonMap map) {
  return MyNoteTag(
    tag: stringField(map, const ['tag', 'name']),
    count: intField(map, const ['count', 'note_count', 'noteCount']),
  );
}

JsonMap myNoteSummaryToJson(MyNoteSummary note) {
  return {
    'id': note.id,
    'workspace_id': note.workspaceId,
    'folder_id': note.folderId,
    'title': note.title,
    'excerpt': note.excerpt,
    'tags': note.tags,
    'pinned': note.pinned,
    'version': note.version,
    'source_channel_id': note.sourceChannelId,
    'source_message_id': note.sourceMessageId,
    'attachment_count': note.attachmentCount,
    'created_at': note.createdAt.toUtc().toIso8601String(),
    'updated_at': note.updatedAt.toUtc().toIso8601String(),
  };
}

JsonMap myNoteToJson(MyNote note) {
  return {
    ...myNoteSummaryToJson(note.toSummary()),
    'body': note.body,
    'attachments': [
      for (final attachment in note.attachments)
        {
          'file_id': attachment.fileId,
          'original_name': attachment.originalName,
          'mime_type': attachment.mimeType,
          'byte_size': attachment.byteSize,
          'created_at': attachment.createdAt.toUtc().toIso8601String(),
        },
    ],
  };
}

JsonMap myNoteFolderToJson(MyNoteFolder folder) {
  return {
    'id': folder.id,
    'workspace_id': folder.workspaceId,
    'parent_id': folder.parentId,
    'name': folder.name,
    'position': folder.position,
    'note_count': folder.noteCount,
    'created_at': folder.createdAt.toUtc().toIso8601String(),
    'updated_at': folder.updatedAt.toUtc().toIso8601String(),
  };
}

JsonMap myNoteTagToJson(MyNoteTag tag) => {'tag': tag.tag, 'count': tag.count};

List<String> _tags(JsonMap map) {
  final value = map['tags'];
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
