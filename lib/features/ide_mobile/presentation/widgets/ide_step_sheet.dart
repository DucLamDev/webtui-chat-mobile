import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/ide_step_up.dart';
import '../../domain/ide_visible_text.dart';
import 'ide_wb.dart';

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
      // Bảng dưới chỉ tránh tai thỏ phía trên: tự chừa thanh vuốt về màn hình
      // chính để nút Xác nhận không dính mép dưới.
      padding: EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        0,
        WebTuiSpacing.lg,
        WebTuiSpacing.lg + MediaQuery.viewPaddingOf(sheetContext).bottom,
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
          // Lời tóm tắt do IDE gửi: lọc ký tự ẩn / đảo chiều, cắt ngắn, cuộn
          // trong khung thấp để không che dòng do app tự ghi bên dưới.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.25,
            ),
            child: SingleChildScrollView(
              child: Text(
                ideStepSummaryText(summary),
                style: IdeType.bodyMedium.copyWith(color: IdeWb.textStrong),
              ),
            ),
          ),
          // Tên thao tác và đối tượng lấy từ yêu cầu của chính app (phần được
          // ký), không chỉ lời tóm tắt do IDE gửi.
          if (summary.summary.isNotEmpty) ...[
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              tr(
                'Thao tác: ${ideStepOpLabel(summary.op)}',
                'Action: ${ideStepOpLabelEn(summary.op)}',
              ),
              style: IdeType.bodySmall.copyWith(color: IdeWb.text),
            ),
          ],
          if (summary.target.isNotEmpty) ...[
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              tr(
                'Đối tượng: ${ideStepClip(ideVisibleText(summary.target), 200)}',
                'Target: ${ideStepClip(ideVisibleText(summary.target), 200)}',
              ),
              style: IdeType.bodySmall.copyWith(color: IdeWb.text),
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

/// Chữ chính của hộp: lời IDE (đã lọc, ≤ 500 ký tự) hoặc mã thao tác.
/// Giữ xuống dòng thật (lời nhiều dòng), các ký tự ẩn khác hiện thành mã.
String ideStepSummaryText(IdeStepSummary s) => s.summary.isEmpty
    ? s.op
    : ideStepClip(
        s.summary
            .replaceAll('\r\n', '\n')
            .split('\n')
            .map(ideVisibleText)
            .join('\n'),
        500,
      );

/// Cắt theo số ký tự (rune) để không cắt đôi ký tự ghép.
String ideStepClip(String s, int max) {
  final r = s.runes;
  return r.length <= max ? s : '${String.fromCharCodes(r.take(max))}…';
}

/// Tên dễ hiểu của thao tác cần vân tay; thao tác lạ thì giữ nguyên mã để người
/// dùng vẫn thấy đúng thứ app sắp ký.
String ideStepOpLabel(String op) => switch (op) {
  'ai.answer' => 'trả lời yêu cầu duyệt của AI',
  'files.purge' => 'xoá hẳn tệp trong thùng rác',
  'files.trash_purge' => 'dọn sạch thùng rác',
  'skills.install' => 'cài skill (ghi đè bản đang có)',
  'skills.update' => 'cập nhật skill (ghi đè bản đang có)',
  'skills.remove' => 'gỡ skill khỏi dự án',
  'skills.agent_install' => 'cài AI Agent (ghi đè bản đang có)',
  'skills.agent_update' => 'cập nhật AI Agent (ghi đè bản đang có)',
  'skills.agent_remove' => 'gỡ AI Agent khỏi dự án',
  'demo.enable' => 'bật web demo công khai',
  'demo.set' => 'đổi web demo thành công khai',
  'demo.disable' => 'tắt web demo',
  'demo.db_show' => 'xem mật khẩu database',
  'demo.db_drop' => 'xoá database demo',
  'servers.add' => 'thêm máy chủ',
  'servers.edit' => 'đổi thông tin đăng nhập máy chủ',
  'servers.remove' => 'gỡ máy chủ',
  'talk.share' => 'chia sẻ cuộc chat (mọi nhân viên đã đăng nhập mở được)',
  'devices.revoke' => 'gỡ điện thoại khác khỏi IDE',
  _ => op,
};

String ideStepOpLabelEn(String op) => switch (op) {
  'ai.answer' => 'answer the AI approval request',
  'files.purge' => 'permanently delete a trashed file',
  'files.trash_purge' => 'empty the trash',
  'skills.install' => 'install skill (overwrite existing)',
  'skills.update' => 'update skill (overwrite existing)',
  'skills.remove' => 'remove skill from the project',
  'skills.agent_install' => 'install AI agent (overwrite existing)',
  'skills.agent_update' => 'update AI agent (overwrite existing)',
  'skills.agent_remove' => 'remove AI agent from the project',
  'demo.enable' => 'turn on a public demo site',
  'demo.set' => 'make the demo site public',
  'demo.disable' => 'turn off the demo site',
  'demo.db_show' => 'view the database password',
  'demo.db_drop' => 'delete the demo database',
  'servers.add' => 'add a server',
  'servers.edit' => 'change server login details',
  'servers.remove' => 'remove a server',
  'talk.share' => 'share chat (any signed-in employee can open it)',
  'devices.revoke' => 'remove another phone from the IDE',
  _ => op,
};
