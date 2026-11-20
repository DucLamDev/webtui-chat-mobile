import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../icons/webtui_icons.dart';
import '../tokens/webtui_colors.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

/// Ô tìm bo tròn hẳn (nền xanh nhạt, không viền khi chưa focus).
const _radius = 10.0;

class WebTuiSearchBar extends StatefulWidget {
  const WebTuiSearchBar({
    required this.hintText,
    this.controller,
    this.onChanged,
    this.onTap,
    this.debounceDuration = const Duration(milliseconds: 250),
    this.fillColor,
    this.accentColor,
    super.key,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final Duration debounceDuration;

  /// Nền ô (mặc định nền chip chung của app).
  final Color? fillColor;

  /// Màu biểu tượng / con trỏ khi đang gõ (mặc định màu nhấn của app).
  final Color? accentColor;

  @override
  State<WebTuiSearchBar> createState() => _WebTuiSearchBarState();
}

class _WebTuiSearchBarState extends State<WebTuiSearchBar> {
  final _focusNode = FocusNode();
  // Ô tìm luôn có controller để nút đóng xoá được chữ, kể cả khi màn gọi không
  // truyền controller.
  TextEditingController? _ownController;
  Timer? _debounceTimer;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _ownController?.dispose();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    final interactive = widget.onChanged != null || widget.controller != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      // Kiểu iOS: nền xám nhạt bo 10, không viền, không bóng; đang gõ chỉ đổi
      // màu biểu tượng.
      height: 40,
      decoration: BoxDecoration(
        color: widget.fillColor ?? WebTuiColors.of(context).chipBackground,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            widget.onTap?.call();
            if (interactive) {
              _focusNode.requestFocus();
            }
          },
          borderRadius: BorderRadius.circular(_radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
            child: Row(
              children: [
                Icon(
                  WebTuiIcons.search,
                  size: 19,
                  color: focused
                      ? (widget.accentColor ?? WebTuiColors.of(context).primary)
                      : WebTuiColors.of(context).textMuted,
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                Expanded(
                  child: interactive
                      ? TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: _handleTextChanged,
                          // Chạm ra ngoài hoặc bấm Tìm trên bàn phím thì đóng
                          // bàn phím (iOS không tự bỏ focus).
                          onTapOutside: (_) => _focusNode.unfocus(),
                          onSubmitted: (_) => _focusNode.unfocus(),
                          maxLines: 1,
                          textInputAction: TextInputAction.search,
                          cursorColor:
                              widget.accentColor ??
                              WebTuiColors.of(context).primary,
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                            hintText: widget.hintText,
                            hintStyle: WebTuiTypography.bodyMedium.copyWith(
                              color: WebTuiColors.of(context).textSecondary,
                            ),
                          ),
                          style: WebTuiTypography.bodyMedium.copyWith(
                            color: WebTuiColors.of(context).textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : Text(
                          widget.hintText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            color: WebTuiColors.of(context).textSecondary,
                          ),
                        ),
                ),
                if (interactive && focused)
                  IconButton(
                    tooltip: tr('Đóng tìm kiếm', 'Close search'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: Icon(
                      WebTuiIcons.close,
                      size: 18,
                      color: WebTuiColors.of(context).textMuted,
                    ),
                    onPressed: _close,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Xoá chữ, trả danh sách về đầy đủ ngay (không chờ debounce) và đóng bàn phím.
  void _close() {
    _debounceTimer?.cancel();
    if (_controller.text.isNotEmpty) {
      _controller.clear();
      widget.onChanged?.call('');
    }
    _focusNode.unfocus();
  }

  void _handleTextChanged(String value) {
    final onChanged = widget.onChanged;
    if (onChanged == null) {
      return;
    }
    _debounceTimer?.cancel();
    if (widget.debounceDuration == Duration.zero) {
      onChanged(value);
      return;
    }
    _debounceTimer = Timer(widget.debounceDuration, () {
      if (mounted) {
        onChanged(value);
      }
    });
  }
}
