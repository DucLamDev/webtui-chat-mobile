import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';

/// Chỉ báo "Đang thu" trên thanh tiêu đề khi trang IDE đang dùng micro.
class IdeWebMicChip extends StatelessWidget {
  const IdeWebMicChip({required this.capturing, super.key});

  final ValueListenable<bool> capturing;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: capturing,
      builder: (context, active, _) {
        if (!active) return const SizedBox.shrink();
        final c = WebTuiColors.of(context);
        return Semantics(
          container: true,
          liveRegion: true,
          label: tr('Đang thu micro', 'Microphone is recording'),
          excludeSemantics: true,
          child: Row(
            key: const Key('ide_web_mic_chip'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic_rounded, size: 18, color: c.danger),
              const SizedBox(width: WebTuiSpacing.xs),
              Flexible(
                child: Text(
                  tr('Đang thu', 'Recording'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: c.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
