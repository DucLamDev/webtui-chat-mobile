import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../l10n/app_strings.dart';
import 'ide_web_mic_chip.dart';

/// Thay thanh trên khi trang IDE đang hiện: nút tròn nổi góc dưới trái để quay
/// lại app (trang vẫn sống), kèm chỉ báo thu khi micro đang bật. Đặt ở góc dưới
/// để không che hàng biểu tượng sát mép trên của IDE.
class IdeWebBackButton extends StatelessWidget {
  const IdeWebBackButton({
    required this.onPressed,
    required this.capturing,
    this.showBack = true,
    super.key,
  });

  final VoidCallback onPressed;
  final ValueListenable<bool> capturing;

  /// `false` khi bàn phím đang mở: ẩn nút, chỉ còn chỉ báo thu (nếu có).
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBack)
          Material(
            color: c.surface,
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            shape: CircleBorder(side: BorderSide(color: c.hairline)),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              key: const Key('ide_web_back'),
              tooltip: tr('Quay lại app', 'Back to app'),
              onPressed: onPressed,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: c.textPrimary,
              ),
            ),
          ),
        ValueListenableBuilder<bool>(
          valueListenable: capturing,
          builder: (_, on, _) => on
              ? Padding(
                  padding: EdgeInsetsDirectional.only(start: showBack ? 8 : 0),
                  // Chỉ báo có nền nhạt: đặt trên nền đặc để đọc được trên
                  // mọi màu của trang IDE bên dưới.
                  child: Material(
                    color: c.surface,
                    elevation: 4,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    shape: StadiumBorder(side: BorderSide(color: c.hairline)),
                    clipBehavior: Clip.antiAlias,
                    child: IdeWebMicChip(capturing: capturing),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
