import 'ide_more_time.dart';
import 'ide_talk_models.dart' show ideTalkNum;

/// Hồ sơ và mức dùng AI (`profile.*`, `ai.*`, Phụ lục C2). Số NaN / vô cực /
/// âm → `null`, hiện "—".

String _s(Object? v) => v is String ? v : '';

List<Map<Object?, Object?>> _maps(Object? v, {int max = 200}) => [
  if (v is List)
    for (final e in v.take(max))
      if (e is Map) e,
];

/// Số lớn gọn: 1,2K / 3,4M; `null` → "—".
String ideFormatCount(double? v) {
  if (v == null) return '—';
  if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e4) return '${(v / 1e3).toStringAsFixed(1)}K';
  return v.round().toString();
}

/// Giá quy đổi USD; `null` → "—".
String ideFormatUsd(double? v) {
  if (v == null) return '—';
  return '\$${v.toStringAsFixed(v < 10 ? 2 : 0)}';
}

final class IdeProfileProject {
  const IdeProfileProject(this.name, this.mode, this.role);
  final String name;
  final String mode;
  final String role;
}

/// Một dòng dùng AI (tổng, theo model hoặc theo dự án).
final class IdeUsageRow {
  const IdeUsageRow({
    this.label = '',
    this.tool = '',
    this.input,
    this.output,
    this.cacheRead,
    this.cacheWrite,
    this.cost,
    this.requests,
  });

  final String label;
  final String tool;
  final double? input;
  final double? output;
  final double? cacheRead;
  final double? cacheWrite;
  final double? cost;
  final double? requests;

  static IdeUsageRow parse(Map<Object?, Object?> m, {String label = ''}) =>
      IdeUsageRow(
        label: label,
        tool: _s(m['tool']),
        input: ideTalkNum(m['input']),
        output: ideTalkNum(m['output']),
        cacheRead: ideTalkNum(m['cache_read']),
        cacheWrite: ideTalkNum(m['cache_write']),
        cost: ideTalkNum(m['cost_usd']),
        requests: ideTalkNum(m['requests']),
      );
}

final class IdeProfileAgent {
  const IdeProfileAgent({
    required this.project,
    required this.name,
    this.health = '',
    this.schedule,
    this.lastAt,
    this.lastSummary = '',
    this.role = '',
  });
  final String project;
  final String name;
  final String health;
  final String? schedule;
  final DateTime? lastAt;
  final String lastSummary;
  final String role;
}

final class IdePersonalAgent {
  const IdePersonalAgent(this.name, this.tool, this.schedule, this.enabled);
  final String name;
  final String tool;
  final String schedule;
  final bool enabled;
}

final class IdeProfile {
  const IdeProfile({
    this.user = '',
    this.full,
    this.email,
    this.admin = false,
    this.hasAvatar = false,
    this.avatarVersion,
    this.projects = const [],
    this.days = 30,
    this.totals,
    this.byModel = const [],
    this.byProject = const [],
    this.rateVnd,
    this.agents = const [],
    this.personalAgents = const [],
  });

  final String user;
  final String? full;
  final String? email;
  final bool admin;
  final bool hasAvatar;
  final String? avatarVersion;
  final List<IdeProfileProject> projects;
  final int days;
  final IdeUsageRow? totals;
  final List<IdeUsageRow> byModel;
  final List<IdeUsageRow> byProject;
  final double? rateVnd;
  final List<IdeProfileAgent> agents;
  final List<IdePersonalAgent> personalAgents;

  String get displayName =>
      (full != null && full!.trim().isNotEmpty) ? full!.trim() : user;

  static IdeProfile parse(Object? data) {
    if (data is! Map) return const IdeProfile();
    final usage = data['usage'];
    final u = usage is Map ? usage : const <Object?, Object?>{};
    final totals = u['totals'];
    final ver = data['avatar_version'];
    return IdeProfile(
      user: _s(data['user']),
      full: data['full'] is String ? data['full'] as String : null,
      email: data['email'] is String ? data['email'] as String : null,
      admin: data['admin'] == true,
      hasAvatar: data['has_avatar'] == true,
      avatarVersion: ver == null ? null : '$ver',
      projects: [
        for (final p in _maps(data['projects']))
          if (_s(p['name']).isNotEmpty)
            IdeProfileProject(_s(p['name']), _s(p['mode']), _s(p['role'])),
      ],
      days: switch (ideSafeInt(u['days'], 30)) {
        7 => 7,
        90 => 90,
        _ => 30,
      },
      totals: totals is Map ? IdeUsageRow.parse(totals) : null,
      byModel: [
        for (final m in _maps(u['by_model']))
          IdeUsageRow.parse(m, label: _s(m['model'])),
      ],
      byProject: [
        for (final m in _maps(u['by_project']))
          IdeUsageRow.parse(m, label: _s(m['project'])),
      ],
      rateVnd: ideTalkNum(u['rate_vnd']),
      agents: [
        for (final a in _maps(data['agents']))
          IdeProfileAgent(
            project: _s(a['project']),
            name: _s(a['name']),
            health: _s(a['health']),
            schedule: a['schedule'] is String ? a['schedule'] as String : null,
            lastAt: ideTimeFromSeconds(a['last_at']),
            lastSummary: _s(a['last_summary']),
            role: _s(a['role']),
          ),
      ],
      personalAgents: [
        for (final a in _maps(data['personal_agents']))
          IdePersonalAgent(
            _s(a['name']),
            _s(a['tool']),
            _s(a['schedule']),
            a['enabled'] == true,
          ),
      ],
    );
  }
}

