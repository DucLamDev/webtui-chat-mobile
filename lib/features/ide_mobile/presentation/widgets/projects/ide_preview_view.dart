import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_deploy.dart';
import '../markdown/ide_code_block.dart';

/// Nhãn dễ hiểu của ký hiệu `s` trong bản xem trước.
String idePreviewStatusLabel(String s) => switch (s) {
  'A' => tr('Tệp mới', 'New'),
  'M' => tr('Sửa', 'Modified'),
  'D' => tr('Xoá', 'Deleted'),
  'N' => tr(
    'Máy chủ mới hơn (sẽ bị ghi đè)',
    'Server newer (will be overwritten)',
  ),
  'P' => tr('Chỉ đổi quyền', 'Permissions only'),
  _ => s,
};

Color idePreviewStatusColor(String s) => switch (s) {
  'A' => WebTuiColors.accentGreen,
  'D' => WebTuiColors.danger,
  'N' => WebTuiColors.accentAmber,
  _ => WebTuiColors.primary,
};

/// Hiện bản xem trước chuẩn: tóm tắt, cảnh báo, tệp theo `s`, diff.
class IdePreviewView extends StatelessWidget {
  const IdePreviewView({required this.preview, super.key});

  final IdeDeployPreview preview;

  /// Mỗi nhóm có giới hạn riêng, nhóm xoá / ghi đè hiện trước.
  static const _maxFiles = 200;
  static const _maxDiffLines = 400;
  static const _maxDiffLine = 500;
  static const _maxDiffChars = 100 * 1024;

  /// Cắt diff: mỗi dòng ≤ 500 ký tự, tổng ≤ 400 dòng / 100 KB.
  static (List<String>, bool) clipDiff(String diff) {
    final out = <String>[];
    var cut = false;
    var chars = 0;
    for (final raw in diff.split('\n')) {
      if (out.length >= _maxDiffLines || chars >= _maxDiffChars) {
        cut = true;
        break;
      }
      var line = raw;
      if (line.length > _maxDiffLine) {
        line = line.substring(0, _maxDiffLine);
        cut = true;
      }
      chars += line.length + 1;
      out.add(line);
    }
    return (out, cut);
  }

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final counts = p.counts;
    final order = ['D', 'N', 'A', 'M', 'P'];
    final groups = [
      for (final s in [
        ...order,
        ...counts.keys.where((k) => !order.contains(k)),
      ])
        if ((counts[s] ?? 0) > 0) s,
    ];
    final (diffLines, diffCut) = clipDiff(p.diff);
    var more = p.truncated;
    for (final s in groups) {
      if (p.files.where((f) => f.s == s).length > _maxFiles) more = true;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.subject.isNotEmpty || p.sha.isNotEmpty)
          Text(
            [
              if (p.sha.isNotEmpty)
                p.sha.substring(0, p.sha.length.clamp(0, 7)),
              p.subject,
            ].where((e) => e.isNotEmpty).join(' · '),
            key: const Key('ide_preview_subject'),
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (p.base != null && p.base!.commit.isNotEmpty)
          Text(
            '${tr('Đang chạy trên máy chủ', 'Currently on the server')}: '
            '${p.base!.commit.substring(0, p.base!.commit.length.clamp(0, 7))}'
            ' ${p.base!.subject}',
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textMuted,
            ),
          ),
        const SizedBox(height: WebTuiSpacing.sm),
        for (final w in p.warnings)
          Container(
            key: const Key('ide_preview_warning'),
            margin: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
            padding: const EdgeInsets.all(WebTuiSpacing.sm),
            decoration: BoxDecoration(
              color: WebTuiColors.accentAmber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: WebTuiColors.accentAmber,
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                Expanded(
                  child: Text(
                    w,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (p.deleteMany)
          Container(
            key: const Key('ide_preview_delete_many'),
            margin: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
            padding: const EdgeInsets.all(WebTuiSpacing.sm),
            decoration: BoxDecoration(
              color: WebTuiColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tr(
                'Bản này xoá rất nhiều tệp trên máy chủ. Hãy xem kỹ danh sách.',
                'This deploy deletes many files on the server. Review the list.',
              ),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.danger,
              ),
            ),
          ),
        if (p.files.isEmpty)
          Text(
            tr('Không có tệp nào thay đổi.', 'No files changed.'),
            key: const Key('ide_preview_no_files'),
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          )
        else ...[
          Text(
            '${p.total} ${tr('tệp thay đổi', 'changed files')}',
            key: const Key('ide_preview_total'),
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
          for (final s in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
              child: Text(
                '${idePreviewStatusLabel(s)} (${counts[s]})',
                key: Key('ide_preview_group_$s'),
                style: WebTuiTypography.labelSmall.copyWith(
                  color: idePreviewStatusColor(s),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final f in p.files.where((f) => f.s == s).take(_maxFiles))
              IdePathText(
                f.path,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
          ],
          if (more)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: Text(
                tr('Danh sách chưa hiện hết.', 'The list is not complete.'),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
            ),
        ],
        if (p.diff.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('ide_preview_diff'),
              tilePadding: EdgeInsets.zero,
              title: Text(tr('Xem chi tiết thay đổi', 'View the diff')),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        for (final line in diffLines)
                          TextSpan(
                            text: '$line\n',
                            style: TextStyle(
                              color:
                                  line.startsWith('+') &&
                                      !line.startsWith('+++')
                                  ? WebTuiColors.accentGreen
                                  : line.startsWith('-') &&
                                        !line.startsWith('---')
                                  ? WebTuiColors.danger
                                  : WebTuiColors.textSecondary,
                            ),
                          ),
                        if (diffCut)
                          TextSpan(
                            text: tr('(đã cắt bớt)', '(truncated)'),
                            style: TextStyle(color: WebTuiColors.textMuted),
                          ),
                      ],
                    ),
                    style: ideMonoStyle,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Dòng báo lý do nút Triển khai đang tắt.
String? ideDeployBlockText(IdeDeployBlock b) => switch (b) {
  IdeDeployBlock.none => null,
  IdeDeployBlock.missing => tr(
    'Hãy bấm "Xem trước" trước khi triển khai.',
    'Run "Preview" before deploying.',
  ),
  IdeDeployBlock.otherProject || IdeDeployBlock.otherTarget => tr(
    'Bản xem trước là của máy khác, hãy xem trước lại.',
    'The preview is for another target, preview again.',
  ),
  IdeDeployBlock.expired => tr(
    'Bản xem trước đã cũ (quá 15 phút), hãy xem trước lại.',
    'The preview is too old (over 15 min), preview again.',
  ),
  IdeDeployBlock.used => tr(
    'Bản xem trước đã dùng rồi, hãy xem trước lại.',
    'The preview was already used, preview again.',
  ),
};

/// Đường dẫn tệp một dòng, dài quá thì cắt ở phần thư mục, luôn giữ tên tệp
/// (`backend/…/ide_relay/application/notify.go` thay vì cắt mất đuôi).
class IdePathText extends StatelessWidget {
  const IdePathText(this.path, {super.key, this.style});

  final String path;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cut = path.lastIndexOf('/');
    if (cut <= 0 || cut == path.length - 1) {
      return Text(
        path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final dir = path.substring(0, cut + 1);
    final name = path.substring(cut + 1);
    return Semantics(
      label: path,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Flexible(
              child: Text(
                dir,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: c.maxWidth.isFinite ? c.maxWidth * 0.7 : 600,
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
