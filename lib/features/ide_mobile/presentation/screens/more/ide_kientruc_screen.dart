import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_insight_models.dart';
import '../../../domain/ide_more_time.dart';
import '../../controllers/ide_more_controllers.dart';
import '../../widgets/markdown/ide_blocks_model.dart';
import '../../widgets/markdown/ide_diagram_view.dart';
import 'ide_more_common.dart';

/// Kết quả đọc kiến trúc + kiểm tra (kiểm tra hỏng không chặn việc xem).
final class _ArchData {
  const _ArchData(this.arch, this.check, this.checkError);

  final IdeKientruc arch;
  final IdeKientrucCheck? check;
  final Object? checkError;
}

/// Kiến trúc dự án: sơ đồ, rủi ro, kiểm tra lỗi / cảnh báo, tiến độ.
class IdeKientrucScreen extends ConsumerWidget {
  const IdeKientrucScreen({this.project, super.key});

  final String? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(ideMoreServiceProvider);
    return IdeMorePage(
      title: tr('Kiến trúc', 'Architecture'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) => IdeLoader<_ArchData>(
          load: () async {
            final arch = await service.kientruc(p.name);
            if (!arch.exists) return _ArchData(arch, null, null);
            try {
              return _ArchData(arch, await service.kientrucCheck(p.name), null);
            } on Object catch (e) {
              return _ArchData(arch, null, e);
            }
          },
          builder: (context, d, reload) => _ArchView(data: d, reload: reload),
        ),
      ),
    );
  }
}

class _ArchView extends StatelessWidget {
  const _ArchView({required this.data, required this.reload});

  final _ArchData data;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final a = data.arch;
    if (!a.exists) {
      return WebTuiEmptyState(
        title: tr('Chưa có tài liệu kiến trúc', 'No architecture file'),
        message: tr(
          'Dự án này chưa có tệp .vpsttt/kien-truc.md.',
          'This project has no .vpsttt/kien-truc.md yet.',
        ),
        icon: Icons.account_tree_outlined,
      );
    }
    final head = WebTuiTypography.titleMedium.copyWith(
      color: WebTuiColors.textPrimary,
    );
    IdeDiagramSpec? spec;
    if (a.diagram != null) {
      try {
        spec = parseIdeDiagram(jsonEncode(a.diagram));
      } on Object {
        spec = null;
      }
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        key: const Key('ide_kientruc_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        children: [
          if (a.name.isNotEmpty)
            Text(a.name, style: WebTuiTypography.titleLarge),
          if (a.mtime != null)
            Text(
              '${tr('Cập nhật', 'Updated')} ${ideFormatDateTime(a.mtime!)}',
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
          if (a.progress != null) ...[
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              '${tr('Tiến độ', 'Progress')}: ${(a.progress! * 100).round()}%',
              style: head,
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            LinearProgressIndicator(
              key: const Key('ide_kientruc_progress'),
              value: a.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
          if (a.steps.isNotEmpty) ...[
            const SizedBox(height: WebTuiSpacing.sm),
            for (final s in a.steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      s.done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: s.done
                          ? WebTuiColors.accentGreen
                          : WebTuiColors.textMuted,
                    ),
                    const SizedBox(width: WebTuiSpacing.sm),
                    Expanded(child: Text(s.name)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: WebTuiSpacing.lg),
          Text(tr('Kiểm tra kiến trúc', 'Architecture check'), style: head),
          const SizedBox(height: WebTuiSpacing.sm),
          _check(),
          const SizedBox(height: WebTuiSpacing.lg),
          Text(tr('Sơ đồ', 'Diagram'), style: head),
          if (spec != null)
            IdeDiagramView(spec: spec)
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
              child: Text(
                tr('Chưa có sơ đồ.', 'No diagram yet.'),
                key: const Key('ide_kientruc_no_diagram'),
              ),
            ),
          if (a.risks.isNotEmpty) ...[
            const SizedBox(height: WebTuiSpacing.lg),
            Text(tr('Rủi ro đã biết', 'Known risks'), style: head),
            const SizedBox(height: WebTuiSpacing.sm),
            for (final r in a.risks)
              Padding(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
                child: IdeCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: WebTuiColors.accentAmber,
                      ),
                      const SizedBox(width: WebTuiSpacing.sm),
                      Expanded(child: Text(r.text)),
                      if (r.levelKey case final k?)
                        IdeTag(
                          switch (k) {
                            'high' => tr('Cao', 'High'),
                            'mid' => tr('Vừa', 'Medium'),
                            _ => tr('Thấp', 'Low'),
                          },
                          color: switch (k) {
                            'high' => WebTuiColors.danger,
                            'mid' => WebTuiColors.accentAmber,
                            _ => WebTuiColors.textMuted,
                          },
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _check() {
    final c = data.check;
    if (c == null) {
      return IdeCard(
        child: Text(
          data.checkError == null
              ? tr('Chưa kiểm tra.', 'Not checked.')
              : tr(
                  'Không kiểm tra được: ${ideMoreErrorText(data.checkError!)}',
                  'Could not check: ${ideMoreErrorText(data.checkError!)}',
                ),
          key: const Key('ide_kientruc_check_failed'),
        ),
      );
    }
    if (c.issues.isEmpty) {
      return IdeCard(
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: WebTuiColors.accentGreen),
            const SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Text(
                tr('Không có lỗi hoặc cảnh báo.', 'No errors or warnings.'),
                key: const Key('ide_kientruc_check_ok'),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      key: const Key('ide_kientruc_issues'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${c.errors} ${tr('lỗi', 'errors')} · ${c.warnings} ${tr('cảnh báo', 'warnings')}',
          style: WebTuiTypography.bodySmall.copyWith(
            color: c.errors > 0 ? WebTuiColors.danger : WebTuiColors.textMuted,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.xs),
        for (final i in c.issues)
          Padding(
            padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
            child: IdeCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IdeTag(
                    i.error ? tr('Lỗi', 'Error') : tr('Cảnh báo', 'Warning'),
                    color: i.error
                        ? WebTuiColors.danger
                        : WebTuiColors.accentAmber,
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Expanded(
                    child: Text(
                      i.ref.isEmpty ? i.text : '${i.text} (${i.ref})',
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
