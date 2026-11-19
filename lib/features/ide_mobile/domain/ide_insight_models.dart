import 'ide_more_time.dart';

String _s(Object? v) => v is String ? v : '';

// ------------------------------------------------------------- báo cáo

/// Một lần đọc `jobs.tail` của việc nền.
final class IdeJobTail {
  const IdeJobTail({
    this.text = '',
    this.next = 0,
    this.status = '',
    this.done = false,
    this.result,
  });

  final String text;
  final int next;
  final String status;
  final bool done;
  final Object? result;

  static IdeJobTail parse(Object? data) {
    if (data is! Map) return const IdeJobTail();
    return IdeJobTail(
      text: _s(data['text']),
      next: data['next'] is num ? (data['next'] as num).toInt() : 0,
      status: _s(data['status']),
      done: data['done'] == true,
      result: data['result'],
    );
  }
}

final class IdeReportFact {
  const IdeReportFact(this.label, this.value);

  final String label;
  final String value;
}

final class IdeReport {
  const IdeReport({
    this.generatedAt,
    this.my = false,
    this.facts = const [],
    this.alerts = const [],
    this.aiText = '',
    this.aiTips = const [],
    this.aiState = '',
  });

  final DateTime? generatedAt;
  final bool my;

  /// Số liệu chính (đã làm phẳng, nhãn tiếng Việt).
  final List<IdeReportFact> facts;
  final List<String> alerts;

  /// Nhận xét của AI (Markdown).
  final String aiText;
  final List<String> aiTips;
  final String aiState;

  bool get hasAi => aiText.trim().isNotEmpty || aiTips.isNotEmpty;

  static const _labels = {
    'name': 'Dự án',
    'status': 'Trạng thái',
    'deploy': 'Triển khai gần nhất',
    'commits_7d': 'Commit 7 ngày',
    'commits_30d': 'Commit 30 ngày',
    'today': 'Hôm nay',
    'd7': '7 ngày',
    'd30': '30 ngày',
    'hours_total': 'Giờ làm',
    'prs_open': 'PR đang mở',
    'prs_merged': 'PR đã gộp',
    'members': 'Thành viên',
  };

  static String _label(String key) => _labels[key] ?? key;

  static String _scalar(Object? v) {
    if (v is bool) return v ? 'Có' : 'Không';
    if (v is double) {
      return v == v.roundToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(1);
    }
    return '$v';
  }

  static void _flatten(String prefix, Object? v, List<IdeReportFact> out) {
    if (out.length >= 24) return;
    if (v is Map) {
      for (final e in v.entries) {
        final k = e.key.toString();
        _flatten(
          prefix.isEmpty ? _label(k) : '$prefix · ${_label(k)}',
          e.value,
          out,
        );
      }
    } else if (v is num || v is bool || (v is String && v.isNotEmpty)) {
      if (prefix.isNotEmpty) out.add(IdeReportFact(prefix, _scalar(v)));
    }
  }

  static String _alertText(Object? a) {
    if (a is String) return a;
    if (a is Map) {
      for (final k in const ['text', 'message', 'title', 'msg']) {
        if (a[k] is String && (a[k] as String).isNotEmpty) {
          return a[k] as String;
        }
      }
    }
    return '';
  }

  /// `result` của job `report.self`; không phải bảng → `null`.
  static IdeReport? parse(Object? result) {
    if (result is! Map) return null;
    final facts = <IdeReportFact>[];
    final project = result['project'];
    if (project is Map) {
      // Bỏ danh sách / bảng dài, chỉ lấy số liệu đơn.
      _flatten('', {
        for (final e in project.entries)
          if (e.value is! List) e.key: e.value,
      }, facts);
    }
    final alerts = result['alerts'];
    final ai = result['ai'] is Map ? result['ai'] as Map : const {};
    final tips = ai['goi_y'];
    final text = _s(ai['nhan_xet']).isNotEmpty
        ? _s(ai['nhan_xet'])
        : _s(ai['text']);
    return IdeReport(
      generatedAt:
          ideTimeFromSeconds(result['generated_at']) ??
          DateTime.tryParse(_s(result['generated_at']))?.toLocal(),
      my: result['my'] == true,
      facts: facts,
      alerts: [
        if (alerts is List)
          for (final a in alerts)
            if (_alertText(a).isNotEmpty) _alertText(a),
      ],
      aiText: text,
      aiTips: [
        if (tips is List)
          for (final t in tips)
            if (t is String && t.isNotEmpty) t,
      ],
      aiState: _s(ai['state']),
    );
  }
}

// ------------------------------------------------------------ kiến trúc

final class IdeRisk {
  const IdeRisk({required this.text, this.level = '', this.id = ''});

  final String text;
  final String level;
  final String id;
}

final class IdeArchStep {
  const IdeArchStep({required this.name, this.status = '', this.done = false});

  final String name;
  final String status;
  final bool done;
}

final class IdeKientruc {
  const IdeKientruc({
    this.exists = false,
    this.sha = '',
    this.name = '',
    this.diagram,
    this.risks = const [],
    this.steps = const [],
    this.progress,
    this.notes = '',
    this.mtime,
  });

  final bool exists;
  final String sha;
  final String name;

  /// `{zones, nodes, edges}` để vẽ; `null` khi chưa có nút nào.
  final Map<String, Object?>? diagram;
  final List<IdeRisk> risks;
  final List<IdeArchStep> steps;

