/// Mô hình Skill và AI Agent (Phụ lục C1). Mọi trường đọc phòng thủ: kiểu sai,
/// NaN / vô cực / âm / quá lớn không làm vỡ màn.
library;

import 'ide_more_time.dart';

// ---------------------------------------------------------------- đọc JSON

/// Chuỗi cắt tối đa [max] ký tự; không phải chuỗi → [fallback].
String toolStr(Object? v, {int max = 600, String fallback = ''}) {
  if (v is! String) return fallback;
  return v.length > max ? v.substring(0, max) : v;
}

/// Số hữu hạn không âm; còn lại → `null`.
double? toolNum(Object? v, {double max = 1e15}) {
  if (v is! num || !v.isFinite || v < 0 || v > max) return null;
  return v.toDouble();
}

/// Phần trăm 0–100 (cắt ngoài khoảng); không hợp lệ → `null`.
double? toolPct(Object? v) {
  final n = toolNum(v, max: 1e9);
  return n?.clamp(0, 100).toDouble();
}

int toolInt(Object? v, [int fallback = 0]) {
  final n = toolNum(v, max: 9e15);
  return n == null ? fallback : n.toInt();
}

bool toolBool(Object? v) => v == true;

Map<String, Object?> toolMap(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : const {};

List<Map<String, Object?>> toolMaps(Object? v, {int max = 500}) => v is List
    ? [
        for (final e in v.take(max))
          if (e is Map) Map<String, Object?>.from(e),
      ]
    : const [];

List<String> toolStrings(Object? v, {int max = 20, int len = 300}) => v is List
    ? [
        for (final e in v.take(max))
          if (e is String) toolStr(e, max: len),
      ]
    : const [];

/// Giây Unix → giờ địa phương; quá lớn / không hợp lệ → `null` (hiện "—").
DateTime? toolTime(Object? seconds) => ideTimeFromSeconds(seconds);

// ---------------------------------------------------------------- skill / lệnh

final class IdeSkillIntro {
  const IdeSkillIntro({
    this.title = '',
    this.summary = '',
    this.when = '',
    this.notFor = '',
    this.how = '',
    this.examples = const [],
    this.benefits = const [],
    this.category = '',
  });

  final String title;
  final String summary;
  final String when;
  final String notFor;
  final String how;
  final List<String> examples;
  final List<String> benefits;
  final String category;

  bool get isEmpty =>
      summary.isEmpty &&
      when.isEmpty &&
      notFor.isEmpty &&
      how.isEmpty &&
      examples.isEmpty &&
      benefits.isEmpty;

  static IdeSkillIntro? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = toolMap(raw);
    return IdeSkillIntro(
      title: toolStr(m['title'], max: 200),
      summary: toolStr(m['summary'], max: 1500),
      when: toolStr(m['when'], max: 1000),
      notFor: toolStr(m['not_for'], max: 1000),
      how: toolStr(m['how'], max: 1000),
      examples: toolStrings(m['examples'], max: 4),
      benefits: toolStrings(m['benefits'], max: 5),
      category: toolStr(m['category'], max: 40),
    );
  }
}

/// Một skill / agent / lệnh, đã cài hoặc còn trong thư viện.
final class IdeToolEntry {
  const IdeToolEntry({
    required this.kind,
    required this.name,
    this.description = '',
    this.version,
    this.libraryVersion,
    this.installedVersion,
    this.state = '',
    this.source = '',
    this.installed = false,
    this.model = '',
    this.intro,
  });

  /// `skill` | `agent` | `command`.
  final String kind;
  final String name;
  final String description;
  final String? version;
  final String? libraryVersion;
  final String? installedVersion;

  /// `current` | `outdated` | `modified` | `local` | `missing-library`.
  final String state;
  final String source;
  final bool installed;
  final String model;
  final IdeSkillIntro? intro;

  bool get canUpdate =>
      installed && (state == 'outdated' || state == 'modified');

  /// Tên hợp lệ để gửi lên IDE (tránh gửi tên rác do máy chủ lỗi).
  bool get nameOk =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(name);
}

final class IdeToolCatalog {
  const IdeToolCatalog({
    this.project = '',
    this.writable = false,
    this.defaults = const [],
    this.installed = const [],
    this.library = const [],
  });

  final String project;
  final bool writable;
  final List<String> defaults;
  final List<IdeToolEntry> installed;

  /// Thư viện chưa cài.
  final List<IdeToolEntry> library;

  static String? _ver(Object? v) {
    if (v == null) return null;
    if (v is num) return v.isFinite ? '$v' : null;
    return v is String && v.isNotEmpty ? toolStr(v, max: 40) : null;
  }

