import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../data/ide_connection.dart';
import '../../../domain/ide_deploy.dart';
import '../../../domain/ide_project.dart';
import '../../../domain/ide_project_info.dart';
import '../../controllers/ide_controllers.dart';
import '../../controllers/ide_project_controllers.dart';
import '../../controllers/ide_project_ops_controllers.dart';
import '../../widgets/projects/ide_project_ui.dart';
import 'ide_project_picker.dart';
import 'ide_project_sheets.dart';

/// Tab Dự án của IDE: chọn dự án, thông tin git và các nút theo kiểu dự án.
class IdeProjectsTab extends ConsumerWidget {
  const IdeProjectsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(
      ideLinkStatusProvider.select((v) => v.valueOrNull?.phase),
    );
    if (phase != IdeLinkPhase.ready) {
      return WebTuiEmptyState(
        title: tr('Chưa nối IDE', 'IDE not connected'),
        message: tr(
          'Hãy nối điện thoại với IDE trên máy tính để xem dự án.',
          'Link this phone to the IDE on your computer to see projects.',
        ),
        icon: Icons.link_off_rounded,
      );
    }
    final current = ref.watch(ideCurrentProjectProvider);
    return current.when(
      loading: () => WebTuiLoadingState(
        message: tr('Đang tải dự án...', 'Loading projects...'),
      ),
      error: (e, _) => ideProjectErrorView(
        e,
        title: tr('Không tải được dự án', 'Could not load projects'),
        onRetry: () => ref.invalidate(ideProjectsProvider),
      ),
      data: (project) => project == null
          ? WebTuiEmptyState(
              key: const Key('ide_projects_empty'),
              title: tr('Chưa có dự án nào', 'No projects yet'),
              message: tr(
                'Tài khoản này chưa được giao dự án nào trên IDE.',
                'This account has no project on the IDE yet.',
              ),
              icon: Icons.folder_off_outlined,
            )
          : _ProjectBody(project: project),
    );
  }
}

class _ProjectBody extends ConsumerWidget {
  const _ProjectBody({required this.project});

  final IdeProject project;

