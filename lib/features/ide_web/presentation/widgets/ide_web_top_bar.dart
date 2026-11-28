import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';

/// Thanh trên của các màn trạng thái IDE (đang mở, lỗi, tắt...): nút đóng và
/// tên. Trang IDE đã hiện thì không có thanh này (xem `IdeWebBackButton`).
/// Giữ thấp (52); nút đóng vẫn có vùng bấm 48.
class IdeWebTopBar extends StatelessWidget implements PreferredSizeWidget {
  const IdeWebTopBar({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return AppBar(
      toolbarHeight: 52,
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      leadingWidth: 56,
      leading: Center(
        child: IconButton(
          key: const Key('ide_web_close'),
          tooltip: tr('Đóng', 'Close'),
          onPressed: onClose,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          padding: EdgeInsets.zero,
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.chipBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.close_rounded, size: 20, color: c.textPrimary),
          ),
        ),
      ),
      title: Text(
        'VPSTTT IDE',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: WebTuiTypography.titleMedium.copyWith(
          fontSize: 15.5,
          height: 1.2,
          fontWeight: FontWeight.w800,
          color: c.textPrimary,
        ),
      ),
    );
  }
}
