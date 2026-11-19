import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_term.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/ide_screen.dart';

void main() {
  test('terminal bị tắt: tab vẫn hiện để báo, bật thì cần op term.*', () {
    const off = IdeReady(ops: {'ai.sessions'}, features: {'terminal': false});
    expect(visibleIdeTabs(off), contains(IdeTab.terminal));
    expect(
      visibleIdeTabs(const IdeReady(ops: {'ai.sessions'})),
      isNot(contains(IdeTab.terminal)),
    );
    expect(
      visibleIdeTabs(const IdeReady(ops: {'term.list'})),
      contains(IdeTab.terminal),
    );
  });

  test('Ctrl + chữ = mã điều khiển', () {
    expect(IdeTermKeys.ctrl('c'), '\x03');
    expect(IdeTermKeys.ctrl('C'), '\x03');
    expect(IdeTermKeys.ctrl('d'), '\x04');
    expect(IdeTermKeys.ctrl('z'), '\x1a');
    expect(IdeTermKeys.ctrl('['), '\x1b');
    expect(IdeTermKeys.ctrl('1'), isNull);
    expect(IdeTermKeys.ctrl('ab'), isNull);
  });

  test('Ctrl dính: bấm Ctrl rồi chữ, xong tự nhả', () {
    final m = IdeTermModifiers()..ctrl = true;
    expect(m.applyTyped('c'), '\x03');
    expect(m.ctrl, isFalse);
    expect(m.applyTyped('c'), 'c');
  });

  test('Ctrl dính không đụng chuỗi dài (dán) hay chữ không có mã', () {
    final m = IdeTermModifiers()..ctrl = true;
    expect(m.applyTyped('hello'), 'hello');
    expect(m.ctrl, isTrue);
    expect(m.applyTyped('5'), '5');
    expect(m.ctrl, isFalse);
  });

  test('Alt = ESC + phím; Ctrl+Alt cùng lúc', () {
    final m = IdeTermModifiers()..alt = true;
    expect(m.applyTyped('f'), '\x1bf');
    expect(m.alt, isFalse);
    m
      ..ctrl = true
      ..alt = true;
    expect(m.applyTyped('b'), '\x1b\x02');
  });

  test('mũi tên theo xterm, có chế độ ứng dụng và bổ trợ', () {
    expect(IdeTermKeys.arrow('up'), '\x1b[A');
    expect(IdeTermKeys.arrow('down'), '\x1b[B');
    expect(IdeTermKeys.arrow('right'), '\x1b[C');
    expect(IdeTermKeys.arrow('left'), '\x1b[D');
    expect(IdeTermKeys.arrow('up', appCursor: true), '\x1bOA');
    expect(IdeTermKeys.arrow('left', mod: 5), '\x1b[1;5D');
    expect(IdeTermKeys.arrow('right', mod: 3), '\x1b[1;3C');
  });

  test('Home / End / PgUp / PgDn theo xterm', () {
    expect(IdeTermKeys.home(), '\x1b[H');
    expect(IdeTermKeys.end(), '\x1b[F');
    expect(IdeTermKeys.home(appCursor: true), '\x1bOH');
    expect(IdeTermKeys.end(appCursor: true), '\x1bOF');
    expect(IdeTermKeys.pageUp(), '\x1b[5~');
    expect(IdeTermKeys.pageDown(), '\x1b[6~');
    expect(IdeTermKeys.pageUp(mod: 5), '\x1b[5;5~');
    expect(IdeTermKeys.esc, '\x1b');
    expect(IdeTermKeys.tab, '\t');
  });

  test('applyKey dùng bổ trợ hiện có rồi nhả', () {
    final m = IdeTermModifiers()..ctrl = true;
    expect(m.applyKey((mod) => IdeTermKeys.arrow('up', mod: mod)), '\x1b[1;5A');
    expect(m.ctrl, isFalse);
  });

  test('cắt khối tin ≤ 64 KB, không cắt giữa ký tự, ghép lại đủ', () {
    final text = 'ệ' * 50000;
    final chunks = ideTermChunks(text);
    expect(chunks.length, greaterThanOrEqualTo(3));
    for (final c in chunks) {
      expect(c.length, lessThanOrEqualTo(ideTermMaxChunk));
    }
    expect(utf8.decode([for (final c in chunks) ...c]), text);
    expect(ideTermChunks(''), isEmpty);
  });

  test('tên phiên, mở phiên, kẹp cỡ', () {
    expect(ideTermNameOk('a-b_c.1'), isTrue);
    expect(ideTermNameOk('a b'), isFalse);
    expect(ideTermNameOk('../x'), isFalse);
    expect(ideTermNameOk('a' * 65), isFalse);
    expect(IdeTermItem.tryParse({'name': '../x'}), isNull);
    expect(ideTermCols(5), 20);
    expect(ideTermCols(900), 500);
    expect(ideTermRows(1), 5);
    expect(ideTermRows(900), 200);
    expect(ideTermCmd(IdeTermKind.mySsh, 'h1'), 'my-ssh:h1');
    expect(ideTermCmd(IdeTermKind.ssh, 'h1'), 'ssh:h1');
  });

  test('phân tích term.list và term.targets', () {
    final items = parseIdeTermItems({
      'items': [
        {'name': 'a', 'root': '/srv/du-an', 'cmd': 'claude', 'attached': true},
        {'name': 'b', 'root': '/x/y/', 'cmd': 'ssh:h'},
        'rác',
      ],
    });
    expect(items, hasLength(2));
    expect(items[0].project, 'du-an');
    expect(items[0].attached, isTrue);
    expect(items[1].project, 'y');
    final t = IdeTermTargets.parse({
      'ssh': [
        {'alias': 'h1', 'label': 'Máy 1'},
      ],
      'my_ssh': [
        {'alias': 'm'},
      ],
    });
    expect(t.ssh.single.label, 'Máy 1');
    expect(t.mySsh.single.label, 'm');
  });
}
