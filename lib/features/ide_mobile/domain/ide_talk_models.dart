import 'ide_more_time.dart';

/// Mô hình dữ liệu chat thường (`talk.*`, Phụ lục C2). Đọc lỏng: trường sai
/// dạng bị bỏ, số NaN / vô cực / âm thành `null` (hiện "—").

String _s(Object? v) => v is String ? v : '';

/// Trần độ dài một tin chat nhận từ IDE (ký tự): IDE gửi quá thì cắt, tránh
/// treo khung chat khi vẽ chữ khổng lồ.
const ideTalkMaxMessageChars = 200000;

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';
bool _b(Object? v) => v == true;

/// Số hữu hạn không âm; còn lại `null`.
double? ideTalkNum(Object? v) =>
    v is num && v.isFinite && v >= 0 ? v.toDouble() : null;

List<Map<Object?, Object?>> _maps(Object? v, {int max = 500}) => [
  if (v is List)
    for (final e in v.take(max))
      if (e is Map) e,
];

List<String> _strings(Object? v, {int max = 50}) => [
  if (v is List)
    for (final e in v.take(max))
      if (e is String && e.isNotEmpty) e,
];

final _idRe = RegExp(r'^[0-9a-f]{32}$');

/// Mã cuộc / tin: 32 hex.
bool ideTalkIdOk(String id) => _idRe.hasMatch(id);

/// Một mô hình chọn được.
final class IdeTalkModelOption {
  const IdeTalkModelOption({
    required this.id,
    required this.name,
    this.efforts = const [],
    this.fast = false,
    this.tag = '',
  });

  final String id;
  final String name;
  final List<String> efforts;
  final bool fast;
  final String tag;

  static IdeTalkModelOption? tryParse(Map<Object?, Object?> m) {
    final id = _s(m['id']);
    if (id.isEmpty) return null;
    return IdeTalkModelOption(
      id: id,
      name: _s(m['name']).isEmpty ? id : _s(m['name']),
      efforts: _strings(m['efforts'], max: 12),
      fast: _b(m['fast']),
      tag: _s(m['tag']),
    );
  }
}

final class IdeTalkModelGroup {
  const IdeTalkModelGroup({
    required this.kind,
    required this.title,
    required this.models,
    this.account = '',
    this.isDefault = false,
  });

  final String kind;
  final String account;
  final String title;
  final bool isDefault;
  final List<IdeTalkModelOption> models;
}

final class IdeTalkModels {
  const IdeTalkModels({
    this.defaultId = '',
    this.groups = const [],
    this.note = '',
    this.stale = false,
  });

  final String defaultId;
  final List<IdeTalkModelGroup> groups;
  final String note;
  final bool stale;

  Iterable<IdeTalkModelOption> get all => groups.expand((g) => g.models);

  IdeTalkModelOption? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Mô hình mặc định (theo `default`, không có thì cái đầu tiên).
  IdeTalkModelOption? get defaultModel =>
      byId(defaultId) ?? (all.isEmpty ? null : all.first);

  static IdeTalkModels parse(Object? data) {
    if (data is! Map) return const IdeTalkModels();
    final groups = <IdeTalkModelGroup>[];
    for (final g in _maps(data['groups'], max: 30)) {
      final models = [
        for (final m in _maps(g['models'], max: 100))
          ?IdeTalkModelOption.tryParse(m),
      ];
      if (models.isEmpty) continue;
      groups.add(
        IdeTalkModelGroup(
          kind: _s(g['kind']),
          account: _s(g['account']),
          title: _s(g['title']),
          isDefault: _b(g['default']),
          models: models,
        ),
      );
    }
    return IdeTalkModels(
      defaultId: _s(data['default']),
      groups: groups,
      note: _s(data['note']),
      stale: _b(data['stale']),
    );
  }
}

/// Lượt chạy gần nhất của AI Agent.
final class IdeTalkLastRun {
  const IdeTalkLastRun({this.at, this.status = '', this.summary = ''});

  final DateTime? at;
  final String status;
  final String summary;
}

