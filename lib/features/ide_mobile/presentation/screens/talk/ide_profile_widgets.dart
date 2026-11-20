import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../more/ide_more_common.dart';

/// Tiêu đề mục + nội dung trong thẻ.
class IdeProfileSection extends StatelessWidget {
  const IdeProfileSection({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: WebTuiSpacing.xs,
            bottom: WebTuiSpacing.xs,
          ),
          child: Text(
            title,
            style: WebTuiTypography.titleMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
        ),
        IdeCard(child: child),
      ],
    ),
  );
}

/// Tải một mục con: nhỏ gọn (đang tải / lỗi + thử lại / không quyền) để lỗi một
/// mục không làm hỏng cả màn.
class IdeProfileAsync<T> extends StatefulWidget {
  const IdeProfileAsync({required this.load, required this.builder, super.key});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<IdeProfileAsync<T>> createState() => _IdeProfileAsyncState<T>();
}

class _IdeProfileAsyncState<T> extends State<IdeProfileAsync<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (mounted && seq == _seq) setState(() => _data = d);
    } on Object catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(WebTuiSpacing.md),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final e = _error;
    if (e != null) {
      return Row(
        children: [
          Icon(
            e is IdeForbidden
                ? Icons.lock_outline_rounded
                : Icons.error_outline,
            color: WebTuiColors.textSecondary,
          ),
          const SizedBox(width: WebTuiSpacing.sm),
          Expanded(
            child: Text(
              e is IdeForbidden
                  ? tr(
                      'Bạn không có quyền xem mục này.',
                      'You do not have access to this.',
                    )
                  : ideMoreErrorText(e),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            ),
          ),
          if (e is! IdeForbidden)
            TextButton(onPressed: _run, child: Text(tr('Thử lại', 'Retry'))),
        ],
      );
    }
    return widget.builder(context, _data as T);
  }
}

/// Hai cột nhãn / giá trị.
class IdeKeyValue extends StatelessWidget {
  const IdeKeyValue(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: WebTuiSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
