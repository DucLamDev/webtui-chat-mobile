/// Mô hình Giám sát (`monitor.*`, Phụ lục C1). Số liệu sai (NaN, vô cực, âm,
/// quá lớn) thành `null`, hiện "—".
library;

import 'ide_tools_models.dart';

final class IdeMonAlert {
  const IdeMonAlert({
    required this.level,
    required this.code,
    this.args = const [],
  });

  /// `warn` | `bad`.
  final String level;
  final String code;
  final List<String> args;

  static List<IdeMonAlert> parseList(Object? v) => [
    for (final a in toolMaps(v, max: 30))
      if (toolStr(a['code']).isNotEmpty)
        IdeMonAlert(
          level: a['level'] == 'bad' ? 'bad' : 'warn',
          code: toolStr(a['code'], max: 20),
          args: a['args'] is List
              ? [
                  for (final x in (a['args'] as List).take(4))
                    if (x is num)
                      (x.isFinite ? '${(x * 10).round() / 10}' : '—')
                    else
                      toolStr(x, max: 80),
                ]
              : const [],
        ),
  ];
}

final class IdeMonItem {
  const IdeMonItem({
    required this.key,
    required this.kind,
    required this.name,
    this.label = '',
    this.ok,
    this.error = '',
    this.cpu,
    this.mem,
    this.disk,
    this.load,
    this.ncpu,
    this.uptime,
    this.alerts = const [],
  });

  final String key;
  final String kind;
  final String name;
  final String label;
  final bool? ok;
  final String error;
  final double? cpu;
  final double? mem;
  final double? disk;
  final double? load;
  final int? ncpu;
  final double? uptime;
  final List<IdeMonAlert> alerts;

  String get title => label.isNotEmpty ? label : name;

  static List<IdeMonItem> parseList(Object? data) {
    final out = <IdeMonItem>[];
    for (final it in toolMaps(toolMap(data)['items'], max: 100)) {
      final key = toolStr(it['key'], max: 40);
      if (!RegExp(r'^(sys|my):[a-z0-9][a-z0-9-]{0,30}$').hasMatch(key)) {
        continue;
      }
      final st = toolMap(it['state']);
      final s = toolMap(st['summary']);
      out.add(
        IdeMonItem(
          key: key,
          kind: key.startsWith('my:') ? 'my' : 'sys',
          name: toolStr(it['name'], max: 80),
          label: toolStr(it['label'], max: 120),
          ok: st['ok'] is bool ? st['ok'] as bool : null,
          error: toolStr(st['error'], max: 200),
          cpu: toolPct(s['cpu']),
          mem: toolPct(s['mem']),
          disk: toolPct(s['disk']),
          load: toolNum(s['load'], max: 1e6),
          ncpu: s['ncpu'] == null ? null : toolInt(s['ncpu']),
          uptime: toolNum(s['uptime']),
          alerts: IdeMonAlert.parseList(s['alert_list']),
        ),
      );
    }
    return out;
  }
}

final class IdeMonProc {
  const IdeMonProc({
    this.pid,
    this.user = '',
    this.cpu,
    this.mem,
    this.name = '',
    this.cmd = '',
  });

  final int? pid;
  final String user;
  final double? cpu;
  final double? mem;
  final String name;
  final String cmd;

  static List<IdeMonProc> parseList(Object? v) => [
    for (final p in toolMaps(v, max: 10))
      IdeMonProc(
        pid: p['pid'] == null ? null : toolInt(p['pid']),
        user: toolStr(p['user'], max: 40),
        cpu: toolNum(p['cpu'], max: 1e6),
        mem: toolNum(p['mem']),
        name: toolStr(p['name'], max: 80),
        cmd: toolStr(p['cmd'], max: 300),
      ),
  ];
}

final class IdeMonMem {
  const IdeMonMem({this.total, this.used, this.swapTotal, this.swapUsed});

  final double? total;
  final double? used;
  final double? swapTotal;
  final double? swapUsed;

  /// Phần trăm dùng; thiếu / tổng 0 → `null`.
  double? get pct => _ratio(used, total);
  double? get swapPct => _ratio(swapUsed, swapTotal);

  static double? _ratio(double? a, double? b) =>
      a == null || b == null || b <= 0
      ? null
      : (a / b * 100).clamp(0, 100).toDouble();

  factory IdeMonMem.parse(Object? raw) {
    final m = toolMap(raw);
    return IdeMonMem(
      total: toolNum(m['total']),
      used: toolNum(m['used']),
      swapTotal: toolNum(m['swap_total']),
      swapUsed: toolNum(m['swap_used']),
    );
  }
}

final class IdeMonDisk {
  const IdeMonDisk({this.mount = '', this.size, this.used, this.pct});

  final String mount;
  final double? size;
  final double? used;
  final double? pct;
}

final class IdeMonUnit {
  const IdeMonUnit({required this.unit, this.active = '', this.sub = ''});