final class IdeTalkAgentInfo {
  const IdeTalkAgentInfo({
    this.name = '',
    this.schedule = '',
    this.scheduleLabel = '',
    this.enabled = false,
    this.scheduled = false,
    this.warning = '',
    this.model = '',
    this.lastRun,
    this.held = false,
  });

  final String name;
  final String schedule;
  final String scheduleLabel;
  final bool enabled;
  final bool scheduled;
  final String warning;
  final String model;
  final IdeTalkLastRun? lastRun;
  final bool held;

  static IdeTalkAgentInfo? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final run = raw['lastRun'];
    return IdeTalkAgentInfo(
      name: _s(raw['name']),
      schedule: _s(raw['schedule']),
      scheduleLabel: _s(raw['scheduleLabel']),
      enabled: _b(raw['enabled']),
      scheduled: _b(raw['scheduled']),
      warning: _s(raw['warning']),
      model: _s(raw['model']),
      held: _b(raw['held']),
      lastRun: run is Map
          ? IdeTalkLastRun(
              at: ideTimeFromSeconds(run['at']),
              status: _s(run['status']),
              summary: _s(run['summary']),
            )
          : null,
    );
  }
}

/// Dòng trong danh sách (`talk.list`).
final class IdeTalkSummary {
  const IdeTalkSummary({
    required this.id,
    this.title = '',
    this.updated,
    this.model = '',
    this.busy = false,
    this.count = 0,
    this.isAgent = false,
    this.unread = false,
    this.shared = false,
    this.pinned = false,
    this.archived = false,
    this.agent,
  });

  final String id;
  final String title;
  final DateTime? updated;
  final String model;
  final bool busy;
  final int count;
  final bool isAgent;
  final bool unread;
  final bool shared;
  final bool pinned;
  final bool archived;
  final IdeTalkAgentInfo? agent;

  static IdeTalkSummary? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    if (!ideTalkIdOk(id)) return null;
    return IdeTalkSummary(
      id: id,
      title: _s(raw['title']),
      updated: ideTimeFromSeconds(raw['updated']),
      model: _s(raw['model']),
      busy: _b(raw['busy']),
      count: ideSafeInt(raw['count']),
      isAgent: _s(raw['kind']) == 'agent',
      unread:
          raw['unread'] == true ||
          (raw['unread'] is num && (raw['unread'] as num) > 0),
      shared: _b(raw['shared']),
      pinned: _b(raw['pinned']),
      archived: _b(raw['archived']),
      agent: IdeTalkAgentInfo.tryParse(raw['agent']),
    );
  }

  static List<IdeTalkSummary> parseList(Object? data) {
    final items = data is Map ? data['items'] : null;
    return [
      if (items is List)
        for (final e in items.take(500)) ?IdeTalkSummary.tryParse(e),
    ];
  }
}

/// Tệp đính kèm hiện dưới tin.
final class IdeTalkFile {
  const IdeTalkFile({required this.name, this.label = '', this.size});

  final String name;
  final String label;
  final double? size;
}

final _fileNameRe = RegExp(r'^[A-Za-z0-9][\w.() -]{0,200}$');

/// Tên hợp lệ để gọi `talk.file` (không `/`, không `..`).
bool ideTalkFileNameOk(String name) =>
    _fileNameRe.hasMatch(name) && !name.contains('..');

final class IdeTalkStep {
  const IdeTalkStep(this.tool, this.detail);
  final String tool;
  final String detail;
}

final class IdeTalkPlanItem {
  const IdeTalkPlanItem(this.step, this.status);
  final String step;
  final String status;
}

final class IdeTalkSource {
  const IdeTalkSource(this.url, this.title);
  final String url;
  final String title;
}

final class IdeTalkMessage {
  const IdeTalkMessage({
    required this.id,
    required this.isUser,
    this.text = '',
    this.at,
    this.model = '',
    this.effort = '',
    this.pending = false,
    this.error = false,
    this.stage = '',
    this.note = '',
    this.images = const [],
    this.attachments = const [],
    this.files = const [],
    this.steps = const [],
    this.plan = const [],
    this.sources = const [],
    this.followups = const [],
  });

  final String id;
  final bool isUser;
  final String text;
  final DateTime? at;
  final String model;
  final String effort;
  final bool pending;
  final bool error;
  final String stage;
  final String note;

