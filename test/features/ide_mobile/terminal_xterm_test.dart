import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_term.dart';
import 'package:xterm/xterm.dart';

String lineText(Terminal t, int y) =>
    t.buffer.lines[t.buffer.scrollBack + y].getText().trimRight();

/// Ghi byte qua bộ giải mã UTF-8 cắt khúc rồi vào xterm (như luồng thật).
void feed(Terminal t, IdeTermUtf8Decoder d, List<int> bytes) =>
    t.write(d.decode(bytes));

void main() {
  test('chữ tiếng Việt bị cắt giữa hai khung vẫn ghép đúng', () {
    final t = Terminal(maxLines: 200)..resize(40, 10);
    final d = IdeTermUtf8Decoder();
    const text = 'Xin chào, Việt Nam ơi ệ 😀';
    final bytes = utf8.encode(text);
    // Cắt từng byte: mọi vị trí cắt đều rơi vào giữa ký tự nhiều byte.
    for (final b in bytes) {
      feed(t, d, [b]);
    }
    expect(lineText(t, 0), text);
  });

  test('cắt khúc ở mọi vị trí cho cùng kết quả', () {
    final bytes = utf8.encode('Tiếng Việt: ắ ằ ẳ ẵ ặ đ Đ ư ơ');
    for (var i = 1; i < bytes.length; i++) {
      final t = Terminal()..resize(60, 5);
      final d = IdeTermUtf8Decoder();
      feed(t, d, bytes.sublist(0, i));
      feed(t, d, bytes.sublist(i));
      expect(lineText(t, 0), 'Tiếng Việt: ắ ằ ẳ ẵ ặ đ Đ ư ơ', reason: 'cắt $i');
    }
  });

  test('byte sai thành ký tự thay thế, không làm hỏng phần sau', () {
    final t = Terminal()..resize(20, 5);
    final d = IdeTermUtf8Decoder();
    feed(t, d, [0x61, 0xff, 0x62]);
    expect(lineText(t, 0), 'a�b');
  });

  test('256 màu và màu thật', () {
    final t = Terminal()..resize(40, 5);
    t.write(
      '\x1b[38;5;196mA\x1b[48;5;21mB\x1b[0m\x1b[38;2;10;20;30mC\x1b[31mD',
    );
    final line = t.buffer.lines[t.buffer.scrollBack];
    final a = line.getForeground(0);
    expect(a & CellColor.typeMask, CellColor.palette);
    expect(a & CellColor.valueMask, 196);
    final b = line.getBackground(1);
    expect(b & CellColor.typeMask, CellColor.palette);
    expect(b & CellColor.valueMask, 21);
    final c = line.getForeground(2);
    expect(c & CellColor.typeMask, CellColor.rgb);
    expect(c & CellColor.valueMask, 0x0a141e);
    final d = line.getForeground(3);
    expect(d & CellColor.typeMask, CellColor.named);
    expect(d & CellColor.valueMask, NamedColor.red);
  });

  test('kiểu top / htop: màn phụ, vị trí con trỏ, xoá dòng, quay về', () {
    final t = Terminal()..resize(30, 8);
    t.write('lenh truoc\r\n');
    t.write('\x1b[?1049h\x1b[2J\x1b[H'); // vào màn phụ
    expect(t.isUsingAltBuffer, isTrue);
    t.write('\x1b[1;1Htop - 10:00');
    t.write('\x1b[3;5HCPU 12%');
    t.write('\x1b[2;1H\x1b[7mPID  USER\x1b[0m');
    t.write('\x1b[3;5H\x1b[K\x1b[32mCPU 99%\x1b[0m');
    expect(lineText(t, 0), 'top - 10:00');
    expect(lineText(t, 1), 'PID  USER');
    expect(lineText(t, 2), 'CPU 99%'); // ô trống đầu dòng không có chữ
    expect(t.buffer.cursorX, 11);
    expect(t.buffer.cursorY, 2);
    t.write('\x1b[?25l'); // ẩn con trỏ
    expect(t.cursorVisibleMode, isFalse);
    t.write('\x1b[?1049l'); // thoát: màn chính trở lại
    expect(t.isUsingAltBuffer, isFalse);
    expect(lineText(t, 0), 'lenh truoc');
  });

  test('cuộn: nhiều dòng đẩy dòng đầu vào lịch sử, vẫn đọc lại được', () {
    final t = Terminal(maxLines: 100)..resize(20, 5);
    for (var i = 0; i < 30; i++) {
      t.write('dòng $i\r\n');
    }
    expect(t.buffer.scrollBack, greaterThan(20));
    expect(t.buffer.lines[0].getText().trimRight(), 'dòng 0');
    expect(lineText(t, 3), 'dòng 29');
  });
}