  final String unit;
  final String active;
  final String sub;
}

final class IdeMonInfo {
  const IdeMonInfo({
    this.os = '',
    this.kernel = '',
    this.cpuModel = '',
    this.ncpu,
    this.mem = const IdeMonMem(),
    this.load5,
    this.uptime,
    this.disks = const [],
    this.failed = const [],
    this.alerts = const [],
    this.topCpu = const [],
    this.topMem = const [],
  });

  final String os;
  final String kernel;
  final String cpuModel;
  final int? ncpu;
  final IdeMonMem mem;
  final double? load5;
  final double? uptime;
  final List<IdeMonDisk> disks;
  final List<String> failed;
  final List<IdeMonAlert> alerts;
  final List<IdeMonProc> topCpu;
  final List<IdeMonProc> topMem;

  factory IdeMonInfo.parse(Object? data) {
    final m = toolMap(data);
    final load = toolMap(m['load']);
    return IdeMonInfo(
      os: toolStr(m['os'], max: 100),
      kernel: toolStr(m['kernel'], max: 80),
      cpuModel: toolStr(m['cpu_model'], max: 120),
      ncpu: m['ncpu'] == null ? null : toolInt(m['ncpu']),
      mem: IdeMonMem.parse(m['mem']),
      load5: toolNum(load['l5'], max: 1e6),
      uptime: toolNum(m['uptime']),
      disks: [
        for (final d in toolMaps(m['disks'], max: 30))
          IdeMonDisk(
            mount: toolStr(d['mount'], max: 100),
            size: toolNum(d['size']),
            used: toolNum(d['used']),
            pct: toolPct(d['pct']),
          ),
      ],
      failed: toolStrings(m['failed'], max: 20, len: 100),
      alerts: IdeMonAlert.parseList(m['alerts']),
      topCpu: IdeMonProc.parseList(m['top_cpu']),
      topMem: IdeMonProc.parseList(m['top_mem']),
    );
  }
}

final class IdeMonLive {
  const IdeMonLive({
    this.cpu,
    this.mem = const IdeMonMem(),
    this.load1,
    this.rx,
    this.tx,
    this.read,
    this.write,
    this.procs,
    this.topCpu = const [],
    this.topMem = const [],
  });

  final double? cpu;
  final IdeMonMem mem;
  final double? load1;
  final double? rx;
  final double? tx;
  final double? read;
  final double? write;
  final int? procs;
  final List<IdeMonProc> topCpu;
  final List<IdeMonProc> topMem;

  factory IdeMonLive.parse(Object? data) {
    final m = toolMap(data);
    final net = toolMap(m['net']);
    final disk = toolMap(m['disk']);
    return IdeMonLive(
      cpu: toolPct(toolMap(m['cpu'])['total']),
      mem: IdeMonMem.parse(m['mem']),
      load1: toolNum(toolMap(m['load'])['l1'], max: 1e6),
      rx: toolNum(net['rx']),
      tx: toolNum(net['tx']),
      read: toolNum(disk['read']),
      write: toolNum(disk['write']),
      procs: m['procs'] == null ? null : toolInt(m['procs']),
      topCpu: IdeMonProc.parseList(m['top_cpu']),
      topMem: IdeMonProc.parseList(m['top_mem']),
    );
  }
}

final class IdeMonPoint {
  const IdeMonPoint({this.t, this.cpu, this.mem, this.load, this.rx, this.tx});

  final DateTime? t;
  final double? cpu;
  final double? mem;
  final double? load;
  final double? rx;
  final double? tx;
}

final class IdeMonHistory {
  const IdeMonHistory({this.range = '24h', this.points = const []});

  final String range;
  final List<IdeMonPoint> points;

  /// Tối đa điểm giữ lại cho biểu đồ.
  static const maxPoints = 300;

  factory IdeMonHistory.parse(Object? data) {
    final m = toolMap(data);
    final raw = toolMaps(m['points'], max: 20000);
    // Thưa bớt để biểu đồ nhẹ (giữ điểm đầu, cách đều).
    final step = (raw.length / maxPoints).ceil().clamp(1, 1000);
    final pts = <IdeMonPoint>[];
    for (var i = 0; i < raw.length; i += step) {
      final p = raw[i];
      final mt = toolNum(p['mt']);
      final mem = toolNum(p['mem']);
      pts.add(
        IdeMonPoint(
          t: toolTime(p['t']),
          cpu: toolPct(p['cpu']),
          mem: mem == null || mt == null || mt <= 0
              ? null
              : (mem / mt * 100).clamp(0, 100).toDouble(),
          load: toolNum(p['l1'], max: 1e6),
          rx: toolNum(p['rx']),
          tx: toolNum(p['tx']),
        ),
      );
    }
    return IdeMonHistory(
      range: toolStr(m['range'], max: 6, fallback: '24h'),
      points: pts,
    );
  }
}
