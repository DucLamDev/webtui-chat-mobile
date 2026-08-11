import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/auth/application/legal_acceptance_access_policy.dart';
import 'package:webtui_chat/features/auth/data/interceptors/legal_acceptance_interceptor.dart';

void main() {
  test('policy blocks UGC mutations but preserves read and safety actions', () {
    final policy = LegalAcceptanceAccessPolicy();

    expect(policy.shouldBlock(_request('GET', '/messages')), isFalse);
    expect(policy.shouldBlock(_request('DELETE', '/messages/1')), isFalse);
    expect(
      policy.shouldBlock(
        _request('POST', '/api/v1/workspaces/w1/channels/c1/messages'),
      ),
      isTrue,
    );
    expect(
      policy.shouldBlock(
        _request('POST', '/api/v1/workspaces/w1/moderation/reports'),
      ),
      isFalse,
    );
    expect(
      policy.shouldBlock(_request('POST', '/api/v1/workspaces/w1/blocks')),
      isFalse,
    );
    expect(
      policy.shouldBlock(
        _request('POST', '/api/v1/workspaces/w1/calls/c1/accept'),
      ),
      isTrue,
    );
    expect(
      policy.shouldBlock(
        _request('POST', '/api/v1/workspaces/w1/calls/c1/reject'),
      ),
      isFalse,
    );
    expect(
      policy.shouldBlock(_request('PUT', '/api/v1/notifications/preferences')),
      isFalse,
    );
    policy.dispose();
  });

  test(
    'collaboration cleanup stays open while expansive variants stay gated',
    () {
      final policy = LegalAcceptanceAccessPolicy();
      const root = '/api/v1/workspaces/w1/channels/c1/collaboration';

      expect(
        policy.shouldBlock(
          _request('POST', '$root/voice-room/stop', data: const {}),
        ),
        isFalse,
      );
      expect(
        policy.shouldBlock(
          _request('POST', '$root/voice-room/start', data: const {}),
        ),
        isTrue,
      );
      expect(
        policy.shouldBlock(
          _request('POST', '$root/recordings/r1/stop', data: const {}),
        ),
        isFalse,
      );
      expect(
        policy.shouldBlock(
          _request('POST', '$root/recordings', data: const {}),
        ),
        isTrue,
      );
      expect(
        policy.shouldBlock(
          _request(
            'PUT',
            '$root/recording-policy',
            data: const {'enabled': false, 'provider': 'disabled'},
          ),
        ),
        isFalse,
      );
      expect(
        policy.shouldBlock(
          _request(
            'PUT',
            '$root/recording-policy',
            data: const {'enabled': true, 'provider': 'jibri'},
          ),
        ),
        isTrue,
      );
      expect(
        policy.shouldBlock(
          _request(
            'PUT',
            '$root/recordings/r1/consent',
            data: const {'consented': false},
          ),
        ),
        isFalse,
      );
      expect(
        policy.shouldBlock(
          _request(
            'PUT',
            '$root/recordings/r1/consent',
            data: const {'consented': true},
          ),
        ),
        isTrue,
      );
      expect(
        policy.shouldBlock(
          _request('PATCH', '$root/roles/u1', data: const {'role': 'listener'}),
        ),
        isFalse,
      );
      expect(
        policy.shouldBlock(
          _request(
            'PATCH',
            '$root/roles/u1',
            data: const {'role': 'moderator'},
          ),
        ),
        isTrue,
      );
      expect(
        policy.shouldBlock(
          _request(
            'PUT',
            '$root/breakouts/b1/assignments',
            data: const {'assigned_user_ids': <String>[]},
          ),
        ),
        isFalse,
      );
      expect(
        policy.shouldBlock(
          _request(
            'PUT',
            '$root/breakouts/b1/assignments',
            data: const {
              'assigned_user_ids': <String>['u1'],
            },
          ),
        ),
        isTrue,
      );

      const lockdown = {
        'room_mode': 'internal',
        'lobby_enabled': true,
        'chat_locked': true,
        'guest_microphone_enabled': false,
        'guest_camera_enabled': false,
        'default_participant_role': 'listener',
      };
      expect(
        policy.shouldBlock(_request('PUT', root, data: lockdown)),
        isFalse,
      );
      expect(
        policy.shouldBlock(
          _request('PUT', root, data: {...lockdown, 'chat_locked': false}),
        ),
        isTrue,
      );
      expect(
        policy.shouldBlock(
          _request('PUT', root, data: const {'chat_locked': true}),
        ),
        isTrue,
        reason: 'partial or malformed safety bodies must fail closed',
      );
      policy.dispose();
    },
  );

  test(
    'local guard rejects UGC before network and emits required event',
    () async {
      final policy = LegalAcceptanceAccessPolicy();
      final adapter = _Adapter(statusCode: 200, body: const {'success': true});
      final dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com'))
        ..httpClientAdapter = adapter
        ..interceptors.add(LegalAcceptanceInterceptor(policy));
      final required = Completer<void>();
      final subscription = policy.requiredEvents.listen((_) {
        if (!required.isCompleted) required.complete();
      });

      await expectLater(
        dio.post<Object>(
          '/api/v1/workspaces/w1/channels/c1/messages',
          data: const {'body': 'blocked'},
        ),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'status',
            409,
          ),
        ),
      );
      await required.future;

      expect(adapter.requests, 0);
      await subscription.cancel();
      dio.close(force: true);
      policy.dispose();
    },
  );

  test('backend 409 invalidates a previously complete policy', () async {
    final policy = LegalAcceptanceAccessPolicy()..markComplete();
    final adapter = _Adapter(
      statusCode: 409,
      body: const {
        'success': false,
        'error': {
          'code': 'LEGAL_ACCEPTANCE_REQUIRED',
          'message': 'Acceptance required.',
        },
      },
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://chat.example.com'))
      ..httpClientAdapter = adapter
      ..interceptors.add(LegalAcceptanceInterceptor(policy));
    final required = Completer<void>();
    final subscription = policy.requiredEvents.listen((_) {
      if (!required.isCompleted) required.complete();
    });

    await expectLater(
      dio.post<Object>('/api/v1/profile', data: const {'display_name': 'A'}),
      throwsA(isA<DioException>()),
    );
    await required.future;

    expect(adapter.requests, 1);
    expect(policy.canCreateUserContent, isFalse);
    await subscription.cancel();
    dio.close(force: true);
    policy.dispose();
  });
}

RequestOptions _request(String method, String path, {Object? data}) {
  return RequestOptions(
    baseUrl: 'https://chat.example.com',
    path: path,
    method: method,
    data: data,
  );
}

final class _Adapter implements HttpClientAdapter {
  _Adapter({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, Object?> body;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
