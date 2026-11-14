import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

/// Màu chủ đạo của hộp thoại: thường (xanh) hay nguy hiểm (đỏ: xoá, rời...).
enum WebTuiDialogTone { normal, danger }

const _dangerSoft = Color(0xFFFDECEC);

/// Một nút ở chân hộp thoại. `primary` là nút chính (nền đặc), còn lại là nút
/// phụ (nền xám nhạt). `destructive` tô đỏ nút chính.
final class WebTuiDialogAction {
  const WebTuiDialogAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
    this.loading = false,
    this.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool destructive;

  /// Đang xử lý: nút hiện vòng xoay và không bấm được.
  final bool loading;
  final Key? key;
}

/// Hộp thoại chuẩn của app: nền trắng bo 24, biểu tượng trong vòng tròn màu
/// nhạt (tuỳ chọn), tiêu đề đậm, lời giải thích, nội dung riêng (ô nhập...) và
/// hàng nút cao 48 chia đều bề ngang.
///
/// Dùng thay `AlertDialog` cho mọi hộp thoại mới để giao diện đồng bộ.
///
/// Cả hộp nằm trong một `SingleChildScrollView` (tránh tràn khi bàn phím mở),
/// nên [content] không được chứa widget cần chiều cao giới hạn (`ListView`,
/// `Expanded`...); danh sách dài thì dùng bảng trượt `showWebTuiSheet`.
class WebTuiDialog extends StatelessWidget {
  const WebTuiDialog({
    required this.title,
    this.message,
    this.icon,
    this.tone = WebTuiDialogTone.normal,
    this.content,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final WebTuiDialogTone tone;

  /// Nội dung riêng dưới lời giải thích (ô nhập, danh sách chọn...).
  final Widget? content;
  final List<WebTuiDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    final danger = tone == WebTuiDialogTone.danger;
    final icon = this.icon;
    return Dialog(
      backgroundColor: WebTuiColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebTuiRadii.dialog),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.xxl,
        vertical: WebTuiSpacing.xxl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.xxl,
            WebTuiSpacing.xxl,
            WebTuiSpacing.xxl,
            WebTuiSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: danger ? _dangerSoft : WebTuiColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 24,
                      color: danger
                          ? WebTuiColors.danger
                          : WebTuiColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.lg),
              ],
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: WebTuiTypography.titleLarge.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: WebTuiSpacing.sm),
                Text(
                  message!,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    fontSize: 15,
                    height: 1.45,
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: WebTuiSpacing.lg),
                content!,
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: WebTuiSpacing.xl),
                _DialogActions(actions: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogActions extends StatelessWidget {
  const _DialogActions({required this.actions});

  final List<WebTuiDialogAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.length <= 2) {
      return Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: WebTuiSpacing.md),
            Expanded(child: _DialogButton(action: actions[index])),
          ],
        ],
      );
    }
    // Nhiều lựa chọn: xếp dọc, nút chính lên đầu.
    final ordered = [
      ...actions.where((action) => action.primary),
      ...actions.where((action) => !action.primary),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < ordered.length; index++) ...[
          if (index > 0) const SizedBox(height: WebTuiSpacing.sm),
          _DialogButton(action: ordered[index]),
        ],
      ],
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.action});

  final WebTuiDialogAction action;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WebTuiRadii.lg - 2),
    );
    final textStyle = WebTuiTypography.bodyMedium.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w700,
    );
    final onPressed = action.loading ? null : action.onPressed;
    final label = action.loading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: action.primary
                  ? WebTuiColors.textOnPrimary
                  : WebTuiColors.primary,
            ),
          )
        : Text(action.label, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (action.primary) {
      final color = action.destructive
          ? WebTuiColors.danger
          : WebTuiColors.primary;
      return FilledButton(
        key: action.key,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: WebTuiColors.textOnPrimary,
          disabledBackgroundColor: color.withValues(alpha: 0.4),
          disabledForegroundColor: WebTuiColors.textOnPrimary,
          minimumSize: const Size.fromHeight(48),
          shape: shape,
          textStyle: textStyle,
          elevation: 0,
        ),
        child: label,
      );
    }
    return TextButton(
      key: action.key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: WebTuiColors.backgroundMuted,
        foregroundColor: action.destructive
            ? WebTuiColors.danger
            : WebTuiColors.textPrimary,
        minimumSize: const Size.fromHeight(48),
        shape: shape,
        textStyle: textStyle,
      ),
      child: label,
    );
  }
}