  /// Ảnh AI tạo (`images`) hoặc người dùng gửi (`attachments`) theo tên.
  final List<String> images;
  final List<String> attachments;
  final List<IdeTalkFile> files;
  final List<IdeTalkStep> steps;
  final List<IdeTalkPlanItem> plan;
  final List<IdeTalkSource> sources;
  final List<String> followups;

  static IdeTalkMessage? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    if (id.isEmpty || id.length > 64) return null;
    final role = _s(raw['role']);
    if (role != 'user' && role != 'assistant') return null;
    final images = _strings(raw['images'] ?? raw['outImages'], max: 30);
    return IdeTalkMessage(
      id: id,
      isUser: role == 'user',
      text: _clip(_s(raw['text']), ideTalkMaxMessageChars),
      at: ideTimeFromSeconds(raw['at']),
      model: _s(raw['model']),
      effort: _s(raw['effort']),
      pending: _b(raw['pending']),
      error: _b(raw['error']),
      stage: _s(raw['stage']),
      note: _s(raw['note']),
      images: images,
      attachments: _strings(raw['attachments'], max: 30),
      files: [
        for (final f in _maps(raw['files'], max: 30))
          if (_s(f['name']).isNotEmpty)
            IdeTalkFile(
              name: _s(f['name']),
              label: _s(f['label']),
              size: ideTalkNum(f['size']),
            ),
      ],
      steps: [
        for (final s in _maps(raw['steps'], max: 100))
          IdeTalkStep(_s(s['tool']), _s(s['detail'])),
      ],
      plan: [
        for (final p in _maps(raw['plan'], max: 50))
          IdeTalkPlanItem(_s(p['step']), _s(p['status'])),
      ],
      sources: [
        for (final p in _maps(raw['sources'], max: 30))
          if (_s(p['url']).isNotEmpty)
            IdeTalkSource(_s(p['url']), _s(p['title'])),
      ],
      followups: _strings(raw['followups'], max: 8),
    );
  }
}

final class IdeTalkQueueItem {
  const IdeTalkQueueItem({required this.id, required this.text});
  final String id;
  final String text;
}

/// Cuộc chat đầy đủ (`talk.get` / khung đầy đủ của stream).
final class IdeTalkConversation {
  const IdeTalkConversation({
    required this.id,
    this.title = '',
    this.model = '',
    this.busy = false,
    this.shared = false,
    this.queue = const [],
    this.queuePaused = false,
    this.isAgent = false,
    this.agent,
    this.contextUsed,
    this.contextWindow,
    this.truncatedBefore = 0,
    this.messages = const [],
  });

  final String id;
  final String title;
  final String model;
  final bool busy;
  final bool shared;
  final List<IdeTalkQueueItem> queue;
  final bool queuePaused;
  final bool isAgent;
  final IdeTalkAgentInfo? agent;
  final double? contextUsed;
  final double? contextWindow;
  final int truncatedBefore;
  final List<IdeTalkMessage> messages;

  /// Tin cuối đang chạy (AI đang viết).
  bool get working => busy || (messages.isNotEmpty && messages.last.pending);

  IdeTalkConversation withMessages(List<IdeTalkMessage> next) =>
      IdeTalkConversation(
        id: id,
        title: title,
        model: model,
        busy: busy,
        shared: shared,
        queue: queue,
        queuePaused: queuePaused,
        isAgent: isAgent,
        agent: agent,
        contextUsed: contextUsed,
        contextWindow: contextWindow,
        truncatedBefore: truncatedBefore,
        messages: next,
      );

  /// Khung quá nhiều tin thì bỏ (tránh nuốt bộ nhớ): cổng đã giữ ≤ 1 MB.
  static const maxMessages = 3000;

  /// Trùng `id` thì giữ tin sau (bỏ tin trước).
  static List<IdeTalkMessage> _dedupe(List<IdeTalkMessage> list) {
    final ids = <String>{};
    for (final m in list) {
      if (!ids.add(m.id)) {
        final latest = <String, IdeTalkMessage>{};
        for (final x in list) {
          latest[x.id] = x;
        }
        return [
          for (final x in list)
            if (identical(latest[x.id], x)) x,
        ];
      }
    }
    return list;
  }

