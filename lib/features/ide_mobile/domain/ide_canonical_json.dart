import 'dart:convert';

import 'package:crypto/crypto.dart';

/// JSON chuẩn của hợp đồng IDE (mục 5): khoá object xếp theo thứ tự byte UTF-8
/// tăng dần ở mọi cấp, không khoảng trắng, giữ nguyên ký tự ngoài ASCII, chỉ
/// escape `"` `\` và ký tự điều khiển < 0x20. Tương đương Python
/// `json.dumps(x, sort_keys=True, separators=(",",":"), ensure_ascii=False)`.
String ideCanonicalJson(Object? value) {
  final out = StringBuffer();
  _write(out, value);
  return out.toString();
}

void _write(StringBuffer out, Object? value) {
  if (value == null) {
    out.write('null');
  } else if (value is bool) {
    out.write(value ? 'true' : 'false');
  } else if (value is int) {
    out.write(value.toString());
  } else if (value is double) {
    // Hợp đồng cấm số thực trong tham số cần ký: Dart và Python in khác nhau
    // (`1e-7` / `1e-07`), chữ ký sẽ hỏng mà không rõ lý do.
    throw ArgumentError('Không dùng số thực trong JSON cần ký.');
  } else if (value is String) {
    _writeString(out, value);
  } else if (value is List) {
    out.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) out.write(',');
      _write(out, value[i]);
    }
    out.write(']');
  } else if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()
      ..sort(_compareUtf8);
    out.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) out.write(',');
      _writeString(out, keys[i]);
      out.write(':');
      _write(out, value[keys[i]]);
    }
    out.write('}');
  } else {
    throw ArgumentError('Kiểu ${value.runtimeType} không có trong JSON.');
  }
}

/// Thứ tự byte UTF-8 trùng thứ tự điểm mã (không phải thứ tự đơn vị UTF-16:
/// emoji đứng sau các ký tự U+E000..U+FFFF).
int _compareUtf8(String a, String b) {
  final x = a.runes.iterator;
  final y = b.runes.iterator;
  while (true) {
    final hasX = x.moveNext();
    final hasY = y.moveNext();
    if (!hasX || !hasY) {
      if (hasX == hasY) return 0;
      return hasX ? 1 : -1;
    }
    if (x.current != y.current) return x.current < y.current ? -1 : 1;
  }
}

void _writeString(StringBuffer out, String text) {
  out.write('"');
  for (final unit in text.codeUnits) {
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      default:
        if (unit < 0x20) {
          out.write('\\u00${unit.toRadixString(16).padLeft(2, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
}

/// Chuỗi ký của bắt tay (hợp đồng mục 4).
String ideAuthSigningString({
  required String nonce,
  required String stream,
  required String chatUser,
}) => 'webtui-ide-auth:v1|$nonce|$stream|$chatUser';

/// Chuỗi ký khoá xác nhận (hợp đồng mục 5). [op] / [args] là phần đang chờ
/// xác nhận; [req] và [challenge] lấy từ khung `need_step`.
String ideStepSigningString({
  required String stream,
  required String req,
  required String challenge,
  required String op,
  required Object? args,
}) {
  final canon = ideCanonicalJson({'op': op, 'args': args});
  final digest = sha256.convert(utf8.encode(canon)).toString();
  return 'webtui-ide-step:v1|$stream|$req|$challenge|$digest';
}
