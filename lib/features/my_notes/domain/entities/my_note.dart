/// Sổ ghi chú cá nhân My Note: chỉ chủ sở hữu đọc / sửa (máy chủ kiểm).
library;

/// Giới hạn khớp với máy chủ.
abstract final class MyNoteLimits {
  static const titleMaxLength = 200;
  static const bodyMaxLength = 50000;
  static const tagsMax = 20;
  static const tagMaxLength = 40;
  static const folderNameMaxLength = 80;
  static const folderMaxDepth = 5;
  static const queryMaxLength = 200;
  static const pageSize = 50;
}

/// Giá trị `folder_id=root` khi lọc ghi chú không thuộc thư mục nào.
const myNoteRootFolderFilter = 'root';

final class MyNoteSummary {
  const MyNoteSummary({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.excerpt,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
    this.tags = const [],
    this.pinned = false,
    this.sourceChannelId,
    this.sourceMessageId,
    this.attachmentCount = 0,
  });

  final String id;
  final String workspaceId;
  final String? folderId;
  final String title;
  final String excerpt;
  final List<String> tags;
  final bool pinned;
  final int version;
  final String? sourceChannelId;
  final String? sourceMessageId;
  final int attachmentCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isFromMessage =>
      (sourceChannelId?.isNotEmpty ?? false) &&
      (sourceMessageId?.isNotEmpty ?? false);

  /// Tiêu đề hiển thị: tiêu đề, hoặc dòng đầu của nội dung.
  String get displayTitle => myNoteDisplayTitle(title, excerpt);

