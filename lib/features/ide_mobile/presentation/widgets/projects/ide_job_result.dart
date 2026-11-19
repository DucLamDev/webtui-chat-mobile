import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_deploy.dart';

/// Kết quả (`result`) của việc nền đã xong: số PR + nút mở, trạng thái gộp,
/// hay thông điệp của triển khai. Không có gì đáng hiện thì không vẽ gì.
class IdeJobResultView extends ConsumerWidget {
  const IdeJobResultView({required this.op, required this.result, super.key});

  final String op;
  final Object? result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = result;
    if (r is! Map) return const SizedBox.shrink();
    final lines = <Widget>[];
    Widget? action;
    if (op == 'pr.create') {
      final pr = IdePrResult.tryParse(r);
      if (pr == null) return const SizedBox.shrink();
      lines.add(
        _line(
          Key('ide_job_pr_number'),
          pr.existed
              ? tr(
                  'PR #${pr.number} đã có sẵn',
                  'PR #${pr.number} already exists',
                )
              : tr('Đã tạo PR #${pr.number}', 'Created PR #${pr.number}'),
          strong: true,
        ),
      );
      for (final w in pr.warnings) {
        lines.add(
          _line(
            const Key('ide_job_pr_warning'),
            w,
            color: WebTuiColors.accentAmber,
          ),
        );
      }
      final url = pr.url;
      if (url != null) {
        action = TextButton.icon(
          key: const Key('ide_job_pr_open'),
          onPressed: () async {
            final ok = await ref.read(externalUrlLauncherProvider).open(url);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    tr('Không mở được liên kết.', 'Could not open the link.'),
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(tr('Mở PR', 'Open PR')),
          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
        );
      }
    } else if (op == 'git.merge') {
      final m = IdeMergeResult.parse(r);
      final text = m.message.isNotEmpty
          ? m.message
          : m.queued
          ? tr('Đã xếp PR vào hàng chờ', 'PR added to the merge queue')
          : m.merged
          ? tr('Đã gộp PR', 'PR merged')
          : '';
      if (text.isEmpty) return const SizedBox.shrink();
      lines.add(
        _line(
          const Key('ide_job_merge'),
          text,
          color: m.queued || m.merged ? WebTuiColors.accentGreen : null,
          strong: true,
        ),
      );
    } else {
      final msg = r['message'];
      if (msg is! String || msg.isEmpty) return const SizedBox.shrink();
      lines.add(
        _line(
          const Key('ide_job_message'),
          msg,
          color: r['ok'] == false ? WebTuiColors.danger : null,
        ),
      );
    }
    return Container(
      key: const Key('ide_job_result'),
      margin: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        0,
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
      ),
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: WebTuiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [...lines, ?action],
      ),
    );
  }

  Widget _line(Key key, String text, {Color? color, bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xxs),
      child: Text(
        text,
        key: key,
        style: WebTuiTypography.bodyMedium.copyWith(
          color: color ?? WebTuiColors.textPrimary,
          fontWeight: strong ? FontWeight.w700 : null,
        ),
      ),
    );
  }
}
