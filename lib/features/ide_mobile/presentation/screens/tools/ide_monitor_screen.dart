import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_monitor_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/ide_wb.dart';
import '../../widgets/markdown/ide_blocks_model.dart';
import '../../widgets/markdown/ide_chart_view.dart';
import '../more/ide_more_common.dart';
import 'ide_tools_common.dart';

/// Giám sát máy chủ của dự án đang mở (Phụ lục C1): số liệu trực tiếp 5 giây,
/// thông tin ≥ 60 giây, biểu đồ 1h / 24h / 7d.
class IdeMonitorScreen extends StatelessWidget {
  const IdeMonitorScreen({
    this.project,
    this.liveInterval = const Duration(seconds: 5),
    this.slowInterval = const Duration(seconds: 15),
    this.infoInterval = const Duration(seconds: 60),
    super.key,
  });

  final String? project;
  final Duration liveInterval;
  final Duration slowInterval;
  final Duration infoInterval;

  @override
  Widget build(BuildContext context) {
    return IdeMorePage(
      title: tr('Giám sát', 'Monitoring'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) => _MonitorList(
          project: p.name,
          live: liveInterval,
          slow: slowInterval,
          info: infoInterval,
        ),
      ),
    );
  }
}

class _MonitorList extends ConsumerStatefulWidget {
  const _MonitorList({
    required this.project,
    required this.live,
    required this.slow,
    required this.info,
  });

  final String project;
  final Duration live;
  final Duration slow;
  final Duration info;

  @override
  ConsumerState<_MonitorList> createState() => _MonitorListState();
}

class _MonitorListState extends ConsumerState<_MonitorList> {
  String? _key;

