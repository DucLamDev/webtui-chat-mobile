import 'ide_more_time.dart';

String _s(Object? v) => v is String ? v : '';
int _i(Object? v) => v is num ? v.toInt() : 0;

List<String> _strs(Object? l) => [
  if (l is List)
    for (final x in l)
      if (x is String && x.isNotEmpty) x,
];

/// Mốc thời gian có thể là giây Unix hoặc chuỗi ISO.
DateTime? _time(Object? v) {
  if (v is num) return ideTimeFromSeconds(v);
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}

// ------------------------------------------------------------- nhật ký AI

final class IdeAiLogSession {
  const IdeAiLogSession({
    this.by = '',
    this.kind = '',
    this.tab = '',
    this.branch = '',
    this.task = '',
    this.hidden = false,
    this.files = const [],
    this.fileCount = 0,
    this.start,
    this.end,
    this.closed = false,
  });

  final String by;
  final String kind;
  final String tab;
  final String branch;
  final String task;
  final bool hidden;
  final List<String> files;
  final int fileCount;
  final DateTime? start;
  final DateTime? end;
  final bool closed;
}

final class IdeAiLogPr {
  const IdeAiLogPr({
    this.number = 0,
    this.title = '',
    this.user = '',
    this.head = '',
    this.state = '',
    this.mergedAt,
    this.url = '',
    this.person = '',
    this.fileCount = 0,
  });

  final int number;
  final String title;
  final String user;
  final String head;
  final String state;
  final DateTime? mergedAt;
  final String url;
  final String person;
  final int fileCount;
}

final class IdeAiLog {
  const IdeAiLog({this.at, this.sessions = const [], this.prs = const []});

  final DateTime? at;
  final List<IdeAiLogSession> sessions;
  final List<IdeAiLogPr> prs;

  bool get isEmpty => sessions.isEmpty && prs.isEmpty;

  static IdeAiLog parse(Object? data) {
    if (data is! Map) return const IdeAiLog();
    final sessions = data['phien'];
    final prs = data['pr'];
    return IdeAiLog(
      at: _time(data['at']),
      sessions: [
        if (sessions is List)
          for (final e in sessions)
            if (e is Map)
              IdeAiLogSession(
                by: _s(e['by']),
                kind: _s(e['loai']),
                tab: _s(e['tab']),
                branch: _s(e['nhanh']),
                task: _s(e['viec']),
                hidden: e['an'] == true,
                files: _strs(e['tep']),
                fileCount: _i(e['so_tep']),
                start: _time(e['dau']),
                end: _time(e['cuoi']),
                closed: e['dong'] == true,
              ),
      ],
      prs: [
        if (prs is List)
          for (final e in prs)
            if (e is Map)
              IdeAiLogPr(
                number: _i(e['number']),
                title: _s(e['title']),
                user: _s(e['user']),
                head: _s(e['head']),
                state: _s(e['state']),
                mergedAt: _time(e['merged_at']),
                url: _s(e['url']),
                person: _s(e['nguoi']),
                fileCount: _i(e['so_tep']),
              ),
      ],
    );
  }
}

// ------------------------------------------------------- nhật ký thao tác

/// Loại sự kiện `oplog.list` nhận được ở `kinds`.
const ideOplogKinds = ['ai', 'deploy', 'git', 'agent', 'quick', 'ssh', 'admin'];

final class IdeOpEvent {
  const IdeOpEvent({
    required this.ts,
    required this.kind,
    this.action = '',
    this.user = '',
    this.detail = '',
    this.level = 'info',
    this.target = '',
    this.name = '',
    this.sha = '',
    this.ms,
  });

  /// Giây Unix (số thực).
  final double ts;
  final String kind;
  final String action;
  final String user;
  final String detail;

  /// `info` / `ok` / `bad`.
  final String level;
  final String target;
  final String name;
  final String sha;
  final int? ms;

  DateTime? get time => ideTimeFromSeconds(ts);

  String get key => '$ts|$kind|$action|$user|$detail';
}

final class IdeOplogPage {
  const IdeOplogPage({
    this.events = const [],
    this.next,
    this.truncated = false,
    this.matched = 0,
    this.total = 0,
    this.bad = 0,
    this.kinds = const {},
  });

  final List<IdeOpEvent> events;

  /// Mốc `before` của trang sau (giây thực); `null` = hết.
  final double? next;
  final bool truncated;
  final int matched;
  final int total;
  final int bad;
  final Map<String, int> kinds;

  static IdeOplogPage parse(Object? data) {
    if (data is! Map) return const IdeOplogPage();
    final summary = data['summary'] is Map ? data['summary'] as Map : const {};
    final rawKinds = summary['kinds'];
    final events = data['events'];
    final next = data['next'];
    return IdeOplogPage(
      events: [
        if (events is List)
          for (final e in events)
            if (e is Map && e['ts'] is num)
              IdeOpEvent(
                ts: (e['ts'] as num).toDouble(),
                kind: _s(e['kind']),
                action: _s(e['action']),
                user: _s(e['user']),
                detail: _s(e['detail']),
                level: _s(e['level']).isEmpty ? 'info' : _s(e['level']),
                target: _s(e['target']),
                name: _s(e['name']),
                sha: _s(e['sha']),
                ms: e['ms'] is num ? (e['ms'] as num).toInt() : null,
              ),
      ],
      next: next is num ? next.toDouble() : null,
      truncated: data['truncated'] == true,
      matched: _i(data['matched']),
      total: _i(summary['total']),
      bad: _i(summary['bad']),
      kinds: {
        if (rawKinds is Map)
          for (final e in rawKinds.entries)
            if (e.value is num) e.key.toString(): (e.value as num).toInt(),
      },
    );
  }
}

/// Danh sách đang hiện + mốc trang sau; trang mới nối vào, bỏ trùng.
final class IdeOplogFeed {
  const IdeOplogFeed({
    this.events = const [],
    this.next,
    this.matched = 0,
    this.total = 0,
    this.bad = 0,
  });

  final List<IdeOpEvent> events;
  final double? next;
  final int matched;
  final int total;
  final int bad;

  bool get hasMore => next != null;

  factory IdeOplogFeed.first(IdeOplogPage page) => IdeOplogFeed(
    events: page.events,
    next: page.next,
    matched: page.matched,
    total: page.total,
    bad: page.bad,
  );

  /// Nối [page] (trang sau). Mốc không lùi thì coi như hết, tránh lặp vô hạn.
  IdeOplogFeed append(IdeOplogPage page) {
    final seen = {for (final e in events) e.key};
    final nextCursor = page.next;
    final stuck = nextCursor != null && next != null && nextCursor >= next!;
    return IdeOplogFeed(
      events: [
        ...events,
        for (final e in page.events)
          if (seen.add(e.key)) e,
      ],
      next: stuck || page.events.isEmpty ? null : nextCursor,
      matched: page.matched,
      total: total,
      bad: bad,
    );
  }
}