/// Một ngày trong `profile.usage_daily`.
final class IdeUsageDay {
  const IdeUsageDay(
    this.day,
    this.input,
    this.output,
    this.cost,
    this.requests,
  );
  final String day;
  final double? input;
  final double? output;
  final double? cost;
  final double? requests;

  static List<IdeUsageDay> parseList(Object? data) {
    final items = data is Map ? data['items'] : null;
    final day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    return [
      for (final m in _maps(items, max: 120))
        if (day.hasMatch(_s(m['day'])))
          IdeUsageDay(
            _s(m['day']),
            ideTalkNum(m['input']),
            ideTalkNum(m['output']),
            ideTalkNum(m['cost_usd']),
            ideTalkNum(m['requests']),
          ),
    ];
  }
}

/// Tài khoản AI đang dùng (một nhánh của `ai.usage`).
final class IdeAiAccount {
  const IdeAiAccount({
    this.id = '',
    this.label = '',
    this.from = '',
    this.note = '',
  });
  final String id;
  final String label;
  final String from;
  final String note;

  bool get isEmpty => id.isEmpty && label.isEmpty;
}

final class IdeAiGrant {
  const IdeAiGrant(this.tool, this.label, this.mode);
  final String tool;
  final String label;
  final String mode;
}

final class IdeAiUsage {
  const IdeAiUsage({
    this.claude = const IdeAiAccount(),
    this.codex = const IdeAiAccount(),
    this.project = '',
    this.granted = const [],
  });
  final IdeAiAccount claude;
  final IdeAiAccount codex;
  final String project;
  final List<IdeAiGrant> granted;

  static IdeAiAccount _acc(Object? v) => v is Map
      ? IdeAiAccount(
          id: _s(v['id']),
          label: _s(v['label']),
          from: _s(v['from']),
          note: _s(v['note']),
        )
      : const IdeAiAccount();

  static IdeAiUsage parse(Object? data) {
    if (data is! Map) return const IdeAiUsage();
    return IdeAiUsage(
      claude: _acc(data['claude']),
      codex: _acc(data['codex']),
      project: _s(data['project']),
      granted: [
        for (final g in _maps(data['granted']))
          IdeAiGrant(_s(g['tool']), _s(g['label']), _s(g['mode'])),
      ],
    );
  }
}

/// Một cửa sổ hạn mức của tài khoản.
final class IdeQuotaWindow {
  const IdeQuotaWindow(this.name, this.label, this.used, this.resetsAt);
  final String name;
  final String label;

  /// 0–100; ngoài khoảng / không phải số → `null`.
  final double? used;
  final DateTime? resetsAt;
}

final class IdeAiRoute {
  const IdeAiRoute({
    required this.id,
    this.type = '',
    this.label = '',
    this.state = '',
    this.blocked = false,
    this.windows = const [],
  });
  final String id;
  final String type;
  final String label;
  final String state;
  final bool blocked;
  final List<IdeQuotaWindow> windows;

  static List<IdeAiRoute> parseList(Object? data) {
    final acc = data is Map ? data['accounts'] : null;
    if (acc is! Map) return const [];
    final out = <IdeAiRoute>[];
    for (final e in acc.entries.take(50)) {
      final v = e.value;
      if (v is! Map) continue;
      final quota = v['quota'];
      out.add(
        IdeAiRoute(
          id: _s(v['id']).isEmpty ? '${e.key}' : _s(v['id']),
          type: _s(v['type']),
          label: _s(v['label']),
          state: _s(v['state']),
          blocked: v['blocked'] == true,
          windows: [
            if (quota is Map)
              for (final w in _maps(quota['windows'], max: 10))
                IdeQuotaWindow(
                  _s(w['name']),
                  _s(w['label']),
                  _pct(w['used']),
                  ideTimeFromSeconds(w['resets_at']),
                ),
          ],
        ),
      );
    }
    return out;
  }

  static double? _pct(Object? v) {
    final n = ideTalkNum(v);
    return n == null || n > 100 ? null : n;
  }
}