  bool _has(WidgetRef ref, String op) =>
      ref.watch(ideLinkStatusProvider).valueOrNull?.ready?.hasOp(op) ?? false;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final all = ref.read(ideProjectsProvider).valueOrNull ?? const [];
    final picked = await showIdeProjectPicker(
      context,
      projects: all,
      currentName: project.name,
    );
    if (picked != null) {
      ref.read(ideSelectedProjectNameProvider.notifier).state = picked.name;
    }
  }

  void _push(BuildContext context, String path, [Map<String, String>? q]) {
    unawaited(context.push(Uri(path: path, queryParameters: q).toString()));
  }

  Future<void> _createPr(BuildContext context) async {
    final job = await showIdeCreatePrSheet(context, project);
    if (job != null && context.mounted) _push(context, '/ide/jobs/$job');
  }

  Future<void> _merge(BuildContext context) async {
    final out = await showIdeMergePrSheet(context, project);
    if (out == null || !context.mounted) return;
    if (!out.ok) {
      ideProjectSnack(
        context,
        out.result.message.isNotEmpty
            ? out.result.message
            : tr('Gộp PR chưa xong, xem chi tiết.', 'Merge not finished.'),
      );
      _push(context, '/ide/jobs/${out.job}');
    } else if (out.result.queued) {
      ideProjectSnack(
        context,
        tr('Đã xếp PR vào hàng chờ', 'PR added to the merge queue'),
      );
      _push(context, '/ide/mergeq', {
        'project': project.name,
        'pr': '${out.number}',
      });
    } else {
      ideProjectSnack(
        context,
        out.result.message.isNotEmpty
            ? out.result.message
            : tr('Đã gộp PR', 'PR merged'),
      );
    }
  }

  Future<void> _toGit(BuildContext context, WidgetRef ref) async {
    final job = await showIdeToGitSheet(context, project);
    if (job != null && context.mounted) _push(context, '/ide/jobs/$job');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(ideProjectOverviewProvider(project));
    final ops = IdeDeployOps.of(project);
    final isCompany = !project.my;
    final canDeploy =
        _has(ref, ops.preview) &&
        project.canDeploy != false &&
        (project.my || project.kind != IdeProjectKind.local);
    final actions = <Widget>[
      if (isCompany && project.isGit && _has(ref, 'pr.create'))
        IdeProjectButton(
          key: const Key('ide_act_pr'),
          icon: Icons.call_split_rounded,
          label: tr('Tạo PR', 'Create PR'),
          onPressed: () => _createPr(context),
        ),
      if (isCompany &&
          project.isGit &&
          project.canMerge != false &&
          _has(ref, 'git.merge'))
        IdeProjectButton(
          key: const Key('ide_act_merge'),
          icon: Icons.call_merge_rounded,
          label: tr('Gộp PR', 'Merge PR'),
          onPressed: () => _merge(context),
        ),
      if (isCompany && project.isGit && _has(ref, 'mergeq.view'))
        IdeProjectButton(
          key: const Key('ide_act_mergeq'),
          icon: Icons.queue_rounded,
          label: tr('Hàng chờ gộp', 'Merge queue'),
          onPressed: () =>
              _push(context, '/ide/mergeq', {'project': project.name}),
        ),
      if (_has(ref, 'mergeq.mine'))
        IdeProjectButton(
          key: const Key('ide_act_mergeq_mine'),
          icon: Icons.person_outline_rounded,
          label: tr('Hàng chờ của tôi', 'My queue'),
          onPressed: () => _push(context, '/ide/mergeq'),
        ),
      if (canDeploy)
        IdeProjectButton(
          key: const Key('ide_act_deploy'),
          primary: true,
          icon: Icons.rocket_launch_outlined,
          label: ops.sync
              ? tr('Đồng bộ lên máy chủ', 'Sync to server')
              : tr('Triển khai', 'Deploy'),
          onPressed: () =>
              _push(context, '/ide/deploy', {'project': project.name}),
        ),
      if (!project.isGit &&
          project.canManage != false &&
          _has(ref, 'to_git.check'))
        IdeProjectButton(
          key: const Key('ide_act_to_git'),
          icon: Icons.merge_type_rounded,
          label: tr('Chuyển sang Git', 'Move to Git'),
          onPressed: () => _toGit(context, ref),
        ),
      if (project.my && _has(ref, 'targets.show'))
        IdeProjectButton(
          key: const Key('ide_act_target'),
          icon: Icons.dns_outlined,
          label: tr('Máy đích', 'Target server'),
          onPressed: () => showIdeMyTargetSheet(context, project),
        ),
      if (isCompany && project.targets.isNotEmpty && _has(ref, 'vps.request'))
        IdeProjectButton(
          key: const Key('ide_act_vps_request'),
          icon: Icons.vpn_key_outlined,
          label: tr('Xin quyền máy chủ', 'Request server access'),
          onPressed: () => showIdeVpsRequestSheet(context, project),
        ),
    ];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(ideProjectOverviewProvider(project));
        await ref
            .read(ideProjectOverviewProvider(project).future)
            .then((_) {}, onError: (_) {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _PickerHeader(project: project, onTap: () => _pick(context, ref)),
          overview.when(
            loading: () => SizedBox(
              height: 160,
              child: WebTuiLoadingState(
                message: tr('Đang tải thông tin...', 'Loading details...'),
              ),
            ),
            error: (e, _) => SizedBox(
              height: 300,
              child: ideProjectErrorView(
                e,
                title: tr('Không tải được thông tin', 'Could not load details'),
                onRetry: () =>
                    ref.invalidate(ideProjectOverviewProvider(project)),
              ),
            ),
            data: (o) => _InfoCard(project: project, overview: o),
          ),
          if (actions.isEmpty)
            IdeProjectCard(
              child: Text(
                tr(
                  'Dự án này chưa có thao tác nào trên điện thoại.',
                  'No actions for this project on the phone yet.',
                ),
                key: const Key('ide_projects_no_actions'),
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WebTuiSpacing.lg,
                vertical: WebTuiSpacing.sm,
              ),
              child: Wrap(
                spacing: WebTuiSpacing.sm,
                runSpacing: WebTuiSpacing.sm,
                children: actions,
              ),
            ),
          ...overview.maybeWhen(
            data: (o) => [
              if (o.status != null && o.status!.files.isNotEmpty)
                _ChangesCard(status: o.status!),
              if (o.log.isNotEmpty) _LogCard(log: o.log),
            ],
            orElse: () => const <Widget>[],
          ),
        ],
      ),
    );
  }
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({required this.project, required this.onTap});

  final IdeProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      child: Material(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        child: InkWell(
          key: const Key('ide_project_picker'),
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WebTuiRadii.md),
              border: Border.all(color: WebTuiColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, color: WebTuiColors.primary),
                const SizedBox(width: WebTuiSpacing.md),
                Expanded(
                  child: Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.titleMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                ),
                WebTuiStatusPill(
                  label: ideProjectGroupLabel(ideProjectGroup(project)),
                ),
                const SizedBox(width: WebTuiSpacing.xs),
                Icon(Icons.unfold_more_rounded, color: WebTuiColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.project, required this.overview});

  final IdeProject project;
  final IdeProjectOverview overview;

  @override
  Widget build(BuildContext context) {
    final i = overview.info;
    final branch = i.branch.isNotEmpty ? i.branch : project.branch;
    final c = i.lastCommit;
    Widget line(IconData icon, String text, [Key? key]) => Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: WebTuiColors.textMuted),
          const SizedBox(width: WebTuiSpacing.sm),
          Expanded(
            child: Text(
              text,
              key: key,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: WebTuiColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    return IdeProjectCard(
      title: tr('Thông tin', 'Details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (branch.isNotEmpty)
            line(
              Icons.call_split_rounded,
              '${tr('Nhánh', 'Branch')} $branch'
              '${i.ahead > 0 ? ' · ${i.ahead} ${tr('commit chưa đẩy lên', 'unpushed commits')}' : ''}'
              '${i.behind > 0 ? ' · ${i.behind} ${tr('commit mới chưa kéo về', 'commits to pull')}' : ''}',
              const Key('ide_info_branch'),
            ),
          line(
            Icons.edit_note_rounded,
            i.dirty == 0
                ? tr('Không có tệp đang sửa', 'No changed files')
                : '${i.dirty} ${tr('tệp đã đổi', 'changed files')}',
            const Key('ide_info_dirty'),
          ),
          if (c != null)
            line(
              Icons.commit_rounded,
              '${c.subject}\n${c.shortSha} · ${c.by} · ${ideFormatUnix(c.at)}',
              const Key('ide_info_commit'),
            ),
        ],
      ),
    );
  }
}

class _ChangesCard extends StatelessWidget {
  const _ChangesCard({required this.status});

  final IdeGitStatus status;

  @override
  Widget build(BuildContext context) {
    const shown = 30;
    final files = status.files.take(shown).toList();
    final more = status.files.length - files.length;
    return IdeProjectCard(
      title: tr('Tệp đã đổi', 'Changed files'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in files)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      f.code,
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      f.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodySmall.copyWith(
                        color: WebTuiColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (more > 0 || status.truncated)
            Text(
              tr('và còn nữa...', 'and more...'),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.log});

  final List<IdeCommit> log;

  @override
  Widget build(BuildContext context) {
    return IdeProjectCard(
      title: tr('Commit gần đây', 'Recent commits'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in log)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${c.shortSha} · ${c.by} · ${ideFormatUnix(c.at)}',
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