  /// `skills.list`.
  factory IdeToolCatalog.parseSkills(Object? data) {
    final m = toolMap(data);
    final installed = <IdeToolEntry>[
      for (final s in toolMaps(m['installed']))
        if (toolStr(s['name']).isNotEmpty)
          IdeToolEntry(
            kind: 'skill',
            name: toolStr(s['name'], max: 128),
            description: toolStr(s['description'], max: 1000),
            version: _ver(s['version']),
            libraryVersion: _ver(s['library_version']),
            installedVersion: _ver(s['installed_version']),
            state: toolStr(s['state'], max: 30),
            source: toolStr(s['source'], max: 20),
            installed: true,
            intro: IdeSkillIntro.tryParse(s['intro']),
          ),
    ];
    final have = {for (final e in installed) e.name};
    final library = <IdeToolEntry>[
      for (final s in toolMaps(m['library']))
        if (toolStr(s['name']).isNotEmpty &&
            !toolBool(s['installed']) &&
            !have.contains(toolStr(s['name'], max: 128)))
          IdeToolEntry(
            kind: 'skill',
            name: toolStr(s['name'], max: 128),
            description: toolStr(s['description'], max: 1000),
            version: _ver(s['version']),
            source: 'library',
            intro: IdeSkillIntro.tryParse(s['intro']),
          ),
    ];
    return IdeToolCatalog(
      project: toolStr(m['project'], max: 120),
      writable: toolBool(m['writable']),
      defaults: toolStrings(m['defaults'], max: 50, len: 128),
      installed: installed,
      library: library,
    );
  }

  /// `skills.agent_list` (agent và lệnh mẫu).
  factory IdeToolCatalog.parseAgents(Object? data) {
    final m = toolMap(data);
    String kindOf(Object? k) => k == 'command' ? 'command' : 'agent';
    final installed = <IdeToolEntry>[
      for (final s in toolMaps(m['installed']))
        if (toolStr(s['name']).isNotEmpty)
          IdeToolEntry(
            kind: kindOf(s['kind']),
            name: toolStr(s['name'], max: 128),
            description: toolStr(s['description'], max: 1000),
            version: _ver(s['version']),
            libraryVersion: _ver(s['library_version']),
            installedVersion: _ver(s['installed_version']),
            state: toolStr(s['state'], max: 30),
            installed: true,
          ),
    ];
    final have = {for (final e in installed) '${e.kind}/${e.name}'};
    final library = <IdeToolEntry>[
      for (final s in toolMaps(m['library']))
        if (toolStr(s['name']).isNotEmpty &&
            !toolBool(s['installed']) &&
            !have.contains(
              '${kindOf(s['kind'])}/${toolStr(s['name'], max: 128)}',
            ))
          IdeToolEntry(
            kind: kindOf(s['kind']),
            name: toolStr(s['name'], max: 128),
            description: toolStr(s['description'], max: 1000),
            version: _ver(s['version']),
            model: toolStr(s['model'], max: 60),
            source: 'library',
          ),
    ];
    return IdeToolCatalog(
      project: toolStr(m['project'], max: 120),
      writable: toolBool(m['writable']),
      installed: installed,
      library: library,
    );
  }
}

// ---------------------------------------------------------------- agent chạy

final class IdeAgentActivity {
  const IdeAgentActivity({
    this.runs = 0,
    this.today = 0,
    this.errors = 0,
    this.running = 0,
    this.tokens,
    this.tokensToday,
    this.cost,
    this.costToday,
    this.daily = const [],
    this.last,
  });

  final int runs;
  final int today;
  final int errors;
  final int running;
  final double? tokens;
  final double? tokensToday;
  final double? cost;
  final double? costToday;
  final List<double> daily;
  final DateTime? last;

  factory IdeAgentActivity.parse(Object? raw) {
    final m = toolMap(raw);
    return IdeAgentActivity(
      runs: toolInt(m['runs']),
      today: toolInt(m['today']),
      errors: toolInt(m['errors']),
      running: m['running'] is List ? (m['running'] as List).length : 0,
      tokens: toolNum(m['tokens']),
      tokensToday: toolNum(m['tokens_today']),
      cost: toolNum(m['cost']),
      costToday: toolNum(m['cost_today']),
      daily: m['daily'] is List
          ? [for (final v in (m['daily'] as List).take(30)) toolNum(v) ?? 0]
          : const [],
      last: toolTime(m['last']),
    );
  }
}

final class IdeAgentInfo {
  const IdeAgentInfo({
    required this.name,
    this.kind = 'agent',
    this.scope = '',
    this.description = '',
    this.model = '',
    this.state = '',
    this.checkErrors = 0,
    this.checkWarnings = 0,
    this.activity = const IdeAgentActivity(),
  });

  final String name;
  final String kind;
  final String scope;
  final String description;
  final String model;
  final String state;
  final int checkErrors;
  final int checkWarnings;
  final IdeAgentActivity activity;

