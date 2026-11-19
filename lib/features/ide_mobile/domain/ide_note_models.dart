import 'ide_more_time.dart';

final _noteId = RegExp(r'^[0-9a-f]{12}$');

/// `id` ghi chú hợp lệ (12 hex).
bool isIdeNoteId(String? id) => id != null && _noteId.hasMatch(id);

String _s(Object? v) => v is String ? v : '';

final class IdeNoteItem {
  const IdeNoteItem({
    required this.id,
    required this.title,
    this.kind = 'van-ban',
    this.updatedAt,
    this.updatedBy = '',
    this.size = 0,
  });

  final String id;
  final String title;
  final String kind;
  final DateTime? updatedAt;
  final String updatedBy;
  final int size;

  bool get isDiagram => kind == 'so-do';
}

final class IdeDeletedNote {
  const IdeDeletedNote({
    required this.id,
    required this.title,
    required this.n,
    this.by = '',
    this.at,
  });

  final String id;
  final String title;
  final int n;
  final String by;
  final DateTime? at;
}

final class IdeNoteList {
  const IdeNoteList({
    this.notes = const [],
    this.deleted = const [],
    this.max = 50,
    this.bodyMax = 512 * 1024,
    this.titleMax = 120,
  });

  final List<IdeNoteItem> notes;
  final List<IdeDeletedNote> deleted;
  final int max;
  final int bodyMax;
  final int titleMax;

  bool get isEmpty => notes.isEmpty && deleted.isEmpty;
  bool get full => notes.length >= max;

  static IdeNoteList parse(Object? data) {
    if (data is! Map) return const IdeNoteList();
    final notes = data['notes'];
    final deleted = data['deleted'];
    int n(Object? v, int d) => v is num && v > 0 ? v.toInt() : d;
    return IdeNoteList(
      notes: [
        if (notes is List)
          for (final e in notes)
            if (e is Map && isIdeNoteId(_s(e['id'])))
              IdeNoteItem(
                id: e['id'] as String,
                title: _s(e['title']),
                kind: _s(e['kind']).isEmpty ? 'van-ban' : _s(e['kind']),
                updatedAt: ideTimeFromSeconds(e['updatedAt']),
                updatedBy: _s(e['updatedByName']).isNotEmpty
                    ? _s(e['updatedByName'])
                    : _s(e['updatedBy']),
                size: e['size'] is num ? (e['size'] as num).toInt() : 0,
              ),
      ],
      deleted: [
        if (deleted is List)
          for (final e in deleted)
            if (e is Map && isIdeNoteId(_s(e['id'])) && e['n'] is num)
              IdeDeletedNote(
                id: e['id'] as String,
                title: _s(e['title']),
                n: (e['n'] as num).toInt(),
                by: _s(e['by']),
                at: ideTimeFromSeconds(e['at']),
              ),
      ],
      max: n(data['max'], 50),
      bodyMax: n(data['bodyMax'], 512 * 1024),
      titleMax: n(data['titleMax'], 120),
    );
  }
}

final class IdeNote {
  const IdeNote({
    required this.id,
    required this.title,
    required this.body,
    required this.sha,
    this.kind = 'van-ban',
    this.diagram,
    this.updatedAt,
    this.updatedBy = '',
    this.createdBy = '',
  });

  final String id;
  final String title;
  final String body;
  final String sha;
  final String kind;
  final Object? diagram;
  final DateTime? updatedAt;
  final String updatedBy;
  final String createdBy;

  bool get isDiagram => kind == 'so-do';

  static IdeNote? tryParse(Object? data) {
    if (data is! Map) return null;
    final id = _s(data['id']);
    if (!isIdeNoteId(id)) return null;
    String name(String a, String b) =>
        _s(data[a]).isNotEmpty ? _s(data[a]) : _s(data[b]);
    return IdeNote(
      id: id,
      title: _s(data['title']),
      body: _s(data['body']),
      sha: _s(data['sha']),
      kind: _s(data['kind']).isEmpty ? 'van-ban' : _s(data['kind']),
      diagram: data['diagram'],
      updatedAt: ideTimeFromSeconds(data['updatedAt']),
      updatedBy: name('updatedByName', 'updatedBy'),
      createdBy: name('createdByName', 'createdBy'),
    );
  }
}

final class IdeNoteVersion {
  const IdeNoteVersion({
    required this.n,
    required this.title,
    required this.body,
    this.by = '',
    this.at,
    this.deleted = false,
    this.kind = 'van-ban',
  });

  final int n;
  final String title;
  final String body;
  final String by;
  final DateTime? at;
  final bool deleted;
  final String kind;

  static List<IdeNoteVersion> parseList(Object? data) {
    final items = data is Map ? data['items'] : null;
    return [
      if (items is List)
        for (final e in items)
          if (e is Map && e['n'] is num)
            IdeNoteVersion(
              n: (e['n'] as num).toInt(),
              title: _s(e['title']),
              body: _s(e['body']),
              by: _s(e['byName']).isNotEmpty ? _s(e['byName']) : _s(e['by']),
              at: ideTimeFromSeconds(e['at']),
              deleted: e['deleted'] == true,
              kind: _s(e['kind']).isEmpty ? 'van-ban' : _s(e['kind']),
            ),
    ];
  }
}
