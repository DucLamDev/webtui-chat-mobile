const _fromMarks =
    'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
const _toBase =
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Bỏ dấu tiếng Việt (cả dạng tổ hợp NFD) và đưa về chữ thường: "Đức Ánh" →
/// "duc anh".
String foldVietnameseText(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    // Dấu thanh / dấu mũ rời (U+0300–U+036F) bị bỏ.
    if (rune >= 0x0300 && rune <= 0x036F) continue;
    final char = String.fromCharCode(rune);
    final index = _fromMarks.indexOf(char);
    buffer.write(index >= 0 ? _toBase[index] : char);
  }
  return buffer.toString();
}

final _whitespace = RegExp(r'\s+');

/// Chữ dùng để tìm trên máy: bỏ dấu, chữ thường, gộp khoảng trắng. Lưu cột
/// `search_text` và chuẩn hoá chữ người dùng gõ bằng CÙNG hàm này để "hop"
/// tìm ra "Họp", "HỌP".
String normalizeSearchText(String input) {
  return foldVietnameseText(input).replaceAll(_whitespace, ' ').trim();
}

/// Các từ cần có trong tin khi tìm (đã chuẩn hoá, không trùng, tối đa
/// [maxTokens] từ): tin phải chứa đủ mọi từ, không cần đúng thứ tự.
List<String> searchTokens(String query, {int maxTokens = 8}) {
  final tokens = <String>[];
  for (final token in normalizeSearchText(query).split(' ')) {
    if (token.isEmpty || tokens.contains(token)) continue;
    tokens.add(token);
    if (tokens.length >= maxTokens) break;
  }
  return tokens;
}

/// Thoát `%`, `_`, `\` để chữ người dùng gõ không thành ký tự đại diện của
/// LIKE (dùng kèm `ESCAPE '\'`).
String escapeLikePattern(String value) {
  return value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
