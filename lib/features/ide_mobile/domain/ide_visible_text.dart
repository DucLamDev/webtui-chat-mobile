/// Chữ do người khác viết (tên tệp, tiêu đề PR, commit, tên việc) có thể chứa
/// ký tự vô hình hoặc đảo chiều chữ (U+202E…) để giả dạng, ví dụ
/// `anh<U+202E>gpj.php` hiện thành "anhphp.jpg". Hàm này đổi mọi ký tự điều
/// khiển / định dạng vô hình thành dạng nhìn thấy `<U+202E>`, xuống dòng thành
/// "⏎", để người duyệt thấy đúng chữ thật trước khi bấm thao tác.
String ideVisibleText(String raw) {
  if (!_bad.hasMatch(raw)) return raw;
  return raw.replaceAllMapped(_bad, (m) {
    final c = m[0]!;
    if (c == '\n' ||
        c == '\r' ||
        c == '\u2028' ||
        c == '\u2029' ||
        c == '\u0085') {
      return '⏎';
    }
    if (c == '\t') return ' ';
    final code = c.runes.first.toRadixString(16).toUpperCase().padLeft(4, '0');
    return '<U+$code>';
  });
}

final _bad = RegExp(
  r'[\u0000-\u001f\u007f-\u009f\u2028\u2029]|\p{Cf}',
  unicode: true,
);
