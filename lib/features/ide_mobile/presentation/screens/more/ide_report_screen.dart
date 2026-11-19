import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_insight_models.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_project.dart';
import '../../controllers/ide_more_controllers.dart';
import '../../widgets/markdown/ide_markdown.dart';
import 'ide_more_common.dart';

/// Báo cáo dự án (`report.self` chạy như job): số liệu chính + nhận xét AI.
class IdeReportScreen extends StatelessWidget {
  const IdeReportScreen({
    this.project,
    this.pollInterval = const Duration(seconds: 2),
    super.key,
  });

  final String? project;
  final Duration pollInterval;

  @override
  Widget build(BuildContext context) {
    return IdeMorePage(
      title: tr('Báo cáo', 'Report'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) =>
            _ReportBody(project: p, pollInterval: pollInterval),
      ),
    );
  }
}

class _ReportBody extends ConsumerStatefulWidget {
  const _ReportBody({required this.project, required this.pollInterval});

  final IdeProject project;
  final Duration pollInterval;

  @override
  ConsumerState<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends ConsumerState<_ReportBody> {
  bool _ai = false;
  bool _running = false;
  Object? _error;
  String _log = '';
  IdeReport? _report;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = null;
      _report = null;
      _log = '';
    });
    try {
      final job = await ref
          .read(ideMoreServiceProvider)
          .startReport(widget.project.name, ai: _ai && widget.project.my);
      if (!mounted) return;
      _poll(job, 0);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = e;
        });
      }
    }
  }

  void _poll(String job, int from) {
    _timer?.cancel();
    _timer = Timer(widget.pollInterval, () async {
      try {
        final tail = await ref.read(ideMoreServiceProvider).jobTail(job, from);
        if (!mounted) return;
        setState(() => _log += tail.text);
        if (!tail.done) {
          _poll(job, tail.next);
          return;
        }
        final report = IdeReport.parse(tail.result);
        setState(() {
          _running = false;
          _report = report;
          if (report == null) {
            _error = StateError(
              _log.trim().isEmpty
                  ? tr('Báo cáo không có kết quả.', 'The report has no result.')
                  : _log.trim(),
            );
          }
        });
      } on Object catch (e) {
        if (mounted) {
          setState(() {
            _running = false;
            _error = e;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final r = _report;
    return ListView(
      key: const Key('ide_report_list'),
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        if (p.my)
          SwitchListTile(
            key: const Key('ide_report_ai'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Nhờ AI nhận xét', 'Ask the AI for a review')),
            subtitle: Text(
              tr('Mất thêm vài phút.', 'Takes a few more minutes.'),
            ),
            value: _ai,
            onChanged: _running ? null : (v) => setState(() => _ai = v),
          ),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const Key('ide_report_run'),
            onPressed: _running ? null : _start,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.assessment_outlined),
            label: Text(
              _running
                  ? tr('Đang tạo báo cáo...', 'Building report...')
                  : (r == null
                        ? tr('Tạo báo cáo', 'Build report')
                        : tr('Tạo lại', 'Rebuild')),
            ),
          ),
        ),
        const SizedBox(height: WebTuiSpacing.md),
        if (_error != null)
          SizedBox(
            height: 260,
            child: IdeMoreErrorView(error: _error!, onRetry: _start),
          )
        else if (r == null && !_running)
          SizedBox(
            height: 260,
            child: WebTuiEmptyState(
              title: tr('Chưa có báo cáo', 'No report yet'),
              message: tr(
                'Bấm "Tạo báo cáo" để IDE tổng hợp số liệu dự án.',
                'Tap "Build report" to have the IDE summarise the project.',
              ),
              icon: Icons.assessment_outlined,
            ),
          )
        else if (r != null)
          ..._result(r),
      ],
    );
  }

  List<Widget> _result(IdeReport r) {
    final head = WebTuiTypography.titleMedium.copyWith(
      color: WebTuiColors.textPrimary,
    );
    return [
      if (r.generatedAt != null)
        Text(
          '${tr('Lập lúc', 'Generated')} ${ideFormatDateTime(r.generatedAt!)}',
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textMuted,
          ),
        ),
      const SizedBox(height: WebTuiSpacing.sm),
      if (r.facts.isNotEmpty) ...[
        Text(tr('Số liệu chính', 'Key figures'), style: head),
        const SizedBox(height: WebTuiSpacing.sm),
        IdeCard(
          key: const Key('ide_report_facts'),
          child: Column(
            children: [
              for (final f in r.facts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          f.label,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            color: WebTuiColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: WebTuiSpacing.sm),
                      Flexible(
                        child: Text(
                          f.value,
                          textAlign: TextAlign.end,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            color: WebTuiColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      if (r.alerts.isNotEmpty) ...[
        const SizedBox(height: WebTuiSpacing.lg),
        Text(tr('Cảnh báo', 'Alerts'), style: head),
        const SizedBox(height: WebTuiSpacing.sm),
        for (final a in r.alerts)
          Padding(
            padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
            child: IdeCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: WebTuiColors.accentAmber,
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Expanded(child: Text(a)),
                ],
              ),
            ),
          ),
      ],
      if (r.hasAi) ...[
        const SizedBox(height: WebTuiSpacing.lg),
        Text(tr('Nhận xét của AI', 'AI review'), style: head),
        const SizedBox(height: WebTuiSpacing.sm),
        IdeCard(
          key: const Key('ide_report_ai_text'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.aiText.trim().isNotEmpty) IdeMarkdown(text: r.aiText),
              for (final t in r.aiTips)
                Padding(
                  padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                  child: Text('• $t'),
                ),
            ],
          ),
        ),
      ],
      if (r.facts.isEmpty && r.alerts.isEmpty && !r.hasAi)
        WebTuiEmptyState(
          title: tr('Báo cáo trống', 'Empty report'),
          message: tr(
            'IDE chưa có số liệu cho dự án này.',
            'The IDE has no figures for this project yet.',
          ),
          icon: Icons.assessment_outlined,
        ),
    ];
  }
}
