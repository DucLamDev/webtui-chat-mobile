import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_file_models.dart';
import '../ide_wb.dart';

/// Lời báo lỗi thân thiện theo mã lỗi của IDE.
String ideFilesErrorText(Object error) => switch (error) {
  IdeOffline() => tr(
    'IDE đang ngoại tuyến. Hãy thử lại khi đã kết nối.',
    'The IDE is offline. Try again when connected.',
  ),
  IdeForbidden(:final message) when message.isNotEmpty => message,
  IdeForbidden() => tr(
    'Bạn không có quyền làm việc này.',
    'You do not have permission for this.',
  ),
  IdeNotFound() => tr('Không tìm thấy tệp.', 'File not found.'),
  IdeTooLarge() => tr('Tệp quá lớn.', 'The file is too large.'),
  IdeUnsupported() => tr(
    'Không mở được loại tệp này trong app.',
    'This file type cannot be opened in the app.',
  ),
  IdeConflict() => tr('Tên này đã có.', 'That name already exists.'),
  IdeBusy() => tr('IDE đang bận, thử lại sau.', 'The IDE is busy, try later.'),
  IdeTimeout() => tr('Quá hạn chờ, thử lại.', 'Timed out, try again.'),
  IdeBadRequest() => tr('Yêu cầu không hợp lệ.', 'Invalid request.'),
  IdeStepFailed() => tr(
    'Chưa xác nhận được bằng vân tay.',
    'Fingerprint confirmation failed.',
  ),
  IdeCancelled() => tr('Đã huỷ.', 'Cancelled.'),
  _ => tr('Có lỗi, thử lại.', 'Something went wrong, try again.'),
};

/// Lỗi tên theo [IdeNameError] (null = hợp lệ).
String? ideNameErrorText(String name) => switch (ideCheckName(name)) {
  null => null,
  IdeNameError.empty => tr('Hãy nhập tên.', 'Enter a name.'),
  IdeNameError.slash => tr(
    'Tên không được có dấu / hoặc \\.',
    'The name cannot contain / or \\.',
  ),
  IdeNameError.dots => tr('Tên không hợp lệ.', 'Invalid name.'),
  IdeNameError.control => tr(
    'Tên có ký tự không hợp lệ.',
    'The name has invalid characters.',
  ),
  IdeNameError.tooLong => tr('Tên quá dài.', 'The name is too long.'),
};

void ideSnack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> ideCopyText(BuildContext context, String text, String note) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) ideSnack(context, note);
}

/// Màu chấm git; chữ cái đi kèm để không chỉ dựa vào màu.
Color ideGitColor(String git) => switch (git) {
  'M' => IdeWb.warn,
  'A' || '?' => IdeWb.ok,
  'D' => IdeWb.danger,
  'R' => IdeWb.accentInk,
  _ => IdeWb.text2,
};

String ideGitLabel(String git) => switch (git) {
  'M' => tr('Đã sửa', 'Modified'),
  'A' => tr('Mới thêm', 'Added'),
  '?' => tr('Chưa theo dõi', 'Untracked'),
  'D' => tr('Đã xoá', 'Deleted'),
  'R' => tr('Đổi tên', 'Renamed'),
  _ => '',
};

IconData ideEntryIcon(IdeFileEntry e) {
  if (e.secret) return Icons.lock_outline_rounded;
  if (e.isDir) return Icons.folder_rounded;
  if (e.type == IdeEntryType.link) return Icons.link_rounded;
  return switch (ideFileKindOf(e.name)) {
    IdeFileKind.image => Icons.image_outlined,
    IdeFileKind.video => Icons.movie_outlined,
    IdeFileKind.pdf => Icons.picture_as_pdf_outlined,
    IdeFileKind.office => Icons.description_outlined,
    IdeFileKind.markdown => Icons.article_outlined,
    IdeFileKind.other => Icons.insert_drive_file_outlined,
    IdeFileKind.code => Icons.code_rounded,
  };
}

/// Màu biểu tượng theo loại tệp (kiểu Working Copy / Files): nhìn là biết loại.
Color ideEntryTint(IdeFileEntry e) {
  if (e.secret) return IdeWb.text2;
  if (e.isDir) return IdeWb.accentInk;
  if (e.type == IdeEntryType.link) return IdeWb.text;
  return switch (ideFileKindOf(e.name)) {
    IdeFileKind.image => IdeWb.ok,
    IdeFileKind.video => const Color(0xFF8E5BD9),
    IdeFileKind.pdf => IdeWb.danger,
    IdeFileKind.office => const Color(0xFF2B7CD3),
    IdeFileKind.markdown => IdeWb.warn,
    IdeFileKind.code =>
      WebTuiColors.brightness == Brightness.dark
          ? const Color(0xFF8E8CFF)
          : const Color(0xFF5E5CE6),
    IdeFileKind.other => IdeWb.text,
  };
}

/// Ngày sửa gọn cho hàng tệp: "5 phút trước", "3 giờ trước", "12/11", năm
/// khác thì "12/11/2025".
String ideShortDate(int mtimeMs, {DateTime? now}) {
  if (mtimeMs <= 0) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(mtimeMs);
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (!d.isNegative && d.inHours < 24) {
    if (d.inMinutes < 1) return tr('vừa xong', 'just now');
    if (d.inMinutes < 60) {
      return tr('${d.inMinutes} phút trước', '${d.inMinutes} min ago');
    }
    return tr('${d.inHours} giờ trước', '${d.inHours} h ago');
  }
  String two(int v) => v.toString().padLeft(2, '0');
  final dm = '${two(t.day)}/${two(t.month)}';
  return t.year == n.year ? dm : '$dm/${t.year}';
}

String ideFormatDate(int mtimeMs) {
  if (mtimeMs <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(mtimeMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
