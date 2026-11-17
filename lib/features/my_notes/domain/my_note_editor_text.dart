/// Văn bản trong ô soạn kiểu app Ghi chú iPhone: một ô duy nhất, DÒNG ĐẦU là
/// tiêu đề, phần còn lại là nội dung (markdown). Máy chủ vẫn lưu hai trường
/// `title` + `body` nên cần tách / ghép (Dart thuần, dễ test).
library;

import 'entities/my_note.dart';
import 'markdown/my_note_line_ops.dart';

/// Ghép tiêu đề + nội dung đã lưu thành văn bản của ô soạn.
String joinMyNoteEditorText(String title, String body) {
  final head = title.trim();
  if (head.isEmpty) return body;
  if (body.isEmpty) return head;
  return '$head\n$body';
}

/// Tách văn bản ô soạn: dòng có chữ đầu tiên (bỏ dấu `#` tiêu đề nếu người
/// dùng gõ) là tiêu đề, phần sau dòng đó là nội dung; dòng trống ở đầu bị bỏ.
/// Dòng đầu dài hơn giới hạn tiêu đề thì để tiêu đề trống, giữ cả văn bản
/// trong nội dung (không cắt giữa dòng; danh sách vẫn lấy dòng đầu làm tên).
({String title, String body}) splitMyNoteEditorText(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.trim().isEmpty) return (title: '', body: '');
  final newline = trimmed.indexOf('\n');
  final firstLine = newline < 0 ? trimmed : trimmed.substring(0, newline);
  final rest = newline < 0 ? '' : trimmed.substring(newline + 1);
  final title = firstLine.replaceFirst(RegExp(r'^#{1,3}\s+'), '').trim();
  if (title.length > MyNoteLimits.titleMaxLength) {
    return (title: '', body: trimmed);
  }
  return (title: title, body: rest);
}

/// Chuẩn hoá tag giống máy chủ: bỏ `#` đầu, gộp khoảng trắng, chữ thường.
String normalizeMyNoteTag(String value) {
  final trimmed = value.trim().replaceFirst(RegExp(r'^#+'), '');
  return trimmed
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ')
      .toLowerCase();
}

/// Tag của ghi chú KHÔNG nằm trong văn bản dạng `#tag` (tag đặt từ trước, có
/// thể có dấu cách). Giữ lại khi lưu để không mất tag cũ; tag gõ trong văn bản
/// thì xoá chữ là bỏ tag.
List<String> myNoteTagsOutsideText(List<String> noteTags, String editorText) {
  final inline = extractMyNoteInlineTags(editorText).toSet();
  return [
    for (final tag in noteTags)
      if (!inline.contains(normalizeMyNoteTag(tag))) normalizeMyNoteTag(tag),
  ].where((tag) => tag.isNotEmpty).toList(growable: false);
}

/// Tag lưu cùng ghi chú: tag đặt từ trước [otherTags] cộng tag gõ trong văn
/// bản (`#tag`).
List<String> myNoteEditorTags(String editorText, List<String> otherTags) =>
    mergeMyNoteTags(otherTags, extractMyNoteInlineTags(editorText));

/// Gộp tag (giữ thứ tự, bỏ trùng, bỏ tag rỗng / quá dài), tối đa
/// [MyNoteLimits.tagsMax].
List<String> mergeMyNoteTags(Iterable<String> first, Iterable<String> second) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in [...first, ...second]) {
    final tag = normalizeMyNoteTag(raw);
    if (tag.isEmpty ||
        tag.length > MyNoteLimits.tagMaxLength ||
        tag.contains(',') ||
        !seen.add(tag)) {
      continue;
    }
    result.add(tag);
    if (result.length == MyNoteLimits.tagsMax) break;
  }
  return result;
}
