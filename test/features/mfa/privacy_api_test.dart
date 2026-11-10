import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/auth/domain/entities/device_identity.dart';
import 'package:webtui_chat/features/auth/domain/repositories/device_identity_repository.dart';
import 'package:webtui_chat/features/conversations/data/dto/conversation_dto.dart';
import 'package:webtui_chat/features/conversations/data/repositories/secret_message_repository_impl.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/mfa/data/mfa_repository_impl.dart';

void main() {
  late Dio dio;
  late List<RequestOptions> requests;
  Object payload = {};
  setUp(() {
    requests = [];
    dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          handler.resolve(
            Response<Object>(
              requestOptions: request,
              data: {'data': payload},
              statusCode: 200,
            ),
          );
        },
      ),
    );
  });
  tearDown(() => dio.close(force: true));
  test(
    'reauth binds device, does not accept empty token, preserves password',
    () async {
      final repository = MfaRepositoryImpl(DioApiTransport(dio), _Device());
      payload = {'reauth_token': 'test-token'};
      final result = await repository.reauthenticate(
        method: 'password',
        value: '  test password  ',
      );
      expect(result.valueOrNull, 'test-token');
      expect(requests.single.headers['X-Device-ID'], 'device-1');
      expect(requests.single.data, {
        'method': 'password',
        'password': '  test password  ',
      });
      payload = {};
      expect(
        (await repository.reauthenticate(
          method: 'totp',
          value: '123456',
        )).isFailure,
        isTrue,
      );
    },
  );
  test(
    'secret reveal sends reauth and device headers with encoded scope',
    () async {
      final repository = SecretMessageRepositoryImpl(
        DioApiTransport(dio),
        _Device(),
      );
      payload = {'body': 'private text'};
      expect(
        (await repository.reveal('w/1', 'c/1', 'm/1', 'proof')).valueOrNull,
        'private text',
      );
      expect(
        requests.single.path,
        '/api/v1/workspaces/w%2F1/channels/c%2F1/messages/m%2F1/reveal',
      );
      expect(requests.single.headers['X-Reauth-Token'], 'proof');
      expect(requests.single.headers['X-Device-ID'], 'device-1');
    },
  );
  test('secret send is explicit and uses retry identity', () async {
    final repository = SecretMessageRepositoryImpl(
      DioApiTransport(dio),
      _Device(),
    );
    payload = {};
    expect(
      (await repository.send('w', 'c', 'private text', 'client-1')).isSuccess,
      isTrue,
    );
    expect(requests.single.data, {
      'body': 'private text',
      'secret': true,
      'kind': 'text',
      'client_message_id': 'client-1',
    });
    expect(requests.single.headers['Idempotency-Key'], 'client-1');
  });
  test('message DTO never imports secret plaintext into timeline model', () {
    final message = MessageDto.fromJson({
      'id': 'm',
      'workspace_id': 'w',
      'channel_id': 'c',
      'secret': true,
      'body': 'must discard',
      'expires_at': '2026-11-10T12:00:00Z',
    }).toDomain();
    expect(message.isSecret, isTrue);
    expect(message.body, isEmpty);
    expect(
      message.copyWith(isMine: true).expiresAt,
      DateTime.utc(2026, 11, 10, 12),
    );
  });
  test('expired event removes message using payload id', () {
    final event = ConversationRealtimeEventMapper.fromSocketData(
      {
        'type': 'MessageExpired',
        'payload': {'channel_id': 'c', 'message_id': 'm'},
      },
      fallbackWorkspaceId: 'w',
      fallbackChannelId: 'c',
    );
    expect(event!.type, ConversationRealtimeEventType.messageDeleted);
    expect(event.messageId, 'm');
  });
}

class _Device implements DeviceIdentityRepository {
  @override
  Future<DeviceIdentity> currentDevice() async => const DeviceIdentity(
    id: 'device-1',
    platform: 'android',
    displayName: 'Test',
  );
}
