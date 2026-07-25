import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile app copy uses Vietnamese with diacritics', () {
    final violations = <_Violation>[];
    final root = Directory('lib');
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      for (final literal in _dartStringLiterals(source)) {
        if (_looksLikeUnaccentedVietnamese(literal.text)) {
          violations.add(_Violation(file.path, literal.text));
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: violations
          .map((item) => '${item.path}: "${item.preview}"')
          .join('\n'),
    );
  });
}

bool _looksLikeUnaccentedVietnamese(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return false;
  }
  final banned = _bannedUnaccentedVietnamesePatterns.any(
    (pattern) => pattern.hasMatch(text),
  );
  if (banned) {
    return true;
  }
  return false;
}

final _bannedUnaccentedVietnamesePatterns = [
  RegExp(r'\b[Kk]hong\b'),
  RegExp(r'\b[Cc]hua\b'),
  RegExp(r'\b[Dd]ang\b'),
  RegExp(r'\b[Dd]uoc\b'),
  RegExp(r'\b[Hh]ay\b'),
  RegExp(r'\b[Tt]hu lai\b'),
  RegExp(r'\b[Tt]ao\b'),
  RegExp(r'\b[Nn]hap\b'),
  RegExp(r'\b[Tt]ieu de\b'),
  RegExp(r'\b[Mm]o ta\b'),
  RegExp(r'\b[Uu]u tien\b'),
  RegExp(r'\b[Hh]uy\b'),
  RegExp(r'\b[Xx]oa\b'),
  RegExp(r'\b[Kk]iem tra\b'),
  RegExp(r'\b[Cc]ap nhat\b'),
  RegExp(r'\b[Bb]at buoc\b'),
  RegExp(r'\b[Dd]u lieu\b'),
  RegExp(r'\b[Tt]hiet bi\b'),
  RegExp(r'\b[Dd]ong bo\b'),
  RegExp(r'\b[Qq]uyen\b'),
  RegExp(r'\b[Tt]hanh vien\b'),
  RegExp(r'\b[Kk]enh\b'),
  RegExp(r'\b[Pp]hong ban\b'),
  RegExp(r'\b[Nn]ghiep vu\b'),
  RegExp(r'\b[Hh]ien\b'),
  RegExp(r'\b[Ll]oi\b'),
  RegExp(r'\b[Tt]hu hoi\b'),
  RegExp(r'\b[Dd]a duoc\b'),
  RegExp(r'\b[Dd]a tao\b'),
  RegExp(r'\b[Cc]huyen sang\b'),
  RegExp(r'\b[Uu]ng dung\b'),
  RegExp(r'\b[Cc]uoc tro chuyen\b'),
  RegExp(r'\b[Tt]in nhan\b'),
  RegExp(r'\b[Tt]ep dinh kem\b'),
  RegExp(r'\b[Nn]oi cai dat\b'),
  RegExp(r'\b[Nn]gu canh\b'),
  RegExp(r'\b[Xx]u ly\b'),
  RegExp(r'\b[Vv]an de\b'),
  RegExp(r'\b[Mm]ay chu\b'),
  RegExp(r'\b[Mm]ang yeu\b'),
  RegExp(r'\b[Gg]an nhat\b'),
  RegExp(r'\b[Bb]an hien tai\b'),
  RegExp(r'\b[Pp]hien ban\b'),
  RegExp(r'\b[Hh]o tro\b'),
  RegExp(r'\b[Ss]u dung\b'),
  RegExp(r'\b[Tt]iep tuc\b'),
];

Iterable<_StringLiteral> _dartStringLiterals(String source) sync* {
  var index = 0;
  while (index < source.length) {
    var isRaw = false;
    var quoteIndex = index;
    final char = source[index];
    if ((char == 'r' || char == 'R') &&
        index + 1 < source.length &&
        _isQuote(source[index + 1])) {
      isRaw = true;
      quoteIndex = index + 1;
    }
    if (!_isQuote(source[quoteIndex])) {
      index += 1;
      continue;
    }

    final quote = source[quoteIndex];
    final triple =
        quoteIndex + 2 < source.length &&
        source[quoteIndex + 1] == quote &&
        source[quoteIndex + 2] == quote;
    final delimiterLength = triple ? 3 : 1;
    final start = quoteIndex + delimiterLength;
    var cursor = start;
    while (cursor < source.length) {
      if (!isRaw && source[cursor] == r'\') {
        cursor += 2;
        continue;
      }
      if (triple) {
        if (cursor + 2 < source.length &&
            source[cursor] == quote &&
            source[cursor + 1] == quote &&
            source[cursor + 2] == quote) {
          yield _StringLiteral(source.substring(start, cursor));
          index = cursor + delimiterLength;
          break;
        }
      } else if (source[cursor] == quote) {
        yield _StringLiteral(source.substring(start, cursor));
        index = cursor + delimiterLength;
        break;
      }
      cursor += 1;
    }
    if (cursor >= source.length) {
      break;
    }
  }
}

bool _isQuote(String value) => value == '"' || value == "'";

final class _StringLiteral {
  const _StringLiteral(this.text);

  final String text;
}

final class _Violation {
  const _Violation(this.path, this.text);

  final String path;
  final String text;

  String get preview {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 96
        ? normalized
        : '${normalized.substring(0, 93)}...';
  }
}
