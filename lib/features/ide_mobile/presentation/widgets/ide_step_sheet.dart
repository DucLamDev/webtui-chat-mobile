import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/ide_step_up.dart';

/// Màn đặt presenter hộp vân tay khi mở và trả lại cái trước đó khi đóng
/// (chỉ khi presenter hiện tại vẫn là của màn này).
final class IdeStepPresenterLease {
  IdeStepPresenterLease(this._notifier);

  final StateController<IdeStepPresenter?> _notifier;
  IdeStepPresenter? _previous;
  IdeStepPresenter? _mine;

  void acquire(BuildContext context, bool Function() mounted) {
    _previous = _notifier.state;
    _mine = (summary) =>
        mounted() ? showIdeStepSheet(context, summary) : Future.value(false);
    _notifier.state = _mine;
  }

  void release() {
    final mine = _mine;
    final previous = _previous;
    _mine = null;
    // Đang dỡ cây widget: không đổi provider ngay (Riverpod báo lỗi).
    Future.microtask(() {
      try {
        if (identical(_notifier.state, mine)) _notifier.state = previous;
      } on StateError {
        // Kho provider đã đóng cùng ứng dụng / test.
      }
    });
  }
}

/// Bảng tóm tắt thao tác nhạy cảm trước khi ký bằng vân tay.
Future<bool> showIdeStepSheet(
  BuildContext context,
  IdeStepSummary summary,
) async {
  final accepted = await showWebTuiSheet<bool>(
    context: context,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        0,
        WebTuiSpacing.lg,
        WebTuiSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebTuiSheetHeader(
            title: tr('Xác nhận thao tác', 'Confirm action'),
            subtitle: tr(
              'IDE trên máy tính đang chờ bạn xác nhận.',
              'The IDE on your computer is waiting for you.',
            ),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          Text(
            summary.summary.isEmpty ? summary.op : summary.summary,
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
          // Tên thao tác lấy từ yêu cầu của chính app (phần được ký), không
          // chỉ lời tóm tắt do IDE gửi.
          if (summary.summary.isNotEmpty) ...[
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              tr('Thao tác: ${summary.op}', 'Action: ${summary.op}'),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: WebTuiSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text(tr('Huỷ', 'Cancel')),
                ),
              ),
              const SizedBox(width: WebTuiSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: Text(tr('Xác nhận', 'Confirm')),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return accepted ?? false;
}