  MyNoteSummary copyWith({
    String? folderId,
    bool clearFolder = false,
    String? title,
    String? excerpt,
    List<String>? tags,
    bool? pinned,
    int? version,
    int? attachmentCount,
    DateTime? updatedAt,
  }) {
    return MyNoteSummary(
      id: id,
      workspaceId: workspaceId,
      folderId: clearFolder ? null : folderId ?? this.folderId,
      title: title ?? this.title,
      excerpt: excerpt ?? this.excerpt,
      tags: tags ?? this.tags,
      pinned: pinned ?? this.pinned,
      version: version ?? this.version,
      sourceChannelId: sourceChannelId,
      sourceMessageId: sourceMessageId,
      attachmentCount: attachmentCount ?? this.attachmentCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

final class MyNoteAttachment {
  const MyNoteAttachment({
    required this.fileId,
    required this.originalName,
    required this.mimeType,
    required this.byteSize,
    required this.createdAt,
  });

  final String fileId;
  final String originalName;
  final String mimeType;
  final int byteSize;
  final DateTime createdAt;
}

final class MyNote {
  const MyNote({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.body,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.excerpt = '',
    this.folderId,
    this.tags = const [],
    this.pinned = false,
    this.sourceChannelId,
    this.sourceMessageId,
    this.attachments = const [],
    this.attachmentCount = 0,
  });

  final String id;
  final String workspaceId;
  final String? folderId;
  final String title;
  final String body;
  final String excerpt;
  final List<String> tags;
  final bool pinned;
  final int version;
  final String? sourceChannelId;
  final String? sourceMessageId;
  final List<MyNoteAttachment> attachments;
  final int attachmentCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isFromMessage =>
      (sourceChannelId?.isNotEmpty ?? false) &&
      (sourceMessageId?.isNotEmpty ?? false);

  String get displayTitle => myNoteDisplayTitle(title, body);

  MyNoteSummary toSummary() {
    return MyNoteSummary(
      id: id,
      workspaceId: workspaceId,
      folderId: folderId,
      title: title,
      excerpt: excerpt.isNotEmpty ? excerpt : myNoteExcerpt(body),
      tags: tags,
      pinned: pinned,
      version: version,
      sourceChannelId: sourceChannelId,
      sourceMessageId: sourceMessageId,
      attachmentCount: attachments.isNotEmpty
          ? attachments.length
          : attachmentCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  MyNote copyWith({List<MyNoteAttachment>? attachments}) {
    return MyNote(
      id: id,
      workspaceId: workspaceId,
      folderId: folderId,
      title: title,
      body: body,
      excerpt: excerpt,
      tags: tags,
      pinned: pinned,
      version: version,
      sourceChannelId: sourceChannelId,
      sourceMessageId: sourceMessageId,
      attachments: attachments ?? this.attachments,
      attachmentCount: (attachments ?? this.attachments).length,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

final class MyNoteFolder {
  const MyNoteFolder({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.position = 0,
    this.noteCount = 0,
  });

  final String id;
  final String workspaceId;
  final String? parentId;
  final String name;
  final int position;
  final int noteCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class MyNoteTag {
  const MyNoteTag({required this.tag, required this.count});

  final String tag;
  final int count;
}

/// Bộ lọc danh sách. [folderId] null = mọi thư mục; [myNoteRootFolderFilter] = gốc.
final class MyNoteFilter {
  const MyNoteFilter({
    this.folderId,
    this.tag,
    this.query = '',
    this.pinnedOnly = false,
  });

  final String? folderId;
  final String? tag;
  final String query;
  final bool pinnedOnly;

  /// Chỉ bộ lọc mặc định (không lọc gì) được lưu để mở khi mất mạng.
  bool get isDefault =>
      folderId == null && tag == null && query.trim().isEmpty && !pinnedOnly;

  MyNoteFilter copyWith({
    String? folderId,
    bool clearFolder = false,
    String? tag,
    bool clearTag = false,
    String? query,
    bool? pinnedOnly,
  }) {
    return MyNoteFilter(
      folderId: clearFolder ? null : folderId ?? this.folderId,
      tag: clearTag ? null : tag ?? this.tag,
      query: query ?? this.query,
      pinnedOnly: pinnedOnly ?? this.pinnedOnly,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MyNoteFilter &&
        other.folderId == folderId &&
        other.tag == tag &&
        other.query == query &&
        other.pinnedOnly == pinnedOnly;
  }

  @override
  int get hashCode => Object.hash(folderId, tag, query, pinnedOnly);
}

final class MyNotePage {
  const MyNotePage({
    required this.notes,
    this.nextCursor,
    this.hasMore = false,
  });

  final List<MyNoteSummary> notes;
  final String? nextCursor;
  final bool hasMore;
}

/// Kết quả đọc: [fromCache] = bản lưu trên máy khi không gọi được máy chủ.
final class MyNotesCached<T> {
  const MyNotesCached(this.value, {this.fromCache = false, this.cachedAt});

  final T value;
  final bool fromCache;
  final DateTime? cachedAt;
}

/// Kết quả "Lưu vào My Note": [created] false khi tin này đã được lưu trước đó.
final class SavedMessageNote {
  const SavedMessageNote({required this.note, required this.created});

  final MyNote note;
  final bool created;
}

/// Thay đổi gửi kèm PATCH; trường null = giữ nguyên.
final class MyNotePatch {
  const MyNotePatch({
    this.title,
    this.body,
    this.tags,
    this.pinned,
    this.folderId,
    this.moveToRoot = false,
  });

  final String? title;
  final String? body;
  final List<String>? tags;
  final bool? pinned;

  /// Chuyển sang thư mục này (bỏ qua khi [moveToRoot]).
  final String? folderId;

  /// Gửi `folder_id: null` để đưa ghi chú về gốc.
  final bool moveToRoot;

  bool get changesFolder => moveToRoot || folderId != null;

  bool get isEmpty =>
      title == null &&
      body == null &&
      tags == null &&
      pinned == null &&
      !changesFolder;
}

/// Một nút của cây thư mục (dựng từ danh sách phẳng máy chủ trả).
final class MyNoteFolderNode {
  const MyNoteFolderNode({
    required this.folder,
    required this.depth,
    this.children = const [],
  });

  final MyNoteFolder folder;

  /// Tầng 1 = thư mục ở gốc.
  final int depth;
  final List<MyNoteFolderNode> children;
}

/// Dựng cây thư mục, sắp theo `position` rồi tên. Thư mục có cha không tồn tại
/// (hoặc nằm trong vòng lặp) được đưa về gốc để không bị mất.
List<MyNoteFolderNode> buildMyNoteFolderTree(List<MyNoteFolder> folders) {
  final ids = {for (final folder in folders) folder.id};
  final byParent = <String?, List<MyNoteFolder>>{};
  for (final folder in folders) {
    final parent = folder.parentId != null && ids.contains(folder.parentId)
        ? folder.parentId
        : null;
    byParent.putIfAbsent(parent, () => []).add(folder);
  }
  int compare(MyNoteFolder a, MyNoteFolder b) {
    final byPosition = a.position.compareTo(b.position);
    if (byPosition != 0) return byPosition;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  final visited = <String>{};
  List<MyNoteFolderNode> build(String? parentId, int depth) {
    final children = [...?byParent[parentId]]..sort(compare);
    final nodes = <MyNoteFolderNode>[];
    for (final folder in children) {
      if (!visited.add(folder.id)) continue;
      nodes.add(
        MyNoteFolderNode(
          folder: folder,
          depth: depth,
          children: build(folder.id, depth + 1),
        ),
      );
    }
    return nodes;
  }

  final roots = build(null, 1);
  // Thư mục nằm trong vòng lặp không tới được từ gốc: đưa lên gốc.
  for (final folder in [...folders]..sort(compare)) {
    if (visited.add(folder.id)) {
      roots.add(
        MyNoteFolderNode(
          folder: folder,
          depth: 1,
          children: build(folder.id, 2),
        ),
      );
    }
  }
  return roots;
}

/// Duỗi cây thành danh sách theo thứ tự hiển thị (để vẽ có thụt lề).
List<MyNoteFolderNode> flattenMyNoteFolderTree(List<MyNoteFolderNode> nodes) {
  final result = <MyNoteFolderNode>[];
  void visit(List<MyNoteFolderNode> items) {
    for (final node in items) {
      result.add(node);
      visit(node.children);
    }
  }

  visit(nodes);
  return result;
}

/// Độ sâu (tầng) của một thư mục; 0 khi không tìm thấy.
int myNoteFolderDepth(List<MyNoteFolder> folders, String folderId) {
  final byId = {for (final folder in folders) folder.id: folder};
  var depth = 0;
  String? current = folderId;
  final seen = <String>{};
  while (current != null && byId.containsKey(current) && seen.add(current)) {
    depth++;
    current = byId[current]!.parentId;
  }
  return depth;
}

/// Chuẩn hoá tag như máy chủ: bỏ `#` đầu, gộp khoảng trắng, chữ thường, bỏ trùng.
List<String> normalizeMyNoteTags(Iterable<String> raw) {
  final result = <String>[];
  for (final value in raw) {
    var tag = value.trim();
    while (tag.startsWith('#')) {
      tag = tag.substring(1).trimLeft();
    }
    tag = tag.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (tag.isEmpty || result.contains(tag)) continue;
    result.add(tag);
  }
  return result;
}

/// Tách chuỗi người dùng gõ ("việc, #nhà riêng") thành danh sách tag.
List<String> parseMyNoteTagInput(String input) {
  return normalizeMyNoteTags(input.split(RegExp(r'[,;\n]')));
}

String myNoteExcerpt(String body, {int maxLength = 240}) {
  final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.runes.length <= maxLength) return compact;
  return String.fromCharCodes(compact.runes.take(maxLength));
}

String myNoteDisplayTitle(String title, String body) {
  final cleanTitle = title.trim();
  if (cleanTitle.isNotEmpty) return cleanTitle;
  for (final line in body.split('\n')) {
    final text = line.replaceFirst(RegExp(r'^[#>\-*\s]+'), '').trim();
    if (text.isNotEmpty) {
      return text.runes.length > 80
          ? String.fromCharCodes(text.runes.take(80))
          : text;
    }
  }
  return 'Ghi chú không tiêu đề';
}

/// Ghim lên đầu, rồi mới sửa gần nhất (khớp thứ tự máy chủ).
List<MyNoteSummary> sortMyNoteSummaries(Iterable<MyNoteSummary> notes) {
  final sorted = [...notes];
  sorted.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final byUpdated = b.updatedAt.compareTo(a.updatedAt);
    if (byUpdated != 0) return byUpdated;
    return b.id.compareTo(a.id);
  });
  return sorted;
}