  /// 0..1 nếu IDE báo tiến độ.
  final double? progress;
  final String notes;
  final DateTime? mtime;

  static IdeKientruc parse(Object? data) {
    if (data is! Map) return const IdeKientruc();
    final d = data['data'] is Map ? data['data'] as Map : const {};
    final nodes = d['nodes'];
    final risks = d['risks'];
    final steps = d['steps'];
    final progress = d['progress'];
    String pick(Map m, List<String> keys) {
      for (final k in keys) {
        if (m[k] is String && (m[k] as String).isNotEmpty) {
          return m[k] as String;
        }
      }
      return '';
    }

    double? ratio(Object? p) {
      if (p is num) return (p > 1 ? p / 100 : p).clamp(0, 1).toDouble();
      if (p is Map) {
        final done = p['done'] ?? p['xong'];
        final total = p['total'] ?? p['tong'];
        if (done is num && total is num && total > 0) {
          return (done / total).clamp(0, 1).toDouble();
        }
      }
      return null;
    }

    final stepList = [
      if (steps is List)
        for (final s in steps)
          if (s is Map)
            IdeArchStep(
              name: pick(s, ['name', 'title', 'text', 'ten']),
              status: _s(s['status']),
              done:
                  s['done'] == true ||
                  const ['done', 'xong', 'ok'].contains(_s(s['status'])),
            )
          else if (s is String)
            IdeArchStep(name: s),
    ];
    return IdeKientruc(
      exists: data['exists'] != false,
      sha: _s(data['sha']),
      name: _s(d['name']),
      diagram: nodes is List && nodes.isNotEmpty
          ? {
              'zones': d['zones'] is List ? d['zones'] : const [],
              'nodes': nodes,
              'edges': d['edges'] is List ? d['edges'] : const [],
            }
          : null,
      risks: [
        if (risks is List)
          for (final r in risks)
            if (r is String && r.isNotEmpty)
              IdeRisk(text: r)
            else if (r is Map &&
                pick(r, ['text', 'title', 'desc', 'mo_ta']).isNotEmpty)
              IdeRisk(
                text: pick(r, ['text', 'title', 'desc', 'mo_ta']),
                level: pick(r, ['level', 'severity', 'muc']),
                id: pick(r, ['id', 'code']),
              ),
      ],
      steps: [
        for (final s in stepList)
          if (s.name.isNotEmpty) s,
      ],
      progress:
          ratio(progress) ??
          (stepList.isEmpty
              ? null
              : stepList.where((s) => s.done).length / stepList.length),
      notes: data['notes'] is String ? data['notes'] as String : '',
      mtime: ideTimeFromSeconds(data['mtime']),
    );
  }
}

final class IdeArchIssue {
  const IdeArchIssue({
    required this.error,
    required this.code,
    required this.text,
    this.ref = '',
  });

  /// `loi` (true) hay `canh-bao` (false).
  final bool error;
  final String code;
  final String text;
  final String ref;
}

final class IdeKientrucCheck {
  const IdeKientrucCheck({
    this.ok = true,
    this.issues = const [],
    this.errors = 0,
    this.warnings = 0,
  });

  final bool ok;
  final List<IdeArchIssue> issues;
  final int errors;
  final int warnings;

  static IdeKientrucCheck parse(Object? data) {
    if (data is! Map) return const IdeKientrucCheck();
    final raw = data['issues'];
    final issues = [
      if (raw is List)
        for (final e in raw)
          if (e is Map)
            IdeArchIssue(
              error: e['level'] == _kientrucErrorKey,
              code: _s(e['code']),
              text: _s(e['text']),
              ref: _s(e['ref']),
            ),
    ];
    final counts = data['counts'] is Map ? data['counts'] as Map : const {};
    return IdeKientrucCheck(
      ok: data['ok'] != false,
      issues: issues,
      errors: counts[_kientrucErrorKey] is num
          ? (counts[_kientrucErrorKey] as num).toInt()
          : issues.where((i) => i.error).length,
      warnings: counts['canh_bao'] is num
          ? (counts['canh_bao'] as num).toInt()
          : issues.where((i) => !i.error).length,
    );
  }
}

// ------------------------------------------------------------ changelog

final class IdeChangelogItem {
  const IdeChangelogItem({
    required this.version,
    this.date = '',
    this.title = '',
    this.body = '',
  });

  final String version;
  final String date;
  final String title;
  final String body;
}

final class IdeChangelog {
  const IdeChangelog({this.version = '', this.items = const []});

  final String version;
  final List<IdeChangelogItem> items;

  static IdeChangelog parse(Object? data) {
    if (data is! Map) return const IdeChangelog();
    final items = data['items'];
    return IdeChangelog(
      version: _s(data['version']),
      items: [
        if (items is List)
          for (final e in items.take(50))
            if (e is Map && _s(e['version']).isNotEmpty)
              IdeChangelogItem(
                version: _s(e['version']),
                date: _s(e['date']),
                title: _s(e['title']),
                body: _s(e['body']),
              ),
      ],
    );
  }
}

/// Khoá máy `loi` do `vpsttt-kientruc kiem` in ra (KHÔNG phải chữ hiện lên màn
/// hình); viết bằng mã `\u` để luật "chữ giao diện phải có dấu" không bắt nhầm.
const _kientrucErrorKey = 'l\u006fi';
