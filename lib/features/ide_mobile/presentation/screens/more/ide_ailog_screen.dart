import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_log_models.dart';
import '../../../domain/ide_more_time.dart';
import '../../controllers/ide_more_controllers.dart';
import '../../widgets/ide_wb.dart';
import 'ide_more_common.dart';

/// Nhật ký AI của dự án: phiên AI đã chạy và PR liên quan.
class IdeAiLogScreen extends ConsumerWidget {
  const IdeAiLogScreen({this.project, super.key});

  final String? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(ideMoreServiceProvider);
    return IdeMorePage(
      title: tr('Nhật ký AI', 'AI log'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) => IdeLoader<IdeAiLog>(
          load: () => service.aiLog(p.name),
          builder: (context, log, reload) {
            if (log.isEmpty) {
              return WebTuiEmptyState(
                title: tr('Chưa có nhật ký', 'No log yet'),
                message: tr(
                  'Dự án này chưa có phiên AI nào được ghi lại.',
                  'No AI sessions were recorded for this project.',
                ),
                icon: Icons.history_rounded,
              );
            }
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                key: const Key('ide_ailog_list'),
                padding: const EdgeInsets.all(WebTuiSpacing.lg),
                children: [
                  if (log.sessions.isNotEmpty)
                    _Header(tr('Phiên AI', 'AI sessions')),
                  for (final s in log.sessions) _SessionTile(s),
                  if (log.prs.isNotEmpty) ...[
                    const SizedBox(height: WebTuiSpacing.md),
                    _Header(tr('PR liên quan', 'Related PRs')),
                  ],
                  for (final pr in log.prs) _PrTile(pr),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
    child: Text(
      text,
      style: IdeType.titleMedium.copyWith(color: IdeWb.textStrong),
    ),
  );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile(this.s);
  final IdeAiLogSession s;

  @override
  Widget build(BuildContext context) {
    final muted = IdeType.bodySmall.copyWith(color: IdeWb.text2);
    final files = s.fileCount > 0 ? s.fileCount : s.files.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      child: IdeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.task.isNotEmpty
                        ? s.task
                        : (s.kind.isEmpty
                              ? tr('Phiên AI', 'AI session')
                              : s.kind),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IdeType.bodyMedium.copyWith(
                      color: IdeWb.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IdeTag(
                  s.closed ? tr('Đã đóng', 'Closed') : tr('Đang mở', 'Open'),
                  color: s.closed ? IdeWb.text : IdeWb.ok,
                ),
              ],
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              [
                if (s.by.isNotEmpty) s.by,
                if (s.kind.isNotEmpty && s.task.isNotEmpty) s.kind,
                if (s.branch.isNotEmpty) s.branch,
                if (s.tab.isNotEmpty) s.tab,
                if (files > 0) '$files ${tr('tệp', 'files')}',
                if (s.hidden) tr('ẩn', 'hidden'),
              ].join(' · '),
              style: muted,
            ),
            if (s.start != null)
              Text(
                [
                  ideFormatDateTime(s.start!),
                  if (s.end != null) ideFormatDateTime(s.end!),
                ].join(' → '),
                style: muted,
              ),
          ],
        ),
      ),
    );
  }
}

class _PrTile extends StatelessWidget {
  const _PrTile(this.pr);
  final IdeAiLogPr pr;

  @override
  Widget build(BuildContext context) {
    final muted = IdeType.bodySmall.copyWith(color: IdeWb.text2);
    final merged = pr.mergedAt != null || pr.state == 'merged';
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      child: IdeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${pr.number} ${pr.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IdeType.bodyMedium.copyWith(
                      color: IdeWb.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (pr.state.isNotEmpty)
                  IdeTag(
                    merged ? tr('Đã gộp', 'Merged') : pr.state,
                    color: merged ? IdeWb.ok : IdeWb.text,
                  ),
              ],
            ),
            Text(
              [
                if (pr.person.isNotEmpty)
                  pr.person
                else if (pr.user.isNotEmpty)
                  pr.user,
                if (pr.head.isNotEmpty) pr.head,
                if (pr.fileCount > 0) '${pr.fileCount} ${tr('tệp', 'files')}',
                if (pr.mergedAt != null) ideFormatDateTime(pr.mergedAt!),
              ].join(' · '),
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}
