import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/text/search_text.dart';

void main() {
  test('bỏ dấu, chữ thường, gộp khoảng trắng (cả dạng dấu tổ hợp)', () {
    expect(normalizeSearchText('  Họp   GIAO\tban  Đức  '), 'hop giao ban duc');
    // "ệ" viết bằng e + dấu mũ + dấu nặng rời (NFD).
    expect(normalizeSearchText('Kệ hoạch'), 'ke hoach');
    expect(normalizeSearchText(''), '');
  });

  test('từ cần tìm: không trùng, bỏ rỗng, tối đa số từ', () {
    expect(searchTokens('Họp họp  giao ban'), ['hop', 'giao', 'ban']);
    expect(searchTokens('   '), isEmpty);
    expect(searchTokens('a b c d', maxTokens: 2), ['a', 'b']);
  });

  test('thoát ký tự đại diện của LIKE', () {
    expect(escapeLikePattern(r'50%_a\b'), r'50\%\_a\\b');
  });
}
