import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import 'ide_web_buttons.dart';
import 'ide_web_code_window.dart';
import 'ide_web_mic_chip.dart';
import 'ide_web_prompt_sheet.dart';

/// Thanh trên của màn IDE: đóng, tên kèm địa chỉ trang, chỉ báo thu. Giữ thấp
/// (52) để trang IDE có thêm chỗ; nút đóng vẫn có vùng bấm 48.
class IdeWebTopBar extends StatelessWidget implements PreferredSizeWidget {
  const IdeWebTopBar({
    required this.onClose,
    this.host,
    this.capturing,
    super.key,
  });

  final VoidCallback onClose;

  /// Địa chỉ trang đang mở; `null` khi chưa mở trang.
  final String? host;
  final ValueListenable<bool>? capturing;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    final host = this.host;
    final capturing = this.capturing;
    return AppBar(
      toolbarHeight: 52,
      backgroundColor: host == null ? c.background : c.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      leadingWidth: 56,
      shape: host == null
          ? null
          : Border(bottom: BorderSide(color: c.hairline)),
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
      title: Row(
        children: [
          if (host != null && !ideWebLargeText(context)) ...[
            const IdeWebMark(size: 28),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
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
                if (host != null && !ideWebLargeText(context))
                  IdeWebHostLabel(host: host),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (capturing != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Center(child: IdeWebMicChip(capturing: capturing)),
          ),
      ],
    );
  }
}
