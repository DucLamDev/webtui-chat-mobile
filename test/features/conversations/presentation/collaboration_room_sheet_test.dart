import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/collaboration_task_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/collaboration_room_sheet.dart';
import 'package:webtui_chat/features/workspace/domain/repositories/workspace_session_repository.dart';

// Bảng dựng cả 6 tab cùng lúc (IndexedStack): chỉ một tab lỗi bố cục là cả bảng
// trắng trơn, bấm ô nào ở tab Công việc cũng vậy. Mỗi tab phải mở ra có nội dung.
const _expectedTextByTab = {
  0: 'Sắp diễn ra',
  1: 'Họp video nhóm',
  2: 'Chưa có file, poll, task hoặc bản ghi.',
  3: 'Lưu biên bản',
  4: 'Vẽ bằng một ngón tay · tự lưu sau mỗi nét',
  5: 'Phòng chưa có việc nào',
};

void main() {
  for (final MapEntry(key: tab, value: expectedText)
      in _expectedTextByTab.entries) {
    testWidgets('mở bảng cộng tác ở tab $tab hiện nội dung, không lỗi vẽ', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiTransportProvider.overrideWithValue(_BackendLikeTransport()),
            workspaceSessionRepositoryProvider.overrideWithValue(
              _ActiveWorkspaceSession(),
            ),
            canManageWorkspaceChannelsProvider.overrideWithValue(false),
            listChannelMembersUseCaseProvider.overrideWithValue(
              ListChannelMembersUseCase(_NoMembersRepository()),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showCollaborationRoomSheet(
                      context,
                      workspaceId: 'ws-1',
                      channelId: 'ch-1',
                      title: 'Phòng dự án',
                      conversation: null,
                      initialTab: tab,
                    ),
                    child: const Text('Mở'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Phòng dự án'), findsWidgets);
      expect(find.text(expectedText), findsWidgets);
    });
  }
}

final class _BackendLikeTransport implements ApiTransport {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    if (path.endsWith('/users/me')) {
      expect(queryParameters, {'workspace_id': 'ws-1'});
    }
    return _ok<T>(path, _dataFor(path));
  }

  Object _dataFor(String path) {
    const now = '2026-11-02T10:00:00Z';
    if (path.endsWith('/collaboration')) {
      return {
        'channel_id': 'ch-1',
        'workspace_id': 'ws-1',
        'channel_name': 'Phòng dự án',
        'channel_type': 'public',
        'room_mode': 'group',
        'meeting_provider': 'jitsi',
        'meeting_base_url': 'https://meet.example.test',
        'meeting_room_key': 'room-key',
        'public_access_enabled': false,
        'has_password': false,
        'lobby_enabled': false,
        'chat_locked': false,
        'guest_microphone_enabled': true,
        'guest_camera_enabled': true,
        'default_participant_role': 'participant',
        'created_at': now,
        'updated_at': now,
      };
    }
    if (path.contains('/documents/')) {
      final kind = path.split('/').last;
      return {
        'channel_id': 'ch-1',
        'kind': kind,
        'content': <String, Object?>{},
        'version': 1,
        'updated_at': now,
      };
    }
    if (path.endsWith('/tasks')) return {'tasks': <Object>[]};
    if (path.endsWith('/roles')) return {'roles': <Object>[]};
    if (path.endsWith('/breakouts')) return {'breakout_rooms': <Object>[]};
    if (path.endsWith('/meetings')) return {'meetings': <Object>[]};
    if (path.endsWith('/shared-items')) return {'items': <Object>[]};
    if (path.endsWith('/recordings')) return {'recordings': <Object>[]};
    if (path.endsWith('/users/me')) {
      return {
        'user': {
          'id': 'u-1',
          'email': 'a@example.test',
          'username': 'a',
          'display_name': 'A',
        },
      };
    }
    return <String, Object?>{};
  }

  Response<T> _ok<T>(String path, Object data) => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: {'success': true, 'data': data} as T,
  );

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _ok<T>(path, <String, Object?>{});

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _ok<T>(path, <String, Object?>{});

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _ok<T>(path, <String, Object?>{});

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _ok<T>(path, <String, Object?>{});
}

/// Tab Task tải thành viên phòng để chọn người làm; ở đây phòng chưa có ai.
final class _NoMembersRepository implements ConversationRepository {
  @override
  Future<Result<List<ChannelMember>>> listMembers({
    required String workspaceId,
    required String channelId,
  }) async => const Success([]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Phòng đã mở trong workspace: không truy cập kho khóa native khi test widget.
final class _ActiveWorkspaceSession implements WorkspaceSessionRepository {
  @override
  Future<String?> readActiveWorkspaceId() async => 'ws-1';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