/// Hỏi xác nhận (Huỷ / nút chính). Trả `true` khi người dùng bấm nút chính;
/// bấm Huỷ, chạm ra ngoài hay nút Back đều là `false`.
Future<bool> showWebTuiConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Đồng ý',
  String cancelLabel = 'Huỷ',
  bool destructive = false,
  IconData? icon,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => WebTuiDialog(
      title: title,
      message: message,
      icon: icon,
      tone: destructive ? WebTuiDialogTone.danger : WebTuiDialogTone.normal,
      actions: [
        WebTuiDialogAction(
          key: const Key('webtui_dialog_cancel'),
          label: cancelLabel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        WebTuiDialogAction(
          key: const Key('webtui_dialog_confirm'),
          label: confirmLabel,
          primary: true,
          destructive: destructive,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Hộp thoại nhập một dòng chữ (tên thư mục, đổi tên...). Trả chữ đã cắt
/// khoảng trắng, hoặc `null` khi huỷ. Nút chính chỉ bấm được khi đã nhập và
/// [validator] (nếu có) không báo lỗi.
Future<String?> showWebTuiTextInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? label,
  String? hint,
  String initialValue = '',
  String confirmLabel = 'Lưu',
  String cancelLabel = 'Huỷ',
  int? maxLength,
  IconData? icon,
  String? Function(String value)? validator,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      message: message,
      label: label,
      hint: hint,
      initialValue: initialValue,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      maxLength: maxLength,
      icon: icon,
      validator: validator,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.maxLength,
    required this.icon,
    required this.validator,
  });

  final String title;
  final String? message;
  final String? label;
  final String? hint;
  final String initialValue;
  final String confirmLabel;
  final String cancelLabel;
  final int? maxLength;
  final IconData? icon;
  final String? Function(String value)? validator;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _value => _controller.text.trim();

  String? get _error {
    if (_value.isEmpty) return null;
    return widget.validator?.call(_value);
  }

  bool get _canSubmit => _value.isNotEmpty && _error == null;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    return WebTuiDialog(
      title: widget.title,
      message: widget.message,
      icon: widget.icon,
      content: WebTuiDialogTextField(
        key: const Key('webtui_dialog_input'),
        controller: _controller,
        label: widget.label,
        hint: widget.hint,
        maxLength: widget.maxLength,
        errorText: _error,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        WebTuiDialogAction(
          key: const Key('webtui_dialog_cancel'),
          label: widget.cancelLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WebTuiDialogAction(
          key: const Key('webtui_dialog_confirm'),
          label: widget.confirmLabel,
          primary: true,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}

/// Ô nhập trong hộp thoại / bảng trượt: nền xám nhạt, bo 14, viền xanh khi
/// đang gõ (khác ô viền mảnh mặc định của Material).
class WebTuiDialogTextField extends StatelessWidget {
  const WebTuiDialogTextField({
    required this.controller,
    this.label,
    this.hint,
    this.maxLength,
    this.errorText,
    this.autofocus = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffix,
    this.showCounter = true,
    this.minLines,
    this.maxLines = 1,
    this.focusNode,
    this.enabled = true,
    this.autocorrect = true,
    this.enableSuggestions = true,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final int? maxLength;
  final String? errorText;
  final bool autofocus;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final Widget? suffix;

  /// Hiện bộ đếm ký tự dưới ô khi có [maxLength] (tắt cho ô ngắn lặp lại).
  final bool showCounter;

  /// Ô nhiều dòng (mô tả...): đặt [minLines] / [maxLines] > 1; bàn phím có
  /// phím xuống dòng.
  final int? minLines;
  final int? maxLines;

  final FocusNode? focusNode;

  /// `false` khi đang xử lý: không gõ thêm được.
  final bool enabled;

  /// Tắt cho mã OTP, mã khôi phục, mật khẩu (không gợi ý / tự sửa).
  final bool autocorrect;
  final bool enableSuggestions;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebTuiRadii.lg - 2),
          borderSide: BorderSide(color: color, width: width),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: WebTuiTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w700,
              color: WebTuiColors.textSecondary,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.xs + 2),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          autofocus: autofocus,
          obscureText: obscureText,
          minLines: minLines,
          maxLines: obscureText ? 1 : maxLines,
          keyboardType:
              keyboardType ?? (maxLines != 1 ? TextInputType.multiline : null),
          textInputAction: maxLines != 1
              ? TextInputAction.newline
              : textInputAction,
          maxLength: maxLength,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: WebTuiTypography.bodyMedium.copyWith(
            fontSize: 16,
            color: WebTuiColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            counterText: showCounter ? null : '',
            filled: true,
            fillColor: WebTuiColors.backgroundMuted,
            prefixIcon: prefixIcon == null
                ? null
                : Icon(prefixIcon, size: 20, color: WebTuiColors.textMuted),
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: WebTuiSpacing.lg,
              vertical: 14,
            ),
            border: border(Colors.transparent),
            enabledBorder: border(Colors.transparent),
            focusedBorder: border(WebTuiColors.primary, 1.6),
            errorBorder: border(WebTuiColors.danger),
            focusedErrorBorder: border(WebTuiColors.danger, 1.6),
          ),
        ),
      ],
    );
  }
}

/// Mở bảng trượt từ dưới lên theo kiểu chung: nền trắng, bo 24, có thanh kéo,
/// tránh bàn phím và vùng an toàn.
Future<T?> showWebTuiSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: WebTuiColors.surface,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}

/// Tiêu đề trong bảng trượt: chữ đậm 18, dòng phụ xám, nút bên phải (tuỳ chọn).
class WebTuiSheetHeader extends StatelessWidget {
  const WebTuiSheetHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.xl,
        0,
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: WebTuiTypography.titleMedium.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: WebTuiSpacing.xxs),
                  Text(
                    subtitle!,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Một dòng thao tác trong bảng trượt: biểu tượng trong ô vuông bo 14 màu
/// nhạt, tiêu đề, dòng phụ; cao tối thiểu 60 để dễ bấm.
class WebTuiSheetActionTile extends StatelessWidget {
  const WebTuiSheetActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.tone = WebTuiDialogTone.normal,
    this.trailing,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final WebTuiDialogTone tone;
  final Widget? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final danger = tone == WebTuiDialogTone.danger;
    final foreground = danger ? WebTuiColors.danger : WebTuiColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.sm),
      child: Material(
        color: selected ? WebTuiColors.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WebTuiSpacing.md,
                vertical: WebTuiSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: danger ? _dangerSoft : WebTuiColors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 21, color: foreground),
                  ),
                  const SizedBox(width: WebTuiSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: danger
                                ? WebTuiColors.danger
                                : WebTuiColors.textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: WebTuiTypography.bodySmall.copyWith(
                              color: WebTuiColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: WebTuiSpacing.sm),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
