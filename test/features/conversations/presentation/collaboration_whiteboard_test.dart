import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/collaboration_whiteboard.dart';

void main() {
  testWidgets('chọn hình chữ nhật rồi kéo → lưu đúng JSON schema 2', (
    tester,
  ) async {
    final transport = _WhiteboardTransport(
      version: 3,
      content: {'background': 'grid'},
    );
    await _pumpBoard(tester, transport);
    expect(find.text('Bảng trắng · v3'), findsOneWidget);

    await tester.tap(find.byTooltip('Hình'));
    await tester.pump();
    await tester.tap(find.byTooltip('Hình chữ nhật'));
    await tester.pump();
    await tester.tap(find.byTooltip('Màu đỏ'));
    await tester.pump();
    await _drag(tester, const [(100, 60), (180, 100), (260, 150)]);
    await _settleSave(tester);

    expect(transport.puts, hasLength(1));
    final body = transport.puts.single;
    expect(body['expected_version'], 3);
    final content = body['content']! as Map<String, Object?>;
    expect(content['schema'], 2);
    expect(content['background'], 'grid');
    expect(content['strokes'], isEmpty);
    final rect = (content['elements']! as List).single as Map<String, Object?>;
    expect(rect['type'], 'rect');
    expect(rect['id'], matches(RegExp(r'^e-')));
    expect(rect['color'], '#dc2626');
    expect(rect['width'], 4);
    expect(rect['x'] as num, closeTo(100, 0.2));
    expect(rect['y'] as num, closeTo(60, 0.2));
    expect(rect['w'] as num, closeTo(160, 0.2));
    expect(rect['h'] as num, closeTo(90, 0.2));
    expect(find.text('Bảng trắng · v4'), findsOneWidget);
    expect(find.text('Đã lưu'), findsOneWidget);
  });

  testWidgets('409 → tải bản mới, áp lại nét vừa vẽ rồi lưu lại', (
    tester,
  ) async {
    final transport = _WhiteboardTransport(version: 3, content: {});
    await _pumpBoard(tester, transport);

    // Người khác lưu trước: máy chủ đã sang v4 với một nét của họ.
    transport
      ..version = 4
      ..content = {
        'schema': 2,
        'strokes': [
          {
            'id': 's-other',
            'color': '#9333ea',
            'width': 2,
            'points': [
              {'x': 400, 'y': 300},
              {'x': 500, 'y': 320},
            ],
          },
        ],
        'elements': <Object?>[],
      };

    await _drag(tester, const [(50, 50), (120, 80), (200, 90)]);
    await _settleSave(tester);

    expect(transport.puts, hasLength(2));
    expect(transport.puts.first['expected_version'], 3);
    final retry = transport.puts.last;
    expect(retry['expected_version'], 4);
    final strokes =
        (retry['content']! as Map<String, Object?>)['strokes']! as List;
    expect(strokes, hasLength(2));
    expect((strokes.first as Map)['id'], 's-other');
    expect((strokes.last as Map)['color'], '#2563eb');
    expect(((strokes.last as Map)['points'] as List).length, greaterThan(1));
    expect(find.text('Bảng trắng · v5'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('409 lặp lại → báo SnackBar, giữ thay đổi chờ lưu', (
    tester,
  ) async {
    final transport = _WhiteboardTransport(version: 1, content: {})
      ..alwaysConflict = true;
    await _pumpBoard(tester, transport);

    await _drag(tester, const [(50, 50), (200, 90)]);
    await _settleSave(tester);

    expect(transport.puts, hasLength(2));
    expect(
      find.textContaining('Bảng trắng vừa có người khác sửa'),
      findsOneWidget,
    );
    expect(find.text('Chưa lưu được'), findsOneWidget);

    // Thử lại ngay từ nút trên SnackBar.
    transport.alwaysConflict = false;
    await tester.tap(find.widgetWithText(SnackBarAction, 'Thử lại'));
    await _settleSave(tester);

    expect(transport.puts, hasLength(3));
    expect(
      ((transport.puts.last['content']! as Map)['strokes']! as List),
      hasLength(1),
    );
    expect(find.text('Đã lưu'), findsOneWidget);
  });

  testWidgets('mất mạng → báo lỗi, không mất nét, thử lại được', (
    tester,
  ) async {
    final transport = _WhiteboardTransport(version: 2, content: {})
      ..offline = true;
    await _pumpBoard(tester, transport);

    await _drag(tester, const [(60, 60), (160, 160)]);
    await _settleSave(tester);

    expect(find.textContaining('Mất kết nối'), findsOneWidget);
    expect(find.text('Chưa lưu được'), findsOneWidget);

    // SnackBar tự ẩn, nút "Lưu lại" ở chân bảng vẫn còn để thử lại.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    transport.offline = false;
    await tester.tap(find.text('Lưu lại'));
    await _settleSave(tester);

    final strokes =
        (transport.puts.last['content']! as Map<String, Object?>)['strokes']!
            as List;
    expect(strokes, hasLength(1));
    expect(transport.puts.last['expected_version'], 2);
  });

  testWidgets('tẩy xoá đúng phần tử được chạm, giữ nét còn lại', (
    tester,
  ) async {
    final transport = _WhiteboardTransport(
      version: 7,
      content: {
        'schema': 2,
        'strokes': [
          {
            'id': 's-keep',
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
            'id': 'e-rect',
            'type': 'rect',
            'x': 100,
            'y': 60,
            'w': 160,
            'h': 90,
            'color': '#2563eb',
            'width': 4,
          },
          {'id': 'e-future', 'type': 'sticky', 'text': 'Bản mới'},
        ],
      },
    );
    await _pumpBoard(tester, transport);

    await tester.tap(find.byTooltip('Tẩy'));
    await tester.pump();
    // Chạm vào lòng hình (xa viền) không xoá gì.
    await tester.tapAt(_at(tester, 180, 105));
    await _settleSave(tester);
    expect(transport.puts, isEmpty);

    await tester.tapAt(_at(tester, 100, 105));
    await _settleSave(tester);

    expect(transport.puts, hasLength(1));
    final content = transport.puts.single['content']! as Map<String, Object?>;
    expect((content['strokes']! as List).map((item) => (item as Map)['id']), [
      's-keep',
    ]);
    expect(content['elements'], [
      {'id': 'e-future', 'type': 'sticky', 'text': 'Bản mới'},
    ]);
  });

  testWidgets('hoàn tác / làm lại nét vẽ và lưu theo từng bước', (
    tester,
  ) async {
    final transport = _WhiteboardTransport(version: 1, content: {});
    await _pumpBoard(tester, transport);

    await _drag(tester, const [(300, 200), (350, 220), (420, 260)]);
    await _settleSave(tester);
    final drawn =
        ((transport.puts.last['content']! as Map)['strokes']! as List).single
            as Map;

    await tester.tap(find.byTooltip('Hoàn tác'));
    await _settleSave(tester);
    expect((transport.puts.last['content']! as Map)['strokes'], isEmpty);
    expect(transport.puts.last['expected_version'], 2);

    await tester.tap(find.byTooltip('Làm lại'));
    await _settleSave(tester);
    final redone =
        ((transport.puts.last['content']! as Map)['strokes']! as List).single
            as Map;
    expect(redone['id'], drawn['id']);
    expect(transport.puts, hasLength(3));
  });

  testWidgets('đặt biểu tượng và chữ tại chỗ chạm', (tester) async {
    final transport = _WhiteboardTransport(version: 1, content: {});
    await _pumpBoard(tester, transport);

    await tester.tap(find.byTooltip('Biểu tượng'));
    await tester.pump();
    await tester.tap(find.byTooltip('Nổi bật'));
    await tester.pump();
    await tester.tapAt(_at(tester, 400, 200));
    await _settleSave(tester);

    final icon =
        ((transport.puts.last['content']! as Map)['elements']! as List).single
            as Map;
    expect(icon['type'], 'icon');
    expect(icon['icon'], '⭐');
    expect(icon['size'], 48);
    expect(icon['x'] as num, closeTo(400, 0.2));
    expect(icon['y'] as num, closeTo(200, 0.2));

    await tester.tap(find.byTooltip('Chữ'));
    await tester.pump();
    await tester.tap(find.byTooltip('Màu xanh lá'));
    await tester.pump();
    await tester.tapAt(_at(tester, 120, 80));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Họp lúc 9 giờ');
    await tester.tap(find.text('Thêm'));
    await _settleSave(tester);

    final elements =
        (transport.puts.last['content']! as Map)['elements']! as List;
    final text = elements.last as Map;
    expect(text['type'], 'text');
    expect(text['text'], 'Họp lúc 9 giờ');
    expect(text['color'], '#16a34a');
    expect(text['x'] as num, closeTo(120, 0.2));
  });

  testWidgets('đóng bảng khi nét chưa kịp lưu vẫn gửi nốt lên máy chủ', (
    tester,
  ) async {
    final transport = _WhiteboardTransport(version: 1, content: {});
    await _pumpBoard(tester, transport);

    await _drag(tester, const [(100, 100), (300, 200)]);
    // Đóng ngay, chưa hết thời gian chờ lưu.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(transport.puts, hasLength(1));
    expect(
      ((transport.puts.single['content']! as Map)['strokes']! as List),
      hasLength(1),
    );
  });

  testWidgets('tab đang hiện mới tải bản mới định kỳ', (tester) async {
    final transport = _WhiteboardTransport(version: 1, content: {});
    await _pumpBoard(tester, transport, active: false);
    transport
      ..version = 2
      ..content = {
        'schema': 2,
        'strokes': <Object?>[],
        'elements': [
          {'id': 'e-1', 'type': 'icon', 'icon': '⭐', 'x': 10, 'y': 10},
        ],
      };

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Bảng trắng · v1'), findsOneWidget);
    final getsWhileHidden = transport.gets;

    await _pumpBoard(tester, transport, active: true, rebuildOnly: true);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(transport.gets, greaterThan(getsWhileHidden));
    expect(find.text('Bảng trắng · v2'), findsOneWidget);
  });
}

Future<void> _pumpBoard(
  WidgetTester tester,
  _WhiteboardTransport transport, {
  bool active = false,
  bool rebuildOnly = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiTransportProvider.overrideWithValue(transport)],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: CollaborationWhiteboard(
              workspaceId: 'ws-1',
              channelId: 'ch-1',
              active: active,
            ),
          ),
        ),
      ),
    ),
  );
  if (!rebuildOnly) await tester.pumpAndSettle();
}

