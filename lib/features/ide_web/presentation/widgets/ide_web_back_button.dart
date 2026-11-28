import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../l10n/app_strings.dart';
import 'ide_web_mic_chip.dart';

/// Nút tròn nổi thay thanh trên khi trang IDE đang hiện: quay lại app (trang
/// vẫn sống). Kéo để dời chỗ: xem `IdeWebFloatingBack`.
class IdeWebBackButton extends StatelessWidget {
  const IdeWebBackButton({required this.onPressed, super.key});

  static const size = 48.0;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return Material(
      color: c.surface,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: CircleBorder(side: BorderSide(color: c.hairline)),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        key: const Key('ide_web_back'),
        tooltip: tr(
          'Quay lại app (kéo để dời chỗ)',
          'Back to app (drag to move)',
        ),
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: size, height: size),
        padding: EdgeInsets.zero,
        icon: Icon(Icons.arrow_back_rounded, size: 22, color: c.textPrimary),
      ),
    );
  }
}

/// Chỉ báo đang thu đặt trên nền đặc (chỉ báo có nền nhạt) để đọc được trên
/// mọi màu của trang IDE bên dưới. Không thu thì không chiếm chỗ.
class IdeWebMicBadge extends StatelessWidget {
  const IdeWebMicBadge({required this.capturing, super.key});

  final ValueListenable<bool> capturing;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: capturing,
      builder: (_, on, _) => on
          ? Material(
              color: c.surface,
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              shape: StadiumBorder(side: BorderSide(color: c.hairline)),
              clipBehavior: Clip.antiAlias,
              child: IdeWebMicChip(capturing: capturing),
            )
          : const SizedBox.shrink(),
    );
  }
}