  static IdeAgentInfo? tryParse(
    Map<String, Object?> m, {
    String kind = 'agent',
  }) {
    final name = toolStr(m['name'], max: 128);
    if (name.isEmpty) return null;
    final check = toolMap(m['check']);
    final act = m['activity'] ?? (m['use'] is Map ? m['use'] : null);
    final use = toolMap(m['use']);
    return IdeAgentInfo(
      name: name,
      kind: kind,
      scope: toolStr(m['scope'], max: 20),
      description: toolStr(m['description'], max: 600),
      model: toolStr(m['model'], max: 60),
      state: toolStr(m['state'], max: 30),
      checkErrors: toolInt(check['errors']),
      checkWarnings: toolInt(check['warnings']),
      activity: kind == 'command'
          ? IdeAgentActivity(
              runs: toolInt(use['runs']),
              last: toolTime(use['last']),
            )
          : IdeAgentActivity.parse(act),
    );
  }
}

final class IdeAgentRun {
  const IdeAgentRun({
    required this.agent,
    this.desc = '',
    this.at,
    this.status = '',
    this.ms,
    this.tokens,
    this.tools = 0,
  });

  final String agent;
  final String desc;
  final DateTime? at;
  final String status;
  final double? ms;
  final double? tokens;
  final int tools;
}

final class IdeAgentTotals {
  const IdeAgentTotals({
    this.agents = 0,
    this.runs = 0,
    this.today = 0,
    this.running = 0,
    this.tokensToday,
    this.errors = 0,
  });

  final int agents;
  final int runs;
  final int today;
  final int running;
  final double? tokensToday;
  final int errors;
}

final class IdeAgentsOverview {
  const IdeAgentsOverview({
    this.days = 7,
    this.agents = const [],
    this.commands = const [],
    this.recent = const [],
    this.totals = const IdeAgentTotals(),
  });

  final int days;
  final List<IdeAgentInfo> agents;
  final List<IdeAgentInfo> commands;
  final List<IdeAgentRun> recent;
  final IdeAgentTotals totals;

  bool get isEmpty => agents.isEmpty && commands.isEmpty && recent.isEmpty;

  factory IdeAgentsOverview.parse(Object? data) {
    final m = toolMap(data);
    final t = toolMap(m['totals']);
    return IdeAgentsOverview(
      days: toolInt(m['days'], 7).clamp(1, 30),
      agents: [
        for (final a in toolMaps(m['agents'])) ?IdeAgentInfo.tryParse(a),
      ],
      commands: [
        for (final c in toolMaps(m['commands']))
          ?IdeAgentInfo.tryParse(c, kind: 'command'),
      ],
      recent: [
        for (final r in toolMaps(m['recent'], max: 100))
          if (toolStr(r['agent']).isNotEmpty)
            IdeAgentRun(
              agent: toolStr(r['agent'], max: 128),
              desc: toolStr(r['desc'], max: 300),
              at: toolTime(r['at']),
              status: toolStr(r['status'], max: 20),
              ms: toolNum(r['ms']),
              tokens: toolNum(r['tokens']),
              tools: toolInt(r['tools']),
            ),
      ],
      totals: IdeAgentTotals(
        agents: toolInt(t['agents']),
        runs: toolInt(t['runs']),
        today: toolInt(t['today']),
        running: toolInt(t['running']),
        tokensToday: toolNum(t['tokens_today']),
        errors: toolInt(t['errors']),
      ),
    );
  }
}

/// Agent chạy theo lịch (`agents.status`, dự án công ty).
final class IdeSchedAgent {
  const IdeSchedAgent({
    required this.name,
    this.description = '',
    this.schedule = '',
    this.enabled = true,
    this.health = 'never',
    this.lastSummary = '',
    this.lastAt,
    this.problems = const [],
  });

  final String name;
  final String description;
  final String schedule;
  final bool enabled;
  final String health;
  final String lastSummary;
  final DateTime? lastAt;
  final List<String> problems;

  static List<IdeSchedAgent> parseStatus(Object? data, String project) {
    final out = <IdeSchedAgent>[];
    for (final p in toolMaps(toolMap(data)['projects'])) {
      if (p['name'] != project) continue;
      for (final a in toolMaps(p['agents'], max: 200)) {
        final name = toolStr(a['name'], max: 128);
        if (name.isEmpty) continue;
        final last = toolMap(a['last']);
        out.add(
          IdeSchedAgent(
            name: name,
            description: toolStr(a['description'], max: 400),
            schedule: toolStr(a['schedule'], max: 100),
            enabled: a['enabled'] != false,
            health: toolStr(a['health'], max: 20, fallback: 'never'),
            lastSummary: toolStr(last['summary'], max: 300),
            lastAt: toolTime(last['ts']),
            problems: toolStrings(a['problems'], max: 5),
          ),
        );
      }
    }
    return out;
  }
}