Offset _at(WidgetTester tester, double x, double y) {
  final rect = tester.getRect(find.byKey(const ValueKey('whiteboard-canvas')));
  return Offset(
    rect.left + x / 800 * rect.width,
    rect.top + y / 420 * rect.height,
  );
}

Future<void> _drag(WidgetTester tester, List<(double, double)> points) async {
  final gesture = await tester.startGesture(
    _at(tester, points.first.$1, points.first.$2),
  );
  for (final (x, y) in points.skip(1)) {
    await gesture.moveTo(_at(tester, x, y));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

Future<void> _settleSave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

/// Máy chủ giả: giữ một tài liệu whiteboard, kiểm `expected_version` như
/// backend thật (sai → 409 DOCUMENT_VERSION_CONFLICT).
final class _WhiteboardTransport implements ApiTransport {
  _WhiteboardTransport({required this.version, required this.content});

  int version;
  Map<String, Object?> content;
  bool alwaysConflict = false;
  bool offline = false;
  int gets = 0;
  final puts = <Map<String, Object?>>[];

  Map<String, Object?> _document() => {
    'channel_id': 'ch-1',
    'kind': 'whiteboard',
    'content': jsonDecode(jsonEncode(content)),
    'version': version,
    'updated_at': '2026-11-02T10:00:00Z',
  };

  Response<T> _ok<T>(String path, Object data) => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: {'success': true, 'data': data} as T,
  );

  DioException _conflict(String path) {
    final options = RequestOptions(path: path);
    return DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
        requestOptions: options,
        statusCode: 409,
        data: {
          'success': false,
          'error': {
            'code': 'DOCUMENT_VERSION_CONFLICT',
            'message': 'document version conflict',
          },
        },
      ),
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    expect(path, endsWith('/documents/whiteboard'));
    gets++;
    return _ok<T>(path, _document());
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final body =
        jsonDecode(jsonEncode(data)) as Map<String, Object?>; // bản sao sâu
    puts.add(body);
    if (offline) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    if (alwaysConflict || body['expected_version'] != version) {
      throw _conflict(path);
    }
    version++;
    content = body['content']! as Map<String, Object?>;
    return _ok<T>(path, _document());
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError(path);

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError(path);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError(path);
}
