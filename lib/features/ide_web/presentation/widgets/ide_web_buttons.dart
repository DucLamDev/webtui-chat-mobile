import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import 'ide_web_code_window.dart';

/// Chữ hệ thống lớn: thu hình, bỏ chữ phụ để nội dung chính không bị cắt.
bool ideWebLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13;

final class IdeWebAction {
  const IdeWebAction({
    required this.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final Key key;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
}

/// Nút trải hết bề ngang của màn và bảng hỏi VPSTTT IDE; chữ dài xuống dòng, không
/// cắt.
class IdeWebButton extends StatelessWidget {
  const IdeWebButton.primary(this.action, {super.key}) : _primary = true;

  const IdeWebButton.secondary(this.action, {super.key}) : _primary = false;

  final IdeWebAction action;
  final bool _primary;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    // Lấy từ theme chứ không từ WebTuiTypography: `textStyle` của nút thay hẳn kiểu
    // chữ mặc định, kiểu không có phông thì nút rơi về phông khác phần còn lại.
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(fontSize: 16, fontWeight: FontWeight.w700);
    final label = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(action.label, textAlign: TextAlign.center),
    );
    if (_primary) {
      return FilledButton(
        key: action.key,
        onPressed: action.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: action.destructive
              ? IdeWebInk.alertRed
              : c.primaryFill,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: shape,
          textStyle: style,
          elevation: 0,
        ),
        child: label,
      );
    }
    return TextButton(
      key: action.key,
      onPressed: action.onPressed,
      style: TextButton.styleFrom(
        foregroundColor: c.textSecondary,
        minimumSize: const Size.fromHeight(50),
        shape: shape,
        textStyle: style.copyWith(fontWeight: FontWeight.w600),
      ),
      child: label,
    );
  }
}
