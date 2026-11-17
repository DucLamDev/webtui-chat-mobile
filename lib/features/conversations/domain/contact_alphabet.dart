import 'entities/conversation_summary.dart';

/// Nhóm đồng nghiệp theo chữ cái đầu của tên (A–Z, cuối cùng là "#").
final class ContactLetterGroup {
  const ContactLetterGroup(this.letter, this.contacts);

  final String letter;
  final List<ContactSummary> contacts;
}

/// Nhóm cho tên bắt đầu bằng số hoặc ký tự lạ.
const contactOtherLetter = '#';

const _fromMarks =
    'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ';
const _toBase =
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Bỏ dấu tiếng Việt (cả dạng tổ hợp NFD) và đưa về chữ thường.
String foldVietnamese(String input) {
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

/// Chữ cái nhóm của một tên: "Đức" → "D", "Ánh" → "A"; số / ký tự lạ / rỗng
/// → "#".
String contactGroupLetter(String name) {
  final folded = foldVietnamese(name.trim());
  if (folded.isEmpty) return contactOtherLetter;
  final first = folded.codeUnitAt(0);
  if (first >= 0x61 && first <= 0x7A) return String.fromCharCode(first - 32);
  return contactOtherLetter;
}

/// Xếp A–Z (không phân biệt hoa thường, bỏ dấu), nhóm "#" ở cuối. Trong nhóm
/// xếp theo tên đã bỏ dấu; tên trùng giữ thứ tự ban đầu (ổn định).
List<ContactLetterGroup> groupContactsAlphabetically(
  Iterable<ContactSummary> contacts,
) {
  final entries = <({ContactSummary contact, String key, int order})>[];
  var order = 0;
  for (final contact in contacts) {
    entries.add((
      contact: contact,
      key: foldVietnamese(contact.displayName.trim()),
      order: order++,
    ));
  }
  entries.sort((a, b) {
    final letterA = contactGroupLetter(a.contact.displayName);
    final letterB = contactGroupLetter(b.contact.displayName);
    if (letterA != letterB) {
      if (letterA == contactOtherLetter) return 1;
      if (letterB == contactOtherLetter) return -1;
      return letterA.compareTo(letterB);
    }
    final byKey = a.key.compareTo(b.key);
    return byKey != 0 ? byKey : a.order.compareTo(b.order);
  });
  final groups = <ContactLetterGroup>[];
  for (final entry in entries) {
    final letter = contactGroupLetter(entry.contact.displayName);
    if (groups.isEmpty || groups.last.letter != letter) {
      groups.add(ContactLetterGroup(letter, <ContactSummary>[]));
    }
    groups.last.contacts.add(entry.contact);
  }
  return groups;
}

/// Tên (đã bỏ dấu, chữ thường) có từ hai đồng nghiệp trở lên: dòng đó hiện
/// thêm email để phân biệt.
Set<String> duplicateContactNames(Iterable<ContactSummary> contacts) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final contact in contacts) {
    final key = foldVietnamese(contact.displayName.trim());
    if (!seen.add(key)) duplicates.add(key);
  }
  return duplicates;
}
