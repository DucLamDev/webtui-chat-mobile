import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_radii.dart';
import '../tokens/webtui_spacing.dart';
import '../tokens/webtui_typography.dart';

class WebTuiSearchBar extends StatefulWidget {
  const WebTuiSearchBar({
    required this.hintText,
    this.controller,
    this.onChanged,
    this.onTap,
    this.debounceDuration = const Duration(milliseconds: 250),
    super.key,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final Duration debounceDuration;

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
      height: 42,
      decoration: BoxDecoration(
        color: focused ? WebTuiColors.surface : WebTuiColors.backgroundMuted,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(
          color: focused
              ? WebTuiColors.primary.withValues(alpha: 0.72)
              : WebTuiColors.border.withValues(alpha: 0.55),
          width: focused ? 1.2 : 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: WebTuiColors.primary.withValues(alpha: 0.09),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
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
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.search,
                  size: 19,
                  color: focused
                      ? WebTuiColors.primary
                      : WebTuiColors.textSecondary,
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
                          cursorColor: WebTuiColors.primary,
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
                              color: WebTuiColors.textMuted,
                            ),
                          ),
                          style: WebTuiTypography.bodyMedium.copyWith(
                            color: WebTuiColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : Text(
                          widget.hintText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            color: WebTuiColors.textMuted,
                          ),
                        ),
                ),
                if (interactive && focused)
                  IconButton(
                    tooltip: 'Đóng tìm kiếm',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 18,
                      color: WebTuiColors.textMuted,
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
