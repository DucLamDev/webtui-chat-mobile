import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_visible_text.dart';

void main() {
  test('ideVisibleText: chữ thường giữ nguyên, có dấu tiếng Việt', () {
    expect(ideVisibleText('Sửa lỗi gọi nhỡ'), 'Sửa lỗi gọi nhỡ');
  });

  test('ideVisibleText: lộ ký tự đảo chiều, vô hình, xuống dòng', () {
    expect(
      ideVisibleText('uploads/anh\u202Egpj.php'),
      'uploads/anh<U+202E>gpj.php',
    );
    expect(ideVisibleText('a\u200Bb'), 'a<U+200B>b');
    expect(ideVisibleText('a\nb\u2028c\u0085d'), 'a⏎b⏎c⏎d');
    expect(ideVisibleText('a\u0000b'), 'a<U+0000>b');
  });
}
