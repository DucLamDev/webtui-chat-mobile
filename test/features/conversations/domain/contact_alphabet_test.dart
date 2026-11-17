import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/contact_alphabet.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';

ContactSummary _c(String id, String name) => ContactSummary(
  userId: id,
  displayName: name,
  username: id,
  email: '$id@x.vn',
  status: 'active',
);

void main() {
  test('chữ cái nhóm: bỏ dấu, Đ thành D, số / lạ / rỗng thành #', () {
    expect(contactGroupLetter('Đức'), 'D');
    expect(contactGroupLetter('đức'), 'D');
    expect(contactGroupLetter('Ánh'), 'A');
    expect(contactGroupLetter('Ơn'), 'O');
    expect(contactGroupLetter('  lan'), 'L');
    // Dạng tổ hợp (NFD): E + dấu mũ + dấu sắc.
    expect(contactGroupLetter('Ến'), 'E');
    expect(contactGroupLetter('123'), contactOtherLetter);
    expect(contactGroupLetter('@bot'), contactOtherLetter);
    expect(contactGroupLetter(''), contactOtherLetter);
    expect(contactGroupLetter('   '), contactOtherLetter);
  });

  test('nhóm A–Z, # ở cuối, không phân biệt hoa thường', () {
    final groups = groupContactsAlphabetically([
      _c('1', '123'),
      _c('2', 'Đức'),
      _c('3', 'Ánh'),
      _c('4', 'an'),
      _c('5', 'Dũng'),
      _c('6', ''),
    ]);
    expect([for (final g in groups) g.letter], ['A', 'D', '#']);
    expect([for (final c in groups[0].contacts) c.userId], ['4', '3']);
    expect([for (final c in groups[1].contacts) c.userId], ['2', '5']);
    expect([for (final c in groups[2].contacts) c.userId], ['6', '1']);
  });

  test('tên trùng giữ thứ tự ban đầu; rỗng cho danh sách rỗng', () {
    final groups = groupContactsAlphabetically([
      _c('b', 'Bình'),
      _c('a', 'bình'),
      _c('c', 'BINH'),
    ]);
    expect(groups, hasLength(1));
    expect([for (final c in groups.single.contacts) c.userId], ['b', 'a', 'c']);
    expect(groupContactsAlphabetically(const []), isEmpty);
  });
}
