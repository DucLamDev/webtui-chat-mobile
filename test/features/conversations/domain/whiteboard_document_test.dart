import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/whiteboard_document.dart';

void main() {
  group('đọc dữ liệu', () {
    test(
      'dữ liệu web cũ (khung 800×420, không có schema) giữ nguyên toạ độ',
      () {
        final board = WhiteboardDocument.parse({
          'strokes': [
            {
              'color': '#dc2626',
              'points': [
                {'x': 120.5, 'y': 88},
                {'x': 300, 'y': 200},
              ],
            },
            {
              'color': '#2563eb',
              'points': [
                {'x': 0.5, 'y': 0.5},
              ],
            },
          ],
        });

        expect(board.strokes, hasLength(2));
        expect(board.strokes.first.id, 's-n0');
        expect(board.strokes.first.color, '#dc2626');
        expect(board.strokes.first.width, 4);
        expect(board.strokes.first.points, const [
          WhiteboardPoint(120.5, 88),
          WhiteboardPoint(300, 200),
        ]);
        expect(board.strokes[1].points, const [WhiteboardPoint(0.5, 0.5)]);
      },
    );

    test('dữ liệu app cũ chuẩn hoá 0–1 được đổi sang khung 800×420', () {
      final board = WhiteboardDocument.parse({
        'strokes': [
          {
            'color': '#2563eb',
            'points': [
              {'x': 0, 'y': 0},
              {'x': 0.5, 'y': 0.5},
            ],
          },
          {
            'color': '#2563eb',
            'points': [
              {'x': 1, 'y': 1},
            ],
          },
        ],
      });

      expect(board.strokes.first.points, const [
        WhiteboardPoint(0, 0),
        WhiteboardPoint(400, 210),
      ]);
      expect(board.strokes[1].points, const [WhiteboardPoint(800, 420)]);
    });

    test('schema 2 không bị coi là dữ liệu 0–1 dù toạ độ nhỏ', () {
      final board = WhiteboardDocument.parse({
        'schema': 2,
        'strokes': [
          {
            'id': 's-1',
            'color': '#111827',
            'width': 2,
            'points': [
              {'x': 0.5, 'y': 1},
            ],
          },
        ],
      });

      expect(board.strokes.single.points, const [WhiteboardPoint(0.5, 1)]);
      expect(board.strokes.single.width, 2);
    });

    test('đọc đủ các loại phần tử, kéo ngược được chuẩn hoá', () {
      final board = WhiteboardDocument.parse({
        'schema': 2,
        'strokes': <Object?>[],
        'elements': [
          {
            'id': 'e-1',
            'type': 'rect',
            'x': 100,
            'y': 60,
            'w': 160,
            'h': 90,
            'color': '#2563eb',
            'width': 4,
          },
          {
            'id': 'e-2',
            'type': 'ellipse',
            'x': 300,
            'y': 180,
            'w': 120,
            'h': -120,
            'color': '#16a34a',
            'width': 8,
          },
          {
            'id': 'e-3',
            'type': 'arrow',
            'x1': 50,
            'y1': 300,
            'x2': 250,
            'y2': 340,
            'color': '#111827',
            'width': 4,
          },
          {
            'id': 'e-4',
            'type': 'text',
            'x': 420,
            'y': 200,
            'text': 'Ghi chú',
            'color': '#111827',
            'size': 20,
          },
          {'id': 'e-5', 'type': 'icon', 'x': 600, 'y': 120, 'icon': '👍'},
        ],
      });

      expect(board.elements.map((element) => element.type), [
        'rect',
        'ellipse',
        'arrow',
        'text',
        'icon',
      ]);
      final ellipse = board.elements[1] as WhiteboardShape;
      expect(ellipse.kind, WhiteboardShapeKind.ellipse);
      expect([ellipse.x, ellipse.y, ellipse.w, ellipse.h], [300, 60, 120, 120]);
      expect((board.elements[4] as WhiteboardIcon).size, 48);
      expect(board.unknownElements, isEmpty);
    });

    test(
      'mặc định width / màu / cỡ và sinh id ổn định khi thiếu hoặc trùng',
      () {
        final content = <String, Object?>{
          'schema': 2,
          'strokes': [
            {
              'id': 'dup',
              'width': -3,
              'points': [
                {'x': 10, 'y': 10},
              ],
            },
            {
              'color': '#ea580c',
              'points': [
                {'x': 20, 'y': 20},
              ],
            },
          ],
          'elements': [
            {'type': 'rect', 'x': 1, 'y': 2, 'w': 3, 'h': 4},
            {'id': 'dup', 'type': 'text', 'text': 'A', 'x': 5, 'y': 6},
          ],
        };

        final first = WhiteboardDocument.parse(content);
        final second = WhiteboardDocument.parse(content);

        expect(first.strokes.first.id, 'dup');
        expect(first.strokes.first.color, whiteboardDefaultColor);
        expect(first.strokes.first.width, whiteboardDefaultStrokeWidth);
        expect(first.strokes[1].id, 's-n1');
        expect(first.elements.first.id, 'e-n0');
        expect(first.elements[1].id, 'e-n1');
        expect((first.elements[1] as WhiteboardText).size, 20);
        expect(
          second.strokes.map((stroke) => stroke.id),
          first.strokes.map((stroke) => stroke.id),
        );
        expect(
          second.elements.map((element) => element.id),
          first.elements.map((element) => element.id),
        );
      },
    );
  });

  group('ghi dữ liệu', () {
    test(
      'giữ khoá cấp trên lạ, phần tử lạ, nét sai và khoá lạ trong phần tử',
      () {
        final saved = WhiteboardDocument.parse({
          'schema': 2,
          'background': 'grid',
          'owner': {'name': 'Lan'},
          'strokes': [
            {
              'id': 's-1',
              'color': '#dc2626',
              'width': 8,
              'opacity': 0.5,
              'points': [
                {'x': 1.04, 'y': 2.06},
              ],
            },
            {'id': 's-2', 'color': '#dc2626', 'points': <Object?>[]},
            'rác',
          ],
          'elements': [
            {'id': 'e-9', 'type': 'sticky', 'x': 1, 'y': 2, 'text': 'Bản mới'},
            {'id': 'e-10', 'type': 'rect', 'x': 1, 'y': 2},
            {
              'id': 'e-11',
              'type': 'icon',
              'icon': '🔥',
              'x': 5,
              'y': 6,
              'rotation': 15,
            },
          ],
        }).toJson();

        expect(saved['background'], 'grid');
        expect(saved['owner'], {'name': 'Lan'});
        expect(saved['schema'], 2);
        expect(saved['strokes'], [
          {
            'opacity': 0.5,
            'id': 's-1',
            'color': '#dc2626',
            'width': 8,
            'points': [
              {'x': 1, 'y': 2.1},
            ],
          },
          {'id': 's-2', 'color': '#dc2626', 'points': <Object?>[]},
          'rác',
        ]);
        expect(saved['elements'], [
          {
            'rotation': 15,
            'id': 'e-11',
            'type': 'icon',
            'x': 5,
            'y': 6,
            'size': 48,
            'icon': '🔥',
          },
          {'id': 'e-9', 'type': 'sticky', 'x': 1, 'y': 2, 'text': 'Bản mới'},
          {'id': 'e-10', 'type': 'rect', 'x': 1, 'y': 2},
        ]);
      },
    );

    test('dữ liệu app cũ được ghi lại theo schema 2, toạ độ khung 800×420', () {
      final saved = WhiteboardDocument.parse({
        'strokes': [
          {
            'color': '#2563eb',
            'points': [
              {'x': 0.25, 'y': 0.5},
              {'x': 0.75, 'y': 0.5},
            ],
          },
        ],
      }).toJson();

      expect(jsonDecode(jsonEncode(saved)), {
        'schema': 2,
        'strokes': [
          {
            'id': 's-n0',
            'color': '#2563eb',
            'width': 4,
            'points': [
              {'x': 200, 'y': 210},
              {'x': 600, 'y': 210},
            ],
          },
        ],
        'elements': <Object?>[],
      });
    });

    test('xoá tất cả bỏ nét, phần tử (cả phần tử lạ) nhưng giữ khoá khác', () {
      final board = WhiteboardDocument.parse({
        'meta': 1,
        'strokes': [
          {
            'points': [
              {'x': 5, 'y': 5},
            ],
          },
        ],
        'elements': [
          {'type': 'sticky'},
        ],
      });

      expect(board.clear().toJson(), {
        'meta': 1,
        'schema': 2,
        'strokes': <Object?>[],
        'elements': <Object?>[],
      });
      expect(board.clear().isEmpty, isTrue);
    });
  });

  group('thao tác', () {
    final board = WhiteboardDocument.parse({
      'schema': 2,
      'strokes': [
        {
          'id': 's-1',
          'color': '#111827',
          'width': 4,
          'points': [
            {'x': 20, 'y': 300},
            {'x': 200, 'y': 300},
          ],
        },
      ],
      'elements': [
        {
          'id': 'rect',
          'type': 'rect',
          'x': 100,
          'y': 60,
          'w': 160,
          'h': 90,
          'color': '#2563eb',
        },
        {
          'id': 'ring',
          'type': 'ellipse',
          'x': 400,
          'y': 100,
          'w': 200,
          'h': 100,
          'color': '#16a34a',
        },
        {
          'id': 'arrow',
          'type': 'arrow',
          'x1': 300,
          'y1': 350,
          'x2': 500,
          'y2': 350,
          'color': '#111827',
        },
        {
          'id': 'note',
          'type': 'text',
          'x': 620,
          'y': 300,
          'text': 'Ghi chú',
          'color': '#111827',
          'size': 20,
        },
        {'id': 'like', 'type': 'icon', 'x': 700, 'y': 60, 'icon': '👍'},
      ],
    });

    test('hit test tìm đúng nét / phần tử trên cùng', () {
      expect(board.hitTest(const WhiteboardPoint(100, 303)), 's-1');
      expect(board.hitTest(const WhiteboardPoint(101, 100)), 'rect');
      expect(board.hitTest(const WhiteboardPoint(500, 101)), 'ring');
      expect(board.hitTest(const WhiteboardPoint(400, 352)), 'arrow');
      expect(board.hitTest(const WhiteboardPoint(640, 310)), 'note');
      expect(board.hitTest(const WhiteboardPoint(710, 70)), 'like');
      expect(board.hitTest(const WhiteboardPoint(10, 10)), isNull);
    });

    test('lòng hình chỉ tính khi chọn, tẩy chỉ trúng đường viền', () {
      const center = WhiteboardPoint(180, 105);
      expect(board.hitTest(center), isNull);
      expect(board.hitTest(center, shapeInteriors: true), 'rect');
      expect(
        board.hitTest(const WhiteboardPoint(500, 150), shapeInteriors: true),
        'ring',
      );
      expect(
        board.hitTest(const WhiteboardPoint(100, 300), includeStrokes: false),
        isNull,
      );
    });

    test('di chuyển phần tử và giữ trong khung', () {
      final moved = board.moveElement('rect', 50, 40);
      final rect = moved.elementById('rect')! as WhiteboardShape;
      expect([rect.x, rect.y, rect.w, rect.h], [150, 100, 160, 90]);

      final clamped = board.moveElement('like', 500, -500);
      final icon = clamped.elementById('like')! as WhiteboardIcon;
      expect([icon.x, icon.y], [776, 24]);

      final arrow =
          board.moveElement('arrow', 10, 5).elementById('arrow')!
              as WhiteboardArrow;
      expect([arrow.x1, arrow.y1, arrow.x2, arrow.y2], [310, 355, 510, 355]);
      expect(board.moveElement('missing', 1, 1), same(board));
    });

    test('thêm / xoá / thay theo id, áp lại lên bản mới vẫn đúng', () {
      const stroke = WhiteboardStroke(
        id: 's-new',
        color: '#dc2626',
        points: [WhiteboardPoint(1, 1), WhiteboardPoint(5, 5)],
      );
      final ops = <WhiteboardOp>[
        const WhiteboardAddOp(strokes: [stroke]),
        const WhiteboardRemoveOp({'ring'}),
        WhiteboardReplaceOp(board.elementById('rect')!.moveBy(10, 0)),
      ];
      // Bản mới của người khác: thêm một nét, đã xoá biểu tượng.
      final remote = board
          .add(
            strokes: const [
              WhiteboardStroke(
                id: 's-other',
                color: '#9333ea',
                points: [WhiteboardPoint(9, 9)],
              ),
            ],
          )
          .remove({'like'});

      var rebased = remote;
      for (final op in ops) {
        rebased = op.applyTo(rebased);
      }
      // Áp lại hai lần không nhân đôi nét.
      final twice = ops.fold(rebased, (doc, op) => op.applyTo(doc));

      expect(rebased.strokes.map((item) => item.id), [
        's-1',
        's-other',
        's-new',
      ]);
      expect(rebased.elements.map((item) => item.id), [
        'rect',
        'arrow',
        'note',
      ]);
      expect((rebased.elementById('rect')! as WhiteboardShape).x, 110);
      expect(twice.strokes, hasLength(3));
    });
  });

  group('lược điểm và kích thước', () {
    test('lược điểm gần trùng, giữ điểm đầu và cuối', () {
      final points = simplifyWhiteboardPoints(const [
        WhiteboardPoint(0, 0),
        WhiteboardPoint(0.5, 0),
        WhiteboardPoint(1, 0),
        WhiteboardPoint(2, 0),
        WhiteboardPoint(2.4, 0),
        WhiteboardPoint(5, 0),
        WhiteboardPoint(5.2, 0),
      ]);

      expect(points, const [
        WhiteboardPoint(0, 0),
        WhiteboardPoint(2, 0),
        WhiteboardPoint(5.2, 0),
      ]);
      expect(simplifyWhiteboardPoints(const [WhiteboardPoint(3, 3)]), const [
        WhiteboardPoint(3, 3),
      ]);
    });

    test('phát hiện bảng trắng vượt 500 KB', () {
      // Các điểm cách nhau 2 đơn vị để không bị lược khi ghi.
      final points = [
        for (var index = 0; index < 40000; index++)
          WhiteboardPoint((index * 2 % 800) + 0.5, 100.5),
      ];
      final big = WhiteboardDocument(
        strokes: [
          WhiteboardStroke(id: 's-1', color: '#111827', points: points),
        ],
      );
      final small = WhiteboardDocument(
        strokes: [
          WhiteboardStroke(
            id: 's-1',
            color: '#111827',
            points: points.take(10).toList(),
          ),
        ],
      );

      expect(big.encodedBytes, greaterThan(whiteboardMaxBytes));
      expect(big.isTooLarge, isTrue);
      expect(small.isTooLarge, isFalse);
    });

    test('id mới có tiền tố theo loại và không trùng', () {
      expect(createWhiteboardId('s'), matches(RegExp(r'^s-[0-9a-z]{10}$')));
      expect(createWhiteboardId('e'), isNot(createWhiteboardId('e')));
    });
  });
}