  @override
  Widget build(BuildContext context) {
    if (!ideToolsHas(ref, 'monitor.list')) return ideToolsUnsupported();
    return IdeLoader<List<IdeMonItem>>(
      load: () => ref.read(ideToolsServiceProvider).monitorList(widget.project),
      builder: (context, items, reload) {
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 320,
                  child: WebTuiEmptyState(
                    title: tr(
                      'Chưa có máy chủ để giám sát',
                      'No servers to monitor',
                    ),
                    message: tr(
                      'Dự án này chưa gắn với máy chủ bạn phụ trách.',
                      'This project is not tied to a server you manage.',
                    ),
                    icon: Icons.monitor_heart_outlined,
                  ),
                ),
              ],
            ),
          );
        }
        final cur = items.firstWhere(
          (i) => i.key == _key,
          orElse: () => items.first,
        );
        return Column(
          children: [
            if (items.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
                child: WebTuiFilterChipBar(
                  chips: [
                    for (final i in items)
                      WebTuiFilterChipData(
                        label: ideVisibleText(i.title),
                        key: Key('ide_mon_pick_${i.key}'),
                      ),
                  ],
                  selectedIndex: items.indexOf(cur),
                  onSelected: (n) => setState(() => _key = items[n].key),
                ),
              ),
            Expanded(
              child: _MachineView(
                key: ValueKey('${widget.project}/${cur.key}'),
                project: widget.project,
                item: cur,
                liveInterval: widget.live,
                slowInterval: widget.slow,
                infoInterval: widget.info,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Lỗi dừng hẳn việc hỏi tự động (hết quyền, máy bị tắt giám sát…).
bool _terminal(Object e) =>
    e is IdeForbidden ||
    e is IdeNotFound ||
    e is IdeConflict ||
    e is IdeUnsupported ||
    e is IdeBadRequest;

class _MachineView extends ConsumerStatefulWidget {
  const _MachineView({
    required this.project,
    required this.item,
    required this.liveInterval,
    required this.slowInterval,
    required this.infoInterval,
    super.key,
  });

  final String project;
  final IdeMonItem item;
  final Duration liveInterval;
  final Duration slowInterval;
  final Duration infoInterval;

  @override
  ConsumerState<_MachineView> createState() => _MachineViewState();
}

class _MachineViewState extends ConsumerState<_MachineView> {
  static const _bufMax = 60;
  static const _ranges = ['1h', '24h', '7d'];

  Timer? _liveTimer;
  Timer? _infoTimer;
  AppLifecycleListener? _life;
  IdeMonLive? _live;
  IdeMonInfo? _info;
  IdeMonHistory? _hist;
  Object? _liveErr;
  Object? _infoErr;
  Object? _histErr;
  bool _stopped = false;
  bool _liveBusy = false;
  bool _infoBusy = false;
  int _fails = 0;
  int _histSeq = 0;
  String _range = '1h';
  int _metric = 0;
  final _buf = <double?>[];

  String get _key => widget.item.key;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onStateChange: (st) {
        if (st == AppLifecycleState.resumed && _active) {
          unawaited(_pollLive());
        }
      },
    );
    unawaited(_pollLive());
    unawaited(_pollInfo());
    unawaited(_loadHist());
    _infoTimer = Timer.periodic(widget.infoInterval, (_) {
      if (_active) {
        unawaited(_pollInfo());
        unawaited(_loadHist(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _infoTimer?.cancel();
    _life?.dispose();
    super.dispose();
  }

  /// Không hỏi máy khi app ở nền hoặc màn bị che.
  bool get _active {
    if (!mounted || _stopped) return false;
    final st = WidgetsBinding.instance.lifecycleState;
    if (st != null && st != AppLifecycleState.resumed) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  void _scheduleLive() {
    _liveTimer?.cancel();
    if (!mounted || _stopped) return;
    final wait = _fails >= 3 ? widget.slowInterval : widget.liveInterval;
    _liveTimer = Timer(wait, () {
      if (_active) {
        unawaited(_pollLive());
      } else {
        _scheduleLive();
      }
    });
  }

  Future<void> _pollLive() async {
    if (_liveBusy || !mounted || _stopped) return;
    _liveBusy = true;
    try {
      final live = await ref
          .read(ideToolsServiceProvider)
          .monitorLive(widget.project, _key);
      if (!mounted) return;
      setState(() {
        _live = live;
        _liveErr = null;
        _fails = 0;
        _buf.add(live.cpu);
        if (_buf.length > _bufMax) _buf.removeAt(0);
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _liveErr = e;
        _fails++;
        if (_terminal(e)) _stopped = true;
      });
    } finally {
      _liveBusy = false;
      _scheduleLive();
    }
  }

  Future<void> _pollInfo() async {
    if (_infoBusy || !mounted || _stopped) return;
    _infoBusy = true;
    try {
      final info = await ref
          .read(ideToolsServiceProvider)
          .monitorInfo(widget.project, _key);
      if (!mounted) return;
      setState(() {
        _info = info;
        _infoErr = null;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _infoErr = e;
          if (_terminal(e)) _stopped = true;
        });
      }
    } finally {
      _infoBusy = false;
    }
  }

  Future<void> _loadHist({bool silent = false}) async {
    if (!ideToolsHasNow(ref, 'monitor.history')) return;
    final seq = ++_histSeq;
    final range = _range;
    if (!silent) setState(() => _histErr = null);
    try {
      final h = await ref
          .read(ideToolsServiceProvider)
          .monitorHistory(widget.project, _key, range);
      if (!mounted || seq != _histSeq) return;
      setState(() {
        _hist = h;
        _histErr = null;
      });
    } on Object catch (e) {
      if (mounted && seq == _histSeq) setState(() => _histErr = e);
    }
  }

  void _retry() {
    setState(() {
      _stopped = false;
      _fails = 0;
      _liveErr = null;
      _infoErr = null;
    });
    unawaited(_pollLive());
    unawaited(_pollInfo());
    unawaited(_loadHist());
  }

  String _alertText(IdeMonAlert a) {
    String arg(int i) =>
        i < a.args.length ? ideVisibleText(a.args[i]) : ideToolsDash;
    return switch (a.code) {
      'disk' => tr(
        'Ổ ${arg(0)} đầy ${arg(1)}%',
        'Disk ${arg(0)} ${arg(1)}% full',
      ),
      'inode' => tr(
        'Inode ổ ${arg(0)} ${arg(1)}%',
        'Inodes on ${arg(0)} ${arg(1)}%',
      ),
      'mem' => tr('RAM dùng ${arg(0)}%', 'Memory ${arg(0)}% used'),
      'swap' => tr('Swap dùng ${arg(0)}%', 'Swap ${arg(0)}% used'),
      'load' => tr(
        'Tải cao ${arg(0)} (${arg(1)} nhân)',
        'High load ${arg(0)} (${arg(1)} cores)',
      ),
      'unit' => tr('Dịch vụ lỗi: ${arg(0)}', 'Service failed: ${arg(0)}'),
      _ => ideVisibleText(a.code),
    };
  }

  IdeChartSpec? _chart() {
    final pts = _hist?.points ?? const <IdeMonPoint>[];
    if (pts.length < 2) return null;
    final long = _range != '1h';
    String label(IdeMonPoint p) {
      final t = p.t;
      if (t == null) return '';
      final hm =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      return long
          ? '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} $hm'
          : hm;
    }

    List<double?> vals(double? Function(IdeMonPoint) f) => [
      for (final p in pts) f(p),
    ];
    final labels = [for (final p in pts) label(p)];
    final (title, unit, series) = switch (_metric) {
      0 => ('CPU', '%', [IdeChartSeries('CPU', vals((p) => p.cpu))]),
      1 => (
        tr('RAM', 'Memory'),
        '%',
        [IdeChartSeries('RAM', vals((p) => p.mem))],
      ),
      2 => (
        tr('Tải hệ thống', 'Load'),
        '',
        [IdeChartSeries(tr('Tải 1 phút', 'Load 1m'), vals((p) => p.load))],
      ),
      _ => (
        tr('Mạng', 'Network'),
        'KB/s',
        [
          IdeChartSeries(
            tr('Nhận', 'Down'),
            vals((p) => p.rx == null ? null : p.rx! / 1024),
          ),
          IdeChartSeries(
            tr('Gửi', 'Up'),
            vals((p) => p.tx == null ? null : p.tx! / 1024),
          ),
        ],
      ),
    };
    if (series.every((s) => s.values.every((v) => v == null))) return null;
    return IdeChartSpec(
      type: IdeChartType.line,
      labels: labels,
      series: series,
      title: title,
      unit: unit,
    );
  }

  Widget _bar(String label, double? pct, {String? detail}) {
    final v = pct == null ? 0.0 : (pct / 100).clamp(0.0, 1.0);
    final color = pct == null
        ? IdeWb.text2
        : pct >= 90
        ? IdeWb.danger
        : pct >= 75
        ? IdeWb.warn
        : IdeWb.ok;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: IdeType.bodySmall.copyWith(color: IdeWb.text),
                ),
              ),
              Text(
                detail ?? ideToolsPct(pct),
                style: IdeType.bodySmall.copyWith(color: IdeWb.textStrong),
              ),
            ],
          ),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: v,
            minHeight: 6,
            color: color,
            backgroundColor: IdeWb.border,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }

  Widget _procs(String title, List<IdeMonProc> list, {required bool byMem}) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ToolSectionTitle(title),
        for (final p in list.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ideVisibleText(p.name.isEmpty ? '${p.pid ?? ''}' : p.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IdeType.bodySmall.copyWith(color: IdeWb.textStrong),
                  ),
                ),
                Text(
                  byMem ? ideToolsBytes(p.mem) : '${ideToolsNum(p.cpu)}%',
                  style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final live = _live;
    final info = _info;
    final alerts = info?.alerts.isNotEmpty == true ? info!.alerts : item.alerts;
    if (live == null && info == null && _liveErr != null && _infoErr != null) {
      return IdeMoreErrorView(error: _liveErr!, onRetry: _retry);
    }
    final chart = _chart();
    final liveSpec = _buf.where((v) => v != null).length >= 2
        ? IdeChartSpec(
            type: IdeChartType.line,
            labels: [for (var i = 0; i < _buf.length; i++) ''],
            series: [IdeChartSeries('CPU', List<double?>.of(_buf))],
            title: tr('CPU trực tiếp', 'Live CPU'),
            unit: '%',
          )
        : null;
    return RefreshIndicator(
      onRefresh: () async => _retry(),
      child: ListView(
        key: const Key('ide_monitor_view'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.xs,
          WebTuiSpacing.lg,
          WebTuiSpacing.xxl,
        ),
        children: [
          IdeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: WebTuiSpacing.sm,
                  runSpacing: WebTuiSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      ideVisibleText(item.title),
                      style: IdeType.titleMedium.copyWith(
                        color: IdeWb.textStrong,
                      ),
                    ),
                    IdeTag(
                      item.kind == 'my'
                          ? tr('VPS riêng', 'Own VPS')
                          : tr('Hệ thống', 'System'),
                    ),
                    if (item.ok == false)
                      IdeTag(
                        tr('Mất kết nối', 'Unreachable'),
                        color: IdeWb.danger,
                      ),
                  ],
                ),
                if (_liveErr != null)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ideMoreErrorText(_liveErr!),
                            key: const Key('ide_monitor_live_error'),
                            style: IdeType.bodySmall.copyWith(
                              color: IdeWb.danger,
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(44, 44),
                          ),
                          onPressed: _retry,
                          child: Text(tr('Thử lại', 'Retry')),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: WebTuiSpacing.xs),
                if (live == null && _liveErr == null)
                  Text(tr('Đang đọc số liệu...', 'Reading metrics...'))
                else if (live != null) ...[
                  _bar('CPU', live.cpu),
                  _bar(
                    'RAM',
                    live.mem.pct,
                    detail:
                        '${ideToolsPct(live.mem.pct)} (${ideToolsBytes(live.mem.used)} / ${ideToolsBytes(live.mem.total)})',
                  ),
                  if (live.mem.swapTotal != null && live.mem.swapTotal! > 0)
                    _bar('Swap', live.mem.swapPct),
                  ToolInfoRow(
                    tr('Tải 1 phút', 'Load 1m'),
                    ideToolsNum(live.load1),
                  ),
                  ToolInfoRow(
                    tr('Mạng', 'Network'),
                    '↓ ${ideToolsBytes(live.rx)}/s  ↑ ${ideToolsBytes(live.tx)}/s',
                  ),
                  ToolInfoRow(
                    tr('Đĩa', 'Disk'),
                    '${tr('đọc', 'read')} ${ideToolsBytes(live.read)}/s  ${tr('ghi', 'write')} ${ideToolsBytes(live.write)}/s',
                  ),
                  ToolInfoRow(
                    tr('Tiến trình', 'Processes'),
                    live.procs?.toString() ?? ideToolsDash,
                  ),
                ],
              ],
            ),
          ),
          if (alerts.isNotEmpty) ...[
            ToolSectionTitle(tr('Cảnh báo', 'Alerts')),
            for (final a in alerts)
              Padding(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
                child: IdeCard(
                  key: Key('ide_monitor_alert_${a.code}'),
                  child: Text(
                    _alertText(a),
                    style: IdeType.bodyMedium.copyWith(
                      color: a.level == 'bad' ? IdeWb.danger : IdeWb.warn,
                    ),
                  ),
                ),
              ),
          ],
          if (liveSpec != null) ...[
            const SizedBox(height: WebTuiSpacing.md),
            IdeChartView(spec: liveSpec),
          ],
          ToolSectionTitle(tr('Lịch sử', 'History')),
          Wrap(
            spacing: WebTuiSpacing.sm,
            runSpacing: WebTuiSpacing.xs,
            children: [
              for (final r in _ranges)
                ChoiceChip(
                  key: Key('ide_monitor_range_$r'),
                  label: Text(r),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  selected: _range == r,
                  onSelected: (_) {
                    if (_range == r) return;
                    setState(() {
                      _range = r;
                      _hist = null;
                    });
                    unawaited(_loadHist());
                  },
                ),
            ],
          ),
          // Khoảng thời gian một hàng, chỉ số một hàng (không lẫn vào nhau).
          Wrap(
            spacing: WebTuiSpacing.sm,
            runSpacing: WebTuiSpacing.xs,
            children: [
              for (final (i, n) in [
                (0, 'CPU'),
                (1, 'RAM'),
                (2, tr('Tải', 'Load')),
                (3, tr('Mạng', 'Network')),
              ])
                ChoiceChip(
                  key: Key('ide_monitor_metric_$i'),
                  label: Text(n),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  selected: _metric == i,
                  onSelected: (_) => setState(() => _metric = i),
                ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          if (_histErr != null)
            IdeCard(
              child: Text(
                ideMoreErrorText(_histErr!),
                style: IdeType.bodySmall.copyWith(color: IdeWb.danger),
              ),
            )
          else if (_hist == null)
            Text(tr('Đang tải lịch sử...', 'Loading history...'))
          else if (chart == null)
            Text(
              tr('Chưa có số liệu trong khoảng này.', 'No data in this range.'),
              key: const Key('ide_monitor_no_chart'),
            )
          else
            IdeChartView(key: const Key('ide_monitor_chart'), spec: chart),
          if (info != null) ...[
            ToolSectionTitle(tr('Thông tin máy', 'Machine info')),
            IdeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (info.os.isNotEmpty)
                    ToolInfoRow('OS', ideVisibleText(info.os)),
                  if (info.kernel.isNotEmpty)
                    ToolInfoRow('Kernel', ideVisibleText(info.kernel)),
                  if (info.cpuModel.isNotEmpty)
                    ToolInfoRow(
                      'CPU',
                      '${ideVisibleText(info.cpuModel)} × ${info.ncpu ?? ideToolsDash}',
                    ),
                  ToolInfoRow(
                    tr('Chạy được', 'Uptime'),
                    ideToolsDuration(info.uptime),
                  ),
                  ToolInfoRow(
                    tr('Tải 5 phút', 'Load 5m'),
                    ideToolsNum(info.load5),
                  ),
                  for (final d in info.disks)
                    _bar(
                      ideVisibleText(d.mount),
                      d.pct,
                      detail:
                          '${ideToolsPct(d.pct)} (${ideToolsBytes(d.used)} / ${ideToolsBytes(d.size)})',
                    ),
                  if (info.failed.isNotEmpty)
                    ToolInfoRow(
                      tr('Dịch vụ lỗi', 'Failed units'),
                      info.failed.map(ideVisibleText).join(', '),
                    ),
                ],
              ),
            ),
            _procs(tr('Top CPU', 'Top CPU'), info.topCpu, byMem: false),
            _procs(tr('Top RAM', 'Top memory'), info.topMem, byMem: true),
          ] else if (_infoErr != null)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.md),
              child: Text(ideMoreErrorText(_infoErr!)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: WebTuiSpacing.md),
            child: Text(
              tr(
                'Số liệu cập nhật khi màn đang mở.',
                'Metrics refresh while this screen is open.',
              ),
              style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
            ),
          ),
        ],
      ),
    );
  }
}
