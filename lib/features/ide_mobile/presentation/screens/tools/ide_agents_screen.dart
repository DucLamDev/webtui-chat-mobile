import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_tools_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../more/ide_more_common.dart';
import 'ide_tools_common.dart';

/// Hoạt động của AI Agent trong dự án (chỉ đọc, Phụ lục C1).
class IdeAgentsScreen extends StatelessWidget {
  const IdeAgentsScreen({this.project, super.key});

  final String? project;

  @override
  Widget build(BuildContext context) {
    return IdeMorePage(
      title: tr('AI Agent', 'AI agents'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) => _AgentsBody(project: p.name),
      ),
    );
  }
}

final class _AgentsData {
  const _AgentsData(this.overview, this.scheduled);

  final IdeAgentsOverview overview;
  final List<IdeSchedAgent> scheduled;
}

class _AgentsBody extends ConsumerStatefulWidget {
  const _AgentsBody({required this.project});

  final String project;

  @override
  ConsumerState<_AgentsBody> createState() => _AgentsBodyState();
}

class _AgentsBodyState extends ConsumerState<_AgentsBody> {
  int _days = 7;

  Future<_AgentsData> _load() async {
    final svc = ref.read(ideToolsServiceProvider);
    final hasSession = ideToolsHasNow(ref, 'agents.session');
    final overview = hasSession
        ? await svc.agentsSession(widget.project, _days)
        : const IdeAgentsOverview();
    var sched = const <IdeSchedAgent>[];
    if (ideToolsHasNow(ref, 'agents.status')) {
      try {
        sched = await svc.agentsStatus(widget.project);
      } on Object {
        // Dự án không phải dự án công ty / không có lịch: bỏ phần này.
        if (!hasSession) rethrow;
      }
    }
    return _AgentsData(overview, sched);
  }

  @override
  Widget build(BuildContext context) {
    if (!ideToolsHas(ref, 'agents.session') &&
        !ideToolsHas(ref, 'agents.status')) {
      return ideToolsUnsupported();
    }
    return Column(
      children: [
        if (ideToolsHas(ref, 'agents.session'))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
            child: WebTuiFilterChipBar(
              chips: [
                WebTuiFilterChipData(label: tr('Hôm nay', 'Today')),
                WebTuiFilterChipData(label: tr('7 ngày', '7 days')),
                WebTuiFilterChipData(label: tr('30 ngày', '30 days')),
              ],
              selectedIndex: switch (_days) {
                1 => 0,
                30 => 2,
                _ => 1,
              },
              onSelected: (i) => setState(() => _days = const [1, 7, 30][i]),
            ),
          ),
        Expanded(
          child: IdeLoader<_AgentsData>(
            key: ValueKey('${widget.project}/$_days'),
            load: _load,
            builder: (context, data, reload) =>
                _AgentsView(data: data, reload: reload),
          ),
        ),
      ],
    );
  }
}

class _AgentsView extends StatelessWidget {
  const _AgentsView({required this.data, required this.reload});

  final _AgentsData data;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final o = data.overview;
    final empty = o.isEmpty && data.scheduled.isEmpty;
    return RefreshIndicator(
      onRefresh: reload,
      child: empty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: 320,
                  child: WebTuiEmptyState(
                    title: tr('Chưa có agent', 'No agents'),
                    message: tr(
                      'Dự án này chưa có AI Agent nào chạy.',
                      'This project has no agents or runs yet.',
                    ),
                    icon: Icons.smart_toy_outlined,
                  ),
                ),
              ],
            )
          : ListView(
              key: const Key('ide_agents_list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                WebTuiSpacing.xs,
                WebTuiSpacing.lg,
                WebTuiSpacing.xxl,
              ),
              children: [
                Wrap(
                  spacing: WebTuiSpacing.sm,
                  runSpacing: WebTuiSpacing.sm,
                  children: [
                    ToolStat(tr('Agent', 'Agents'), '${o.totals.agents}'),
                    ToolStat(tr('Lần chạy', 'Runs'), '${o.totals.runs}'),
                    ToolStat(tr('Hôm nay', 'Today'), '${o.totals.today}'),
                    ToolStat(tr('Đang chạy', 'Running'), '${o.totals.running}'),
                    ToolStat(
                      tr('Lỗi', 'Errors'),
                      '${o.totals.errors}',
                      color: o.totals.errors > 0 ? WebTuiColors.danger : null,
                    ),
                  ],
                ),
                if (data.scheduled.isNotEmpty) ...[
                  ToolSectionTitle(tr('Chạy theo lịch', 'Scheduled')),
                  for (final s in data.scheduled) _SchedCard(agent: s),
                ],
                if (o.agents.isNotEmpty) ...[
                  ToolSectionTitle('Agent (${o.agents.length})'),
                  for (final a in o.agents) _AgentCard(agent: a),
                ],
                if (o.commands.isNotEmpty) ...[
                  ToolSectionTitle(
                    '${tr('Lệnh', 'Commands')} (${o.commands.length})',
                  ),
                  for (final c in o.commands) _AgentCard(agent: c),
                ],
                if (o.recent.isNotEmpty) ...[
                  ToolSectionTitle(tr('Lần chạy gần đây', 'Recent runs')),
                  for (final r in o.recent) _RunTile(run: r),
                ],
              ],
            ),
    );
  }
}

