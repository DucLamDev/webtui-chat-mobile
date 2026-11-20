import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../ide_wb.dart';

const ideMonoStyle = TextStyle(
  fontFamily: WebTuiTypography.monoFamily,
  fontFamilyFallback: WebTuiTypography.monoFallback,
  fontSize: 12.5,
  height: 1.4,
);

/// Khối mã: tên ngôn ngữ, nút chép, mã dòng, cuộn ngang.
class IdeCodeBlock extends StatelessWidget {
  const IdeCodeBlock({
    required this.code,
    this.language = '',
    this.lineNumbers = true,
    super.key,
  });

  final String code;
  final String language;
  final bool lineNumbers;

  @override
  Widget build(BuildContext context) {
    final lines = code.isEmpty ? <String>[''] : code.split('\n');
    final numbersOn = lineNumbers && lines.length > 1;
    final digits = '${lines.length}'.length;
    final mono = ideMonoStyle.copyWith(
      color: IdeWbPalette.of(context).textStrong,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      decoration: BoxDecoration(
        color: IdeWbPalette.of(context).chip,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: IdeWbPalette.of(context).border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(left: WebTuiSpacing.md),
            color: IdeWbPalette.of(context).chip,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.isEmpty ? tr('Mã', 'Code') : language,
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: IdeWbPalette.of(context).text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('Chép mã', 'Copy code'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!context.mounted) return;
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(
                        content: Text(tr('Đã chép', 'Copied')),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(WebTuiSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (numbersOn) ...[
                  Text(
                    [
                      for (var i = 1; i <= lines.length; i++)
                        '$i'.padLeft(digits),
                    ].join('\n'),
                    textAlign: TextAlign.right,
                    style: mono.copyWith(color: IdeWbPalette.of(context).text2),
                  ),
                  const SizedBox(width: WebTuiSpacing.md),
                ],
                SelectableText(code, style: mono),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
