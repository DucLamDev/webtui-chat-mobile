import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_ready.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_session_state.dart';

Map<String, Object?> _state({List<Map<String, Object?>>? messages}) => {
  'revision': 5,
  'title': 'Phiên',
  'messages':
      messages ??
      [
        {'id': 'm1', 'text': 'Xin '},
        {'id': 'm2', 'text': 'b'},
      ],
};

Map<String, Object?> _patch(
  Map<String, Object?> body, {
  int base = 5,
  int rev = 6,
}) => {'type': 'patch', 'base': base, 'revision': rev, ...body};

void main() {
  IdeSessionState fresh() => IdeSessionState()..applyState(_state());

  test('chữ chảy: nối thêm theo textFrom', () {
    final s = fresh();
    final r = s.applyPatch(
      _patch({
        'lists': {
          'messages': {
            'items': [
              {'id': 'm1', 'textFrom': 4, 'text': 'chào'},
            ],
          },
        },
      }),
    );
    expect(r, IdePatchResult.applied);
    expect(s.view.messages.first['text'], 'Xin chào');
    expect(s.revision, 6);
  });

  test('số vô cực (1e999) trong patch: bỏ qua, không ném', () {
    final s = fresh();
    final r = s.applyPatch(
      jsonDecode('{"type":"patch","base":1e999,"revision":1e999}')
          as Map<String, Object?>,
    );
    expect(r, isNot(IdePatchResult.applied));
    final r2 = s.applyPatch(
      _patch({
        'lists': {
          'messages': {
            'items': [
              jsonDecode('{"id":"m1","textFrom":1e999,"text":"x"}')
                  as Map<String, Object?>,
            ],
          },
        },
      }),
    );
    expect(r2, isNot(IdePatchResult.applied));
    expect(s.revision, 5);
  });

  test('nối hai lần liên tiếp', () {
    final s = fresh();
    s.applyPatch(
      _patch({
        'lists': {
          'messages': {
            'items': [
              {'id': 'm2', 'textFrom': 1, 'text': 'ạn'},
            ],
          },
        },
      }),
    );
    s.applyPatch(
      _patch(base: 6, rev: 7, {
        'lists': {
          'messages': {
            'items': [
              {'id': 'm2', 'textFrom': 3, 'text': ' ơi'},
            ],
          },
        },
      }),
    );
    expect(s.view.messages[1]['text'], 'bạn ơi');
    expect(s.revision, 7);
  });

  test('textFrom tính theo UTF-16: emoji chiếm 2 đơn vị', () {
    final s = IdeSessionState()
      ..applyState(
        _state(
          messages: [
            {'id': 'm1', 'text': 'Hi 😀'},
          ],
        ),
      );
    final r = s.applyPatch(
      _patch({
        'lists': {
          'messages': {
            'items': [
              {'id': 'm1', 'textFrom': 5, 'text': ' Việt'},
            ],
          },
        },
      }),
    );
    expect(r, IdePatchResult.applied);
    expect(s.view.messages.first['text'], 'Hi 😀 Việt');
  });

  test('xoá khoá và đặt khoá', () {
    final s = fresh();
    s.applyPatch(
      _patch({
        'set': {'status': 'busy'},
        'del': ['title'],
      }),
    );
    expect(s.raw['status'], 'busy');
    expect(s.raw.containsKey('title'), isFalse);
  });

  test('đổi thứ tự bằng order, mục full thêm mới', () {
    final s = fresh();
    final r = s.applyPatch(
      _patch({
        'lists': {
          'messages': {
            'order': ['m3', 'm2', 'm1'],
            'items': [
              {
                'full': {'id': 'm3', 'text': 'đầu'},
              },
            ],
          },
        },
      }),
    );
    expect(r, IdePatchResult.applied);
    expect([for (final m in s.view.messages) m['id']], ['m3', 'm2', 'm1']);
  });

  test('lệch revision thì phải đăng ký lại và không đổi state', () {
    final s = fresh();
    final r = s.applyPatch(
      _patch(base: 4, {
        'set': {'status': 'x'},
      }),
    );
    expect(r, IdePatchResult.needsResubscribe);
    expect(s.raw.containsKey('status'), isFalse);
    expect(s.revision, 5);
  });

  test('chưa có state thì patch đòi đăng ký lại', () {
    expect(
      IdeSessionState().applyPatch(
        _patch({
          'set': {'a': 1},
        }),
      ),
      IdePatchResult.needsResubscribe,
    );
  });

  test('id trùng: patch theo mục không áp được, state giữ nguyên', () {
    final s = IdeSessionState()
      ..applyState(
        _state(
          messages: [
            {'id': 'd', 'text': 'a'},
            {'id': 'd', 'text': 'b'},
          ],
        ),
      );
    final r = s.applyPatch(
      _patch({
        'lists': {
          'messages': {
            'items': [
              {'id': 'd', 'textFrom': 1, 'text': 'x'},
            ],
          },
        },
      }),
    );
    expect(r, IdePatchResult.needsResubscribe);
    expect(s.view.messages.map((m) => m['text']), ['a', 'b']);
  });

  test('patch trỏ mục không có hoặc textFrom quá dài thì đăng ký lại', () {
    final s = fresh();
    expect(
      s.applyPatch(
        _patch({
          'lists': {
            'messages': {
              'items': [
                {'id': 'zz', 'textFrom': 0, 'text': 'x'},
              ],
            },
          },
        }),
      ),
      IdePatchResult.needsResubscribe,
    );
    expect(
      s.applyPatch(
        _patch({
          'lists': {
            'messages': {
              'items': [
                {'id': 'm1', 'textFrom': 99, 'text': 'x'},
              ],
            },
          },
        }),
      ),
      IdePatchResult.needsResubscribe,
    );
  });

  test('khung ready có protocol vô cực: coi như 0, không ném', () {
    final ready = IdeReady.fromFrame(
      jsonDecode('{"type":"ready","protocol":1e999,"ops":["files.list"]}')
          as Map<String, Object?>,
    );
    expect(ready.protocol, 0);
    expect(ready.hasOp('files.list'), isTrue);
  });
}
