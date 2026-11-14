import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/conversation_home_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/notice_bot_identity.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/notice_bot_read_only_bar.dart';
import 'package:webtui_chat/features/home/presentation/widgets/notification_bell.dart';
import 'package:webtui_chat/features/notifications/application/use_cases/channel_notification_preference_use_cases.dart';
import 'package:webtui_chat/features/notifications/data/datasources/notification_remote_data_source.dart';
import 'package:webtui_chat/features/notifications/data/repositories/channel_notification_preference_repository_impl.dart';
import 'package:webtui_chat/features/notifications/domain/entities/mobile_notification.dart';
import 'package:webtui_chat/features/notifications/presentation/controllers/channel_mute_controller.dart';
import 'package:webtui_chat/features/notifications/presentation/screens/notifications_route_screen.dart';

ConversationSummary _summary(String id, {bool bot = false}) =>
    ConversationSummary(
      id: id,
      workspaceId: 'ws',
      channelId: id,
      kind: ConversationKind.direct,
      title: 'Tên lưu',
      preview: '',
      updatedAt: DateTime.utc(2026, 11),
      noticeBot: bot,
    );

void main() {
  test('chuông chỉ còn khi máy chủ chưa có bot thông báo', () {
    expect(
      notificationBellActions(workspaceId: 'ws', noticeBot: true),
      isEmpty,
    );
    final old = notificationBellActions(workspaceId: 'ws', noticeBot: false);
    expect(old, hasLength(1));
    expect(old.single, isA<NotificationBellEntry>());
  });

  testWidgets('ô nhập được thay bằng dòng chỉ đọc', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NoticeBotReadOnlyBar())),
    );
    expect(find.text('Kênh thông báo, không trả lời được'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  test('tên chat bot dựng từ tên tổ chức, logo trống thì bỏ', () {
    final named = NoticeBotIdentity.fromOrganization(
      name: ' VPSTTT ',
      logoUrl: ' ',
    );
    expect(named.title, 'VPSTTT Bot');
    expect(named.logoUrl, isNull);
    expect(NoticeBotIdentity.fromOrganization().title, 'Bot thông báo');
  });

  test(
    'liên kết thông báo tìm đúng chat bot, không có thì về tab Tin nhắn',
    () {
      final state = ConversationHomeState(
        workspaceId: 'ws',
        conversations: [_summary('dm'), _summary('bot', bot: true)],
      );
      final bot = findNoticeBotConversation(state)!;
      expect(bot.channelId, 'bot');
      expect(
        noticeBotLocation(bot),
        startsWith('/conversations/bot?workspaceId=ws'),
      );
      expect(
        findNoticeBotConversation(
          ConversationHomeState(
            workspaceId: 'ws',
            conversations: [_summary('dm')],
          ),
        ),
        isNull,
      );
    },
  );

  group('tắt / bật thông báo chat bot', () {
    test('GET rồi PUT giữ các trường khác, chỉ đổi mode', () async {
      final api = _Api();
      final repo = ChannelNotificationPreferenceRepositoryImpl(
        NotificationRemoteDataSource(api),
      );
      final controller = ChannelMuteController.forTesting(
        key: const ChannelMuteKey(workspaceId: 'ws', channelId: 'ch 1'),
        loadUseCase: LoadChannelNotificationPreferenceUseCase(repo),
        setMutedUseCase: SetChannelNotificationMutedUseCase(repo),
      );
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.muted, isFalse);
      expect(await controller.toggle(), isTrue);
      expect(controller.state.muted, isTrue);

      expect(api.calls.first.method, 'GET');
      expect(
        api.calls.first.path,
        '/api/v1/notifications/preferences/channels/ch%201',
      );
      expect(api.calls.first.query, {'workspace_id': 'ws'});
      final put = api.calls.last;
      expect(put.method, 'PUT');
      expect(put.path, '/api/v1/notifications/preferences/channels/ch%201');
      final body = put.body! as Map<String, Object?>;
      expect(body['workspace_id'], 'ws');
      expect(body['mode'], 'muted');
      expect(body['important'], isTrue);
      expect(body['tags'], ['a']);

      expect(await controller.toggle(), isTrue);
      expect((api.calls.last.body! as Map)['mode'], 'all');
      expect(controller.state.muted, isFalse);
    });

    test('lỗi lưu hiện thông báo và giữ trạng thái cũ', () async {
      final api = _Api(failPut: true);
      final repo = ChannelNotificationPreferenceRepositoryImpl(
        NotificationRemoteDataSource(api),
      );
      final controller = ChannelMuteController.forTesting(
        key: const ChannelMuteKey(workspaceId: 'ws', channelId: 'ch'),
        loadUseCase: LoadChannelNotificationPreferenceUseCase(repo),
        setMutedUseCase: SetChannelNotificationMutedUseCase(repo),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(await controller.toggle(), isFalse);
      expect(controller.state.muted, isFalse);
      expect(controller.state.errorMessage, isNotNull);
      expect(controller.state.isSaving, isFalse);
    });

    test('use case từ chối kênh rỗng', () async {
      final repo = ChannelNotificationPreferenceRepositoryImpl(
        NotificationRemoteDataSource(_Api()),
      );
      final result = await SetChannelNotificationMutedUseCase(
        repo,
      ).execute(workspaceId: 'ws', channelId: ' ', muted: true);
      expect(result, isA<FailureResult<ChannelNotificationPreference>>());
    });
  });
}

final class _Call {
  _Call(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, dynamic>? query;
  final Object? body;
}

final class _Api implements ApiTransport {
  _Api({this.failPut = false});

  final bool failPut;
  final calls = <_Call>[];
  var _mode = 'all';

  Response<T> _json<T>(String path, Map<String, Object?> data) => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: {'data': data} as T,
  );

  Map<String, Object?> get _pref => {
    'workspace_id': 'ws',
    'channel_id': 'ch',
    'mode': _mode,
    'sensitive': false,
    'important': true,
    'compact': false,
    'tags': ['a'],
  };

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add(_Call('GET', path, queryParameters, null));
    return _json<T>(path, _pref);
  }

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add(_Call('PUT', path, queryParameters, data));
    if (failPut) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    _mode = (data! as Map)['mode']! as String;
    return _json<T>(path, _pref);
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
