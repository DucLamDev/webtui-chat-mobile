import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../application/use_cases/login_mfa_use_cases.dart';

/// Ô nhập mã một lần 6 số: hiện thành 6 ô vuông chia 3–3.
///
/// Bên dưới là MỘT [TextField] thật (trong suốt, phủ lên các ô) nên tự điền
/// mã từ tin nhắn / ứng dụng (`AutofillHints.oneTimeCode`), dán và trình đọc
/// màn hình đều chạy như ô nhập thường. Các ô chỉ vẽ lại từ giá trị.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.onCompleted,
    this.hasError = false,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel = 'Mã xác thực 6 số',
    this.fieldKey,
    super.key,
  });

  static const length = 6;

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  /// Gọi đúng một lần mỗi khi mã vừa đủ 6 số do người dùng gõ / dán.
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool enabled;
  final bool autofocus;
  final String semanticLabel;

  /// Key của ô nhập thật (để test gõ / dán).
  final Key? fieldKey;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _caret = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  /// Giá trị ngay trước lần đổi gần nhất và giá trị hiện tại: để biết mã vừa
  /// đủ 6 số (gọi [OtpCodeField.onCompleted] một lần), kể cả khi màn hình xoá
  /// ô từ bên ngoài sau khi sai mã.
  String _previousValue = '';
  String _currentValue = '';

  @override
  void initState() {
    super.initState();
    _currentValue = widget.controller.text;
    _previousValue = _currentValue;
    widget.controller.addListener(_onValueChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onValueChanged);
      widget.controller.addListener(_onValueChanged);
      _currentValue = widget.controller.text;
      _previousValue = _currentValue;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onValueChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    _caret.dispose();
    super.dispose();
  }

  void _onValueChanged() {
    if (!mounted) return;
    final text = widget.controller.text;
    if (text == _currentValue) return;
    _previousValue = _currentValue;
    _currentValue = text;
    setState(() {});
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleChanged(String value) {
    final wasComplete = _previousValue.length == OtpCodeField.length;
    _previousValue = value;
    _currentValue = value;
    widget.onChanged(value);
    if (!wasComplete && value.length == OtpCodeField.length) {
      widget.onCompleted?.call(value);
    }
  }

  void _syncCaretAnimation(bool active) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (active && !reduceMotion) {
      if (!_caret.isAnimating) _caret.repeat();
    } else if (_caret.isAnimating || _caret.value != 0) {
      _caret
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    final focused = widget.focusNode.hasFocus && widget.enabled;
    final activeIndex = !focused
        ? -1
        : value.length >= OtpCodeField.length
        ? OtpCodeField.length - 1
        : value.length;
    _syncCaretAnimation(focused && value.length < OtpCodeField.length);
    final errorColor = Theme.of(context).colorScheme.error;

    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = WebTuiSpacing.sm;
          const groupGap = WebTuiSpacing.xl;
          final available = constraints.maxWidth - gap * 4 - groupGap;
          final boxWidth = (available / OtpCodeField.length).clamp(36.0, 56.0);
          final boxHeight = (boxWidth * 1.2).clamp(52.0, 64.0);

          Widget box(int index) => _OtpBox(
            digit: index < value.length ? value[index] : null,
            width: boxWidth,
            height: boxHeight,
            active: index == activeIndex,
            showCaret: index == activeIndex && index >= value.length,
            caret: _caret,
            hasError: widget.hasError,
            errorColor: errorColor,
            enabled: widget.enabled,
          );

          return SizedBox(
            height: boxHeight,
            child: Stack(
              children: [
                ExcludeSemantics(
                  child: Row(
                    children: [
                      box(0),
                      const SizedBox(width: gap),
                      box(1),
                      const SizedBox(width: gap),
                      box(2),
                      const SizedBox(width: groupGap),
                      box(3),
                      const SizedBox(width: gap),
                      box(4),
                      const SizedBox(width: gap),
                      box(5),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: boxWidth * OtpCodeField.length + gap * 4 + groupGap,
                  child: _InvisibleInput(
                    fieldKey: widget.fieldKey,
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    enabled: widget.enabled,
                    autofocus: widget.autofocus,
                    onChanged: _handleChanged,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InvisibleInput extends StatelessWidget {
  const _InvisibleInput({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.autofocus,
    required this.onChanged,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextSelectionTheme(
      data: const TextSelectionThemeData(
        selectionColor: Colors.transparent,
        cursorColor: Colors.transparent,
        selectionHandleColor: Colors.transparent,
      ),
      child: TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        autocorrect: false,
        enableSuggestions: false,
        showCursor: false,
        expands: true,
        maxLines: null,
        maxLength: OtpCodeField.length,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: const [_OtpInputFormatter()],
        style: const TextStyle(color: Colors.transparent, fontSize: 1),
        decoration: const InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          counterText: '',
          isCollapsed: true,
          contentPadding: EdgeInsets.zero,
        ),
        // Luôn gõ / xoá ở cuối mã, kể cả khi chạm vào giữa các ô.
        onTap: () => controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// Giữ đúng 6 chữ số khi gõ hoặc dán (bỏ dấu cách, gạch, chữ quanh mã).
class _OtpInputFormatter extends TextInputFormatter {
  const _OtpInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final code = extractLoginTotpCode(newValue.text);
    if (code == newValue.text && newValue.selection.isCollapsed) {
      return newValue.copyWith(
        selection: TextSelection.collapsed(offset: code.length),
      );
    }
    return TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.digit,
    required this.width,
    required this.height,
    required this.active,
    required this.showCaret,
    required this.caret,
    required this.hasError,
    required this.errorColor,
    required this.enabled,
  });

  final String? digit;
  final double width;
  final double height;
  final bool active;
  final bool showCaret;
  final Animation<double> caret;
  final bool hasError;
  final Color errorColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? errorColor
        : active
        ? WebTuiColors.primary
        : WebTuiColors.border;
    final borderWidth = hasError || active ? 2.0 : 1.2;
    final text = digit;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: text != null
          ? Text(
              text,
              style: WebTuiTypography.titleLarge.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1,
                color: enabled
                    ? WebTuiColors.textPrimary
                    : WebTuiColors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          : showCaret
          ? FadeTransition(
              opacity: caret.drive(_blink),
              child: Container(
                width: 2,
                height: height * 0.42,
                decoration: BoxDecoration(
                  color: WebTuiColors.primary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            )
          : null,
    );
  }
}

/// Nhấp nháy dạng bật / tắt như dấu nháy hệ thống (không mờ dần).
final _blink = TweenSequence<double>([
  TweenSequenceItem(tween: ConstantTween(1), weight: 55),
  TweenSequenceItem(tween: ConstantTween(0), weight: 45),
]);
