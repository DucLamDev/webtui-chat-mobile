import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_tools_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../more/ide_more_common.dart';
import 'ide_tools_common.dart';

/// Skill của dự án và agent / lệnh mẫu: xem, cài, cập nhật, gỡ (Phụ lục C1).
class IdeSkillsScreen extends StatelessWidget {
  const IdeSkillsScreen({this.project, super.key});

  final String? project;

  @override
  Widget build(BuildContext context) {
    return IdeMorePage(
      title: tr('Skill', 'Skills'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) => _SkillsBody(project: p.name),
      ),
    );
  }
}

class _SkillsBody extends ConsumerStatefulWidget {
  const _SkillsBody({required this.project});

  final String project;

  @override
  ConsumerState<_SkillsBody> createState() => _SkillsBodyState();
}

class _SkillsBodyState extends ConsumerState<_SkillsBody> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final hasSkills = ideToolsHas(ref, 'skills.list');
    final hasAgents = ideToolsHas(ref, 'skills.agent_list');
    if (!hasSkills && !hasAgents) return ideToolsUnsupported();
    final tabs = [
      if (hasSkills) tr('Skill', 'Skills'),
      if (hasAgents) tr('Agent & lệnh', 'Agents & commands'),
    ];
    final agents = !hasSkills || (tabs.length > 1 && _tab == 1);
    return Column(
      children: [
        if (tabs.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.xs,
              WebTuiSpacing.lg,
              WebTuiSpacing.xs,
            ),
            child: WebTuiSegmentedTabs(
              tabs: tabs,
              selectedIndex: _tab.clamp(0, tabs.length - 1),
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
        Expanded(
          child: _CatalogView(
            key: ValueKey('${widget.project}/$agents'),
            project: widget.project,
            agents: agents,
          ),
        ),
      ],
    );
  }
}

class _CatalogView extends ConsumerStatefulWidget {
  const _CatalogView({required this.project, required this.agents, super.key});

  final String project;
  final bool agents;

  @override
  ConsumerState<_CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends ConsumerState<_CatalogView> {
  bool _ensured = false;

  Future<IdeToolCatalog> _load() async {
    final svc = ref.read(ideToolsServiceProvider);
    if (widget.agents) return svc.agentCatalog(widget.project);
    if (!_ensured && ideToolsHasNow(ref, 'skills.ensure')) {
      _ensured = true;
      await svc.ensureSkills(widget.project);
    }
    return svc.skills(widget.project);
  }

  @override
  Widget build(BuildContext context) {
    return IdeLoader<IdeToolCatalog>(
      load: _load,
      builder: (context, catalog, reload) => _CatalogList(
        project: widget.project,
        agents: widget.agents,
        catalog: catalog,
        reload: reload,
      ),
    );
  }
}

class _CatalogList extends ConsumerStatefulWidget {
  const _CatalogList({
    required this.project,
    required this.agents,
    required this.catalog,
    required this.reload,
  });

  final String project;
  final bool agents;
  final IdeToolCatalog catalog;
  final Future<void> Function() reload;

  @override
  ConsumerState<_CatalogList> createState() => _CatalogListState();
}

class _CatalogListState extends ConsumerState<_CatalogList> {
  bool _busy = false;

  String get _pfx => widget.agents ? 'skills.agent_' : 'skills.';

  String _kindText(String kind) => switch (kind) {
    'command' => tr('lệnh', 'command'),
    'agent' => 'agent',
    _ => 'skill',
  };

  Future<void> _act(IdeToolEntry e, String op) async {
    if (_busy) return;
    final destructive = op == 'remove';
    final ok =
        !destructive ||
        await showWebTuiConfirmDialog(
          context,
          title: tr('Gỡ ${_kindText(e.kind)}?', 'Remove ${_kindText(e.kind)}?'),
          message: '${ideVisibleText(e.name)} (${widget.project})',
          confirmLabel: tr('Gỡ', 'Remove'),
          destructive: true,
        );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await _call(e, op, force: false);
    } on IdeConflict catch (c) {
      if (op == 'remove' || !mounted) {
        if (mounted) ideToolsError(context, c);
      } else {
        final over = await showWebTuiConfirmDialog(
          context,
          title: tr('Ghi đè?', 'Overwrite?'),
          message: c.message.isNotEmpty
              ? ideVisibleText(c.message)
              : tr(
                  'Dự án đã có bản khác của ${e.name}.',
                  'The project already has another copy of ${e.name}.',
                ),
          confirmLabel: tr('Ghi đè', 'Overwrite'),
          destructive: true,
        );
        if (over && mounted) {
          try {
            await _call(e, op, force: true);
          } on Object catch (err) {
            if (mounted) ideToolsError(context, err);
          }
        }
      }
    } on Object catch (err) {
      if (mounted) ideToolsError(context, err);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await widget.reload();
  }

