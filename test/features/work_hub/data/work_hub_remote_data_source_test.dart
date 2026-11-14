import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/work_hub/data/datasources/work_hub_remote_data_source.dart';
import 'package:webtui_chat/features/work_hub/domain/entities/work_hub.dart';

const _shortcut = {
  'id': 's1',
  'workspace_id': 'w1',
  'title': 'Máy chủ',
  'url': 'https://panel.example.com',
  'icon': 'server',
  'color': 'violet',
  'position': 2,
};

void main() {
  test('stream-link: POST đúng đường dẫn, đọc dạng bọc và không bọc', () async {
    final wrapped = _Transport({
      'data': {
        'url': '/api/v1/media/workspaces/w1/files/f 1/stream?token=abc',
        'expires_at': '2026-11-14T10:15:00Z',
      },
    });
    final link = await WorkHubRemoteDataSource(
      wrapped,
    ).createFileStreamLink(workspaceId: 'w1', fileId: 'f 1');
    expect(
      wrapped.calls.single.line,
      'POST /api/v1/workspaces/w1/files/f%201/stream-link',
    );
    expect(link.url, contains('/stream?token=abc'));
    expect(link.expiresAt, DateTime.utc(2026, 11, 14, 10, 15));

    final bare = _Transport({'url': '/x/stream?token=1'});
    final plain = await WorkHubRemoteDataSource(
      bare,
    ).createFileStreamLink(workspaceId: 'w1', fileId: 'f');
    expect(plain.url, '/x/stream?token=1');
    expect(plain.expiresAt, isNull);

    expect(
      WorkHubRemoteDataSource(
        _Transport({'data': {}}),
      ).createFileStreamLink(workspaceId: 'w1', fileId: 'f'),
      throwsFormatException,
    );
  });

  test('danh sách lối tắt: GET đúng đường dẫn, đọc can_manage', () async {
    final transport = _Transport({
      'data': {
        'shortcuts': [_shortcut],
        'can_manage': true,
      },
    });
    final result = await WorkHubRemoteDataSource(
      transport,
    ).listShortcuts(workspaceId: 'w 1');
    expect(
      transport.calls.single.line,
      'GET /api/v1/workspaces/w%201/shortcuts',
    );
    expect(result.canManage, isTrue);
    expect(result.shortcuts.single.title, 'Máy chủ');
    expect(result.shortcuts.single.icon, 'server');
    expect(result.shortcuts.single.color, 'violet');
    expect(result.shortcuts.single.position, 2);
  });

  test('thiếu can_manage là false, thiếu icon / màu là mặc định', () async {
    final transport = _Transport({
      'data': {
        'shortcuts': [
          {'id': 's1', 'title': 'A', 'url': 'https://a.example'},
        ],
      },
    });
    final result = await WorkHubRemoteDataSource(
      transport,
    ).listShortcuts(workspaceId: 'w1');
    expect(result.canManage, isFalse);
    expect(result.shortcuts.single.icon, 'link');
    expect(result.shortcuts.single.color, 'blue');
  });

  test(
    'thêm, sửa, xoá, sắp xếp lối tắt: phương thức, đường dẫn, thân',
    () async {
      final transport = _Transport({
        'data': {
          'shortcut': _shortcut,
          'shortcuts': [_shortcut],
        },
      });
      final api = WorkHubRemoteDataSource(transport);
      const draft = AppShortcutDraft(
        title: 'Máy chủ',
        url: 'https://panel.example.com',
        icon: 'server',
        color: 'violet',
      );

      final created = await api.createShortcut(workspaceId: 'w1', draft: draft);
      expect(created.id, 's1');
      await api.updateShortcut(
        workspaceId: 'w1',
        shortcutId: 's1',
        draft: draft,
      );
      await api.deleteShortcut(workspaceId: 'w1', shortcutId: 's1');
      final ordered = await api.reorderShortcuts(
        workspaceId: 'w1',
        ids: ['s2', 's1'],
      );
      expect(ordered.single.id, 's1');

      const base = '/api/v1/workspaces/w1/shortcuts';
      expect(transport.calls.map((call) => call.line), [
        'POST $base',
        'PATCH $base/s1',
        'DELETE $base/s1',
        'PUT $base/order',
      ]);
      const body = {
        'title': 'Máy chủ',
        'url': 'https://panel.example.com',
        'icon': 'server',
        'color': 'violet',
      };
      expect(transport.calls[0].data, body);
      expect(transport.calls[1].data, body);
      expect(transport.calls[2].data, isNull);
      expect(transport.calls[3].data, {
        'ids': ['s2', 's1'],
      });
    },
  );

  test('đếm việc của tôi đọc open / in_progress / done_7d', () async {
    final transport = _Transport({
      'data': {'open': 1, 'in_progress': 2, 'done_7d': 4},
    });
    final summary = await WorkHubRemoteDataSource(
      transport,
    ).assignedTaskSummary(workspaceId: 'w1');
    expect(
      transport.calls.single.line,
      'GET /api/v1/workspaces/w1/tasks/assigned/summary',
    );
    expect(summary.open, 1);
    expect(summary.inProgress, 2);
    expect(summary.doneLast7Days, 4);
  });

  test('lịch họp sắp tới: query days / limit, bỏ họp thiếu kênh', () async {
    final transport = _Transport({
      'data': {
        'meetings': [
          {
            'id': 'm1',
            'channel_id': 'c1',
            'channel_name': 'Nhóm Kỹ thuật',
            'title': 'Họp tuần',
            'starts_at': '2026-11-15T02:00:00Z',
            'ends_at': '2026-11-15T03:00:00Z',
            'status': 'active',
          },
          {'id': 'm2', 'title': 'Không kênh'},
        ],
      },
    });
    final meetings = await WorkHubRemoteDataSource(
      transport,
    ).upcomingMeetings(workspaceId: 'w1', days: 7, limit: 10);
    expect(
      transport.calls.single.line,
      'GET /api/v1/workspaces/w1/meetings/upcoming',
    );
    expect(transport.calls.single.query, {'days': 7, 'limit': 10});
    expect(meetings, hasLength(1));
    expect(meetings.single.isActive, isTrue);
    expect(meetings.single.channelName, 'Nhóm Kỹ thuật');
    expect(meetings.single.endsAt, isNotNull);
  });

  test('tệp chia sẻ: GET files có limit 100, phân loại theo mime', () async {
    final transport = _Transport({
      'data': {
        'files': [
          {
            'id': 'f1',
            'original_name': 'anh.png',
            'mime_type': 'image/png',
            'byte_size': 2048,
            'created_at': '2026-11-10T01:00:00Z',
          },
          {'id': 'f2', 'name': 'ghi-am.m4a', 'mime_type': 'audio/mp4'},
          {'id': 'f3', 'name': 'bao-cao.pdf', 'mime_type': 'application/pdf'},
        ],
      },
    });
    final files = await WorkHubRemoteDataSource(
      transport,
    ).listFiles(workspaceId: 'w1');
    expect(transport.calls.single.line, 'GET /api/v1/workspaces/w1/files');
    expect(transport.calls.single.query, {'limit': 100});
    expect(files.map((file) => file.kind), [
      SharedFileKind.image,
      SharedFileKind.audio,
      SharedFileKind.document,
    ]);
    expect(files.first.name, 'anh.png');
    expect(files.first.byteSize, 2048);
    // Thiếu trường ảnh nhỏ / cỡ / thời lượng: null (máy chủ cũ, video gửi từ bản cũ).
    expect(files[1].thumbnailUrl, isNull);
    expect(files[1].durationMs, isNull);
  });

  test(
    'tệp chia sẻ: đọc ảnh nhỏ, cỡ, thời lượng video khi máy chủ có',
    () async {
      final transport = _Transport({
        'data': {
          'files': [
            {
              'id': 'v1',
              'original_name': 'clip.mp4',
              'mime_type': 'video/mp4',
              'byte_size': 4096,
              'thumbnail_url': '/api/v1/workspaces/w1/files/v1/thumbnail',
              'width': 1280,
              'height': 720,
              'duration_ms': 42000,
            },
            {
              'id': 'v2',
              'original_name': 'cu.mp4',
              'mime_type': 'video/mp4',
              'thumbnail_url': '  ',
              'width': 0,
              'duration_ms': 'không phải số',
            },
          ],
        },
      });
      final files = await WorkHubRemoteDataSource(
        transport,
      ).listFiles(workspaceId: 'w1');
      expect(
        files.first.thumbnailUrl,
        '/api/v1/workspaces/w1/files/v1/thumbnail',
      );
      expect(files.first.width, 1280);
      expect(files.first.height, 720);
      expect(files.first.durationMs, 42000);
      expect(files.last.thumbnailUrl, isNull);
      expect(files.last.width, isNull);
      expect(files.last.durationMs, isNull);
    },
  );
}

final class _Call {
  const _Call(this.line, this.data, this.query);

  final String line;
  final Object? data;
  final Map<String, dynamic>? query;
}

final class _Transport implements ApiTransport {
  _Transport(this.body);

  final Object? body;
  final calls = <_Call>[];

  Future<Response<T>> _reply<T>(
    String method,
    String path,
    Object? data,
    Map<String, dynamic>? query,
  ) async {
    calls.add(_Call('$method $path', data, query));
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: body as T,
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('GET', path, null, queryParameters);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('POST', path, data, queryParameters);

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('PUT', path, data, queryParameters);

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('PATCH', path, data, queryParameters);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _reply('DELETE', path, data, queryParameters);
}