String _when(DateTime? t) => t == null ? ideToolsDash : ideFormatDateTime(t);

(String, Color) _health(String h) => switch (h) {
  'ok' => (tr('Tốt', 'OK'), WebTuiColors.accentGreen),
  'warn' => (tr('Cảnh báo', 'Warning'), WebTuiColors.accentAmber),
  'error' => (tr('Lỗi', 'Error'), WebTuiColors.danger),
  'stale' => (tr('Trễ lịch', 'Stale'), WebTuiColors.accentAmber),
  'running' => (tr('Đang chạy', 'Running'), WebTuiColors.primary),
  'skipped' => (tr('Bỏ qua', 'Skipped'), WebTuiColors.textSecondary),
  _ => (tr('Chưa chạy', 'Never ran'), WebTuiColors.textSecondary),
};

class _SchedCard extends StatelessWidget {
  const _SchedCard({required this.agent});

  final IdeSchedAgent agent;

  @override
  Widget build(BuildContext context) {
    final h = _health(agent.health);
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      child: IdeCard(
        key: Key('ide_sched_${agent.name}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  ideVisibleText(agent.name),
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
                IdeTag(h.$1, color: h.$2),
                if (!agent.enabled) IdeTag(tr('Tắt', 'Off')),
              ],
            ),
            if (agent.description.isNotEmpty)
              Text(
                ideVisibleText(agent.description),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            if (agent.schedule.isNotEmpty)
              ToolInfoRow(
                tr('Lịch', 'Schedule'),
                ideVisibleText(agent.schedule),
              ),
            ToolInfoRow(tr('Lần cuối', 'Last run'), _when(agent.lastAt)),
            if (agent.lastSummary.isNotEmpty)
              Text(
                ideVisibleText(agent.lastSummary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
            for (final p in agent.problems)
              Text(
                '! ${ideVisibleText(p)}',
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.danger,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});

  final IdeAgentInfo agent;

  @override
  Widget build(BuildContext context) {
    final a = agent.activity;
    final cmd = agent.kind == 'command';
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      child: IdeCard(
        key: Key('ide_agent_${agent.kind}_${agent.name}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  ideVisibleText(agent.name),
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
                if (agent.scope.isNotEmpty) IdeTag(agent.scope),
                if (agent.model.isNotEmpty) IdeTag(ideVisibleText(agent.model)),
                if (a.running > 0)
                  IdeTag(
                    tr('Đang chạy ${a.running}', 'Running ${a.running}'),
                    color: WebTuiColors.primary,
                  ),
                if (agent.checkErrors > 0)
                  IdeTag(
                    tr(
                      '${agent.checkErrors} lỗi cấu hình',
                      '${agent.checkErrors} config errors',
                    ),
                    color: WebTuiColors.danger,
                  ),
                if (agent.checkWarnings > 0)
                  IdeTag(
                    tr(
                      '${agent.checkWarnings} cảnh báo',
                      '${agent.checkWarnings} warnings',
                    ),
                    color: WebTuiColors.accentAmber,
                  ),
              ],
            ),
            if (agent.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                child: Text(
                  ideVisibleText(agent.description),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: WebTuiSpacing.xs),
            ToolInfoRow(
              tr('Lần chạy', 'Runs'),
              cmd
                  ? '${a.runs}'
                  : '${a.runs} (${tr('hôm nay', 'today')} ${a.today}, ${tr('lỗi', 'errors')} ${a.errors})',
            ),
            if (!cmd && a.tokens != null)
              ToolInfoRow('Tokens', ideToolsNum(a.tokens)),
            if (!cmd && a.cost != null)
              ToolInfoRow(
                tr('Chi phí', 'Cost'),
                '\$${a.cost!.toStringAsFixed(2)}',
              ),
            ToolInfoRow(tr('Lần cuối', 'Last'), _when(a.last)),
          ],
        ),
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});

  final IdeAgentRun run;

  @override
  Widget build(BuildContext context) {
    final bad = run.status == 'error' || run.status == 'failed';
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
      child: IdeCard(
        padding: const EdgeInsets.all(WebTuiSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: WebTuiSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  ideVisibleText(run.agent),
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (run.status.isNotEmpty)
                  IdeTag(
                    ideVisibleText(run.status),
                    color: bad ? WebTuiColors.danger : null,
                  ),
              ],
            ),
            if (run.desc.isNotEmpty)
              Text(
                ideVisibleText(run.desc),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            Text(
              '${_when(run.at)} · ${ideToolsMs(run.ms)} · ${run.tools} ${tr('lệnh', 'tools')}',
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