  static IdeTalkConversation? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    final msgs = raw['messages'];
    if (!ideTalkIdOk(id) || msgs is! List || msgs.length > maxMessages) {
      return null;
    }
    final ctx = raw['context'];
    return IdeTalkConversation(
      id: id,
      title: _s(raw['title']),
      model: _s(raw['model']),
      busy: _b(raw['busy']),
      shared: _b(raw['shared']),
      queue: [
        for (final q in _maps(raw['queue'], max: 20))
          if (_s(q['id']).isNotEmpty)
            IdeTalkQueueItem(id: _s(q['id']), text: _s(q['text'])),
      ],
      queuePaused: _b(raw['queuePaused']),
      isAgent: _s(raw['kind']) == 'agent',
      agent: IdeTalkAgentInfo.tryParse(raw['agent']),
      contextUsed: ctx is Map ? ideTalkNum(ctx['used']) : null,
      contextWindow: ctx is Map ? ideTalkNum(ctx['window']) : null,
      truncatedBefore: ideSafeInt(raw['truncated_before']).clamp(0, 1 << 30),
      messages: _dedupe([for (final m in msgs) ?IdeTalkMessage.tryParse(m)]),
    );
  }
}

/// Khung của stream `talk` (đã bỏ lớp `talk_delta`).
sealed class IdeTalkFrame {
  const IdeTalkFrame();

  /// Khung sai dạng → `null` (bỏ qua).
  static IdeTalkFrame? parse(Map<String, Object?> f) {
    if (f['gone'] == true) return const IdeTalkGone();
    if (f['heartbeat'] == true) return const IdeTalkHeartbeat();
    if (f['delta'] == true) {
      final m = IdeTalkMessage.tryParse(f['message']);
      if (m == null) return null;
      final id = f['id'];
      return IdeTalkDelta(m, talkId: id is String ? id : null);
    }
    final c = IdeTalkConversation.tryParse(f);
    return c == null ? null : IdeTalkFull(c);
  }
}

final class IdeTalkFull extends IdeTalkFrame {
  const IdeTalkFull(this.conversation);
  final IdeTalkConversation conversation;
}

final class IdeTalkDelta extends IdeTalkFrame {
  const IdeTalkDelta(this.message, {this.talkId});
  final IdeTalkMessage message;

  /// Mã cuộc ghi trong khung (`null` nếu khung không ghi).
  final String? talkId;
}

final class IdeTalkHeartbeat extends IdeTalkFrame {
  const IdeTalkHeartbeat();
}

final class IdeTalkGone extends IdeTalkFrame {
  const IdeTalkGone();
}

/// Kết quả `talk.send`.
final class IdeTalkSendResult {
  const IdeTalkSendResult({
    required this.id,
    this.queued = false,
    this.note = '',
  });
  final String id;
  final bool queued;
  final String note;
}

/// Kết quả `talk.agent_save`.
final class IdeTalkAgentSaved {
  const IdeTalkAgentSaved({
    required this.id,
    this.scheduled = false,
    this.warning = '',
    this.next = '',
    this.nextAt,
  });
  final String id;
  final bool scheduled;
  final String warning;
  final String next;
  final DateTime? nextAt;
}

/// Bản nháp AI Agent từ `talk.agent_draft`.
final class IdeTalkAgentDraft {
  const IdeTalkAgentDraft({
    this.name = '',
    this.task = '',
    this.schedule = '',
    this.scheduleLabel = '',
  });
  final String name;
  final String task;
  final String schedule;
  final String scheduleLabel;
}

/// Lời nhãn mức suy nghĩ.
String ideTalkEffortLabel(String e, {required bool vi}) => switch (e) {
  'low' => vi ? 'Thấp' : 'Low',
  'medium' => vi ? 'Vừa' : 'Medium',
  'high' => vi ? 'Cao' : 'High',
  'xhigh' => vi ? 'Rất cao' : 'Extra high',
  'minimal' => vi ? 'Tối thiểu' : 'Minimal',
  'max' => vi ? 'Tối đa' : 'Max',
  _ => e,
};
