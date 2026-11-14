import '../../domain/entities/work_hub.dart';
import 'shared_file_logic.dart';

/// Tên do máy / điện thoại tự đặt, không có nghĩa với người xem: `voice-1794…`,
/// `image_picker_088CD997…`, `IMG_2024…`, `PXL_…`, `20261111_141500`, hay chuỗi
/// ngẫu nhiên dài không khoảng trắng (`2aOboRBTenk…`).
bool isMachineFileName(String name) {
  final dot = name.lastIndexOf('.');
  final stem = (dot > 0 ? name.substring(0, dot) : name).trim();
  if (stem.isEmpty) return true;
  final lower = stem.toLowerCase();
  if (RegExp(
    r'^(voice|audio|recording|record|ghi[-_ ]?am)[-_ ]?\d',
  ).hasMatch(lower)) {
    return true;
  }
  if (RegExp(
    r'^(image_picker|img|vid|pxl|mvimg|screenshot|scaled|video)[-_]',
  ).hasMatch(lower)) {
    return true;
  }
  if (RegExp(r'^\d{8}[-_]\d{4,6}').hasMatch(lower)) return true;
  // Chuỗi dài liền mạch toàn chữ / số / gạch, trộn hoa thường hoặc nhiều số:
  // tên tệp tạm, mã băm.
  if (stem.length >= 20 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(stem)) {
    final digits = RegExp(r'\d').allMatches(stem).length;
    final upper = RegExp(r'[A-Z]').allMatches(stem).length;
    final lowerCount = RegExp(r'[a-z]').allMatches(stem).length;
    if (digits >= 4 || (upper >= 3 && lowerCount >= 3)) return true;
  }
  return false;
}

/// Tên hiện trên dòng tệp: tên máy tự đặt của ảnh / video / ghi âm thành
/// "Ảnh" / "Video" / "Ghi âm"; còn lại giữ tên gốc (cắt giữa nếu quá dài).
String sharedFileTitle(SharedFile file, {int maxLength = 40}) {
  final media = file.kind != SharedFileKind.document;
  if (media && isMachineFileName(file.name)) {
    return switch (file.kind) {
      SharedFileKind.image => 'Ảnh',
      SharedFileKind.video => 'Video',
      SharedFileKind.audio => 'Ghi âm',
      SharedFileKind.document => file.name,
    };
  }
  return shortenFileName(file.name, maxLength: maxLength);
}

/// Đuôi tệp in hoa ("DOCX", "PDF") hoặc rỗng.
String sharedFileExtensionLabel(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  final ext = name.substring(dot + 1);
  if (!RegExp(r'^[A-Za-z0-9]{1,6}$').hasMatch(ext)) return '';
  return ext.toUpperCase();
}

/// Thời lượng "0:42", "12:05", "1:02:03".
String sharedFileDurationText(int milliseconds) {
  final total = (milliseconds / 1000).round().clamp(0, 359999);
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Dòng phụ gọn: đuôi tài liệu, thời lượng video, kích thước, rồi giờ (nhóm
/// "Hôm nay" / "Hôm qua") hoặc ngày ("25/08", thêm năm nếu khác năm nay).
String sharedFileSubtitle(
  SharedFile file, {
  required bool showTime,
  required DateTime now,
}) {
  final local = file.createdAt.toLocal();
  final parts = <String>[
    if (file.kind == SharedFileKind.document)
      sharedFileExtensionLabel(file.name),
    if (file.durationMs case final duration?)
      if (file.kind == SharedFileKind.video ||
          file.kind == SharedFileKind.audio)
        sharedFileDurationText(duration),
    sharedFileSizeText(file.byteSize),
    if (showTime)
      '${_two(local.hour)}:${_two(local.minute)}'
    else if (local.year == now.toLocal().year)
      '${_two(local.day)}/${_two(local.month)}'
    else
      '${_two(local.day)}/${_two(local.month)}/${local.year}',
  ];
  return parts.where((part) => part.isNotEmpty).join(' · ');
}

/// Một nhóm tệp theo thời gian ("Hôm nay", "Tháng 10/2026"...).
final class SharedFileSection {
  const SharedFileSection({
    required this.title,
    required this.files,
    required this.showTime,
  });

  final String title;
  final List<SharedFile> files;

  /// Nhóm Hôm nay / Hôm qua: dòng tệp hiện giờ thay vì ngày.
  final bool showTime;
}

/// Xếp mới nhất trước rồi chia nhóm theo giờ địa phương: Hôm nay, Hôm qua,
/// Tháng này, rồi từng tháng cũ hơn ("Tháng 10/2026"). [byMonth]: chỉ chia theo
/// tháng (lưới Ảnh / Video, để mỗi hàng đủ ô).
List<SharedFileSection> groupSharedFiles(
  List<SharedFile> files,
  DateTime now, {
  bool byMonth = false,
}) {
  final localNow = now.toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final sorted = [...files]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final sections = <SharedFileSection>[];
  String? currentTitle;
  var currentFiles = <SharedFile>[];
  var currentShowTime = false;

  void flush() {
    final title = currentTitle;
    if (title != null && currentFiles.isNotEmpty) {
      sections.add(
        SharedFileSection(
          title: title,
          files: List.unmodifiable(currentFiles),
          showTime: currentShowTime,
        ),
      );
    }
  }

  for (final file in sorted) {
    final local = file.createdAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final (title, showTime) = !byMonth && !day.isBefore(today)
        ? ('Hôm nay', true)
        : !byMonth && !day.isBefore(yesterday)
        ? ('Hôm qua', true)
        : local.year == localNow.year && local.month == localNow.month
        ? ('Tháng này', false)
        : ('Tháng ${local.month}/${local.year}', false);
    if (title != currentTitle) {
      flush();
      currentTitle = title;
      currentFiles = <SharedFile>[];
      currentShowTime = showTime;
    }
    currentFiles.add(file);
  }
  flush();
  return sections;
}

/// Kích thước tệp dạng "1,2 MB".
String sharedFileSizeText(int bytes) {
  String format(double value, String unit) {
    final text = value.toStringAsFixed(value < 10 ? 1 : 0);
    return '${text.replaceAll('.', ',')} $unit';
  }

  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return format(kb, 'KB');
  final mb = kb / 1024;
  if (mb < 1024) return format(mb, 'MB');
  return format(mb / 1024, 'GB');
}

/// Số tệp theo từng loại (cho nhãn bộ lọc).
Map<SharedFileKind, int> countSharedFilesByKind(List<SharedFile> files) {
  final counts = <SharedFileKind, int>{};
  for (final file in files) {
    counts[file.kind] = (counts[file.kind] ?? 0) + 1;
  }
  return counts;
}