  Future<void> _call(IdeToolEntry e, String op, {required bool force}) async {
    final svc = ref.read(ideToolsServiceProvider);
    if (widget.agents) {
      await svc.agentAction(op, widget.project, e.name, e.kind, force: force);
    } else {
      await svc.skillAction(op, widget.project, e.name, force: force);
    }
    if (!mounted) return;
    ideToolsSnack(context, switch (op) {
      'remove' => tr('Đã gỡ', 'Removed'),
      'update' => tr('Đã cập nhật', 'Updated'),
      _ => tr('Đã cài', 'Installed'),
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.catalog;
    final canInstall = c.writable && ideToolsHas(ref, '${_pfx}install');
    final canUpdate = c.writable && ideToolsHas(ref, '${_pfx}update');
    final canRemove = c.writable && ideToolsHas(ref, '${_pfx}remove');
    final empty = c.installed.isEmpty && c.library.isEmpty;
    return RefreshIndicator(
      onRefresh: widget.reload,
      child: ListView(
        key: const Key('ide_tools_catalog'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.sm,
          WebTuiSpacing.lg,
          WebTuiSpacing.xxl,
        ),
        children: [
          if (!c.writable)
            Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
              child: IdeCard(
                child: Text(
                  tr(
                    'Bạn chỉ xem được, không thêm / gỡ ở dự án này.',
                    'View only: you cannot add or remove here.',
                  ),
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
            ),
          if (empty)
            SizedBox(
              height: 300,
              child: WebTuiEmptyState(
                title: widget.agents
                    ? tr('Chưa có agent / lệnh mẫu', 'No agents / commands')
                    : tr('Chưa có skill', 'No skills'),
                message: tr(
                  'Dự án này chưa có mục nào để hiện.',
                  'Nothing to show for this project yet.',
                ),
                icon: Icons.extension_outlined,
              ),
            ),
          if (c.installed.isNotEmpty) ...[
            ToolSectionTitle(
              '${tr('Đã cài', 'Installed')} (${c.installed.length})',
            ),
            for (final e in c.installed)
              _EntryCard(
                entry: e,
                busy: _busy,
                onUpdate: canUpdate && e.canUpdate && e.nameOk
                    ? () => _act(e, 'update')
                    : null,
                onRemove: canRemove && e.nameOk
                    ? () => _act(e, 'remove')
                    : null,
              ),
          ],
          if (c.library.isNotEmpty) ...[
            ToolSectionTitle(
              '${tr('Thư viện', 'Library')} (${c.library.length})',
            ),
            for (final e in c.library)
              _EntryCard(
                entry: e,
                busy: _busy,
                onInstall: canInstall && e.nameOk
                    ? () => _act(e, 'install')
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.busy,
    this.onInstall,
    this.onUpdate,
    this.onRemove,
  });

  final IdeToolEntry entry;
  final bool busy;
  final VoidCallback? onInstall;
  final VoidCallback? onUpdate;
  final VoidCallback? onRemove;

  (String, Color)? get _state => switch (entry.state) {
    'current' => (tr('Mới nhất', 'Up to date'), WebTuiColors.accentGreen),
    'outdated' => (
      tr('Có bản mới', 'Update available'),
      WebTuiColors.accentAmber,
    ),
    'modified' => (tr('Đã sửa', 'Modified'), WebTuiColors.accentAmber),
    'local' => (tr('Riêng dự án', 'Project only'), WebTuiColors.textSecondary),
    'missing-library' => (
      tr('Không còn trong thư viện', 'Not in library'),
      WebTuiColors.danger,
    ),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final intro = entry.intro;
    final st = _state;
    final ver = entry.installedVersion ?? entry.version;
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      child: IdeCard(
        key: Key('ide_tool_${entry.kind}_${entry.name}'),
        onTap: intro == null || intro.isEmpty
            ? null
            : () => _showIntro(context, entry, intro),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  ideVisibleText(entry.name),
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
                if (entry.kind != 'skill')
                  IdeTag(
                    entry.kind == 'command' ? tr('lệnh', 'command') : 'agent',
                  ),
                if (ver != null) IdeTag('v$ver'),
                if (st != null) IdeTag(st.$1, color: st.$2),
              ],
            ),
            if (entry.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                child: Text(
                  ideVisibleText(entry.description),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
            if (onInstall != null || onUpdate != null || onRemove != null)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                child: Wrap(
                  spacing: WebTuiSpacing.sm,
                  runSpacing: WebTuiSpacing.xs,
                  children: [
                    if (onInstall != null)
                      FilledButton(
                        key: Key('ide_tool_install_${entry.name}'),
                        style: ideToolsFilledBtn(),
                        onPressed: busy ? null : onInstall,
                        child: Text(tr('Cài', 'Install')),
                      ),
                    if (onUpdate != null)
                      FilledButton(
                        key: Key('ide_tool_update_${entry.name}'),
                        style: ideToolsFilledBtn(),
                        onPressed: busy ? null : onUpdate,
                        child: Text(tr('Cập nhật', 'Update')),
                      ),
                    if (onRemove != null)
                      OutlinedButton(
                        key: Key('ide_tool_remove_${entry.name}'),
                        style: ideToolsBtn(color: WebTuiColors.danger),
                        onPressed: busy ? null : onRemove,
                        child: Text(tr('Gỡ', 'Remove')),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showIntro(
  BuildContext context,
  IdeToolEntry e,
  IdeSkillIntro intro,
) {
  Widget block(String title, String text) => text.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: WebTuiSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: WebTuiTypography.titleMedium.copyWith(
                  color: WebTuiColors.textPrimary,
                ),
              ),
              Text(
                ideVisibleText(text),
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ],
          ),
        );
  String bullets(List<String> l) =>
      l.map((x) => '• ${ideVisibleText(x)}').join('\n');
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            0,
            WebTuiSpacing.lg,
            WebTuiSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ideVisibleText(intro.title.isEmpty ? e.name : intro.title),
                style: WebTuiTypography.titleLarge.copyWith(
                  color: WebTuiColors.textPrimary,
                ),
              ),
              block(tr('Làm gì', 'What it does'), intro.summary),
              block(tr('Dùng khi', 'Use when'), intro.when),
              block(tr('Không dùng cho', 'Not for'), intro.notFor),
              block(tr('Cách dùng', 'How'), intro.how),
              block(tr('Ví dụ', 'Examples'), bullets(intro.examples)),
              block(tr('Lợi ích', 'Benefits'), bullets(intro.benefits)),
            ],
          ),
        ),
      ),
    ),
  );
}
