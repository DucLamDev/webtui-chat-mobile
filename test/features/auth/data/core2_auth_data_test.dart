import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/error_mapper.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/auth/application/use_cases/refresh_access_token_use_case.dart';
import 'package:webtui_chat/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:webtui_chat/features/auth/data/datasources/device_approval_remote_data_source.dart';
import 'package:webtui_chat/features/auth/data/datasources/qr_login_remote_data_source.dart';
import 'package:webtui_chat/features/auth/data/network/auth_refresh_interceptor.dart';
import 'package:webtui_chat/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:webtui_chat/features/auth/domain/entities/device_approval.dart';
import 'package:webtui_chat/features/auth/domain/entities/device_identity.dart';
import 'package:webtui_chat/features/auth/domain/entities/email_verification.dart';
import 'package:webtui_chat/features/auth/domain/entities/qr_login.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';

import '../support/core2_fakes.dart';

void main() {
  final instance = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: Uri.parse('https://chat.example.com'),
  );
  final guard = AuthTokenMutationGuard(
    instanceScopeId: instance.storageId,
    generation: 'generation-a',
  );

  group('AuthRefreshInterceptor', () {
    test('401 SESSION_REVOKED → xoá phiên ngay, không gọi refresh', () async {
      final tokens = MemoryTokenRepository(
        guard: guard,
        accessToken: 'token-a',
        refreshToken: 'refresh-a',
      );
      final auth = ScriptedAuthRepository();
      final revoked = <String?>[];
      final dio = _dio(instance, status: 401, body: _error('SESSION_REVOKED'));
      dio.interceptors.add(
        AuthRefreshInterceptor(
          dio: dio,
          expectedInstanceScope: instance,
          tokenRepository: tokens,
          refreshAccessTokenUseCase: RefreshAccessTokenUseCase(
            authRepository: auth,
            tokenRepository: tokens,
          ),
          onSessionRevoked: (failure, _) async => revoked.add(failure.code),
        ),
      );

      await expectLater(
        dio.get<Object>('/api/v1/users/me'),
        throwsA(isA<DioException>()),
      );

      expect(revoked, ['SESSION_REVOKED']);
      expect(auth.refreshCalls, 0);
      dio.close(force: true);
    });

    test('403 DEVICE_APPROVAL_PENDING → báo màn chờ duyệt', () async {
      final tokens = MemoryTokenRepository(guard: guard, accessToken: 'token');
      var pending = 0;
      final dio = _dio(
        instance,
        status: 403,
        body: _error('DEVICE_APPROVAL_PENDING'),
      );
      dio.interceptors.add(
        AuthRefreshInterceptor(
          dio: dio,
          expectedInstanceScope: instance,
          tokenRepository: tokens,
          refreshAccessTokenUseCase: RefreshAccessTokenUseCase(
            authRepository: ScriptedAuthRepository(),
            tokenRepository: tokens,
          ),
          onDeviceApprovalPending: () => pending++,
        ),
      );

      await expectLater(
        dio.get<Object>('/api/v1/workspaces'),
        throwsA(isA<DioException>()),
      );

      expect(pending, 1);
      dio.close(force: true);
    });
  });

  test('error mapper giữ error.details', () {
    final failure = mapDioExceptionToFailure(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response<Object>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 400,
          data: {
            'success': false,
            'error': {
              'code': 'EMAIL_CODE_INVALID',
              'message': 'Mã sai',
              'details': {'attempts_left': 2},
            },
          },
        ),
      ),
    );

    expect(failure.code, 'EMAIL_CODE_INVALID');
    expect(failure.details['attempts_left'], 2);
  });

  group('AuthRemoteDataSource', () {
    test('danh sách phiên đọc is_current, last_seen_at, approval', () async {
      final api = _FakeApi(
        gets: {
          '/api/v1/auth/sessions': {
            'data': {
              'sessions': [
                {
                  'id': 's1',
                  'device_name': 'iPhone',
                  'created_at': '2026-11-01T00:00:00Z',
                  'expires_at': '2026-12-01T00:00:00Z',
                  'is_current': true,
                  'last_seen_at': '2026-11-09T10:00:00Z',
                  'approval_status': 'approved',
                  'auth_method': 'qr',
                },
                {
                  'id': 's2',
                  'created_at': '2026-11-02T00:00:00Z',
                  'expires_at': '2026-12-01T00:00:00Z',
                  // Máy chủ cũ: không có trường mới.
                },
                {
                  'id': 's3',
                  'created_at': '2026-11-02T00:00:00Z',
                  'expires_at': '2026-12-01T00:00:00Z',
                  'is_current': 'true',
                  'approval_status': 'PENDING',
                },
              ],
            },
          },
        },
      );

      final sessions = await AuthRemoteDataSource(api).listSessions();

      expect(sessions[0].isCurrent, isTrue);
      expect(sessions[0].lastSeenAt, DateTime.utc(2026, 11, 9, 10));
      expect(sessions[0].authMethod, 'qr');
      expect(sessions[1].isCurrent, isFalse);
      expect(sessions[1].approvalStatus, 'approved');
      expect(sessions[1].lastActivityAt, sessions[1].createdAt);
      // Chỉ bool true mới là máy này.
      expect(sessions[2].isCurrent, isFalse);
      expect(sessions[2].isPendingApproval, isTrue);
    });

    test('đăng nhập trả approval_status pending', () async {
      final api = _FakeApi(
        posts: {
          '/api/v1/auth/login': {
            'data': {
              'auth': {
                'access_token': 'a',
                'refresh_token': 'r',
                'session_id': 's1',
                'approval_status': 'pending',
                'approval_expires_at': '2026-11-10T10:15:00Z',
              },
            },
          },
        },
      );

      final session = await AuthRemoteDataSource(api).login(
        identifier: 'lam',
        password: List.filled(12, 'x').join(),
        device: _device,
      );

      expect(session.isPendingApproval, isTrue);
      expect(session.approvalExpiresAt, DateTime.utc(2026, 11, 10, 10, 15));
    });

    test('đăng ký 202 verification_required → lỗi có phiếu xác minh', () async {
      final api = _FakeApi(
        posts: {
          '/api/v1/auth/register': {
            'data': {
              'verification_required': true,
              'verification': {
                'verification_id': 'ver_123',
                'email_hint': 'l***@congty.vn',
                'expires_at': '2026-11-10T10:15:00Z',
                'resend_available_at': '2026-11-10T10:01:00Z',
              },
            },
          },
        },
      );
      final repository = AuthRepositoryImpl(AuthRemoteDataSource(api));

      final result = await repository.register(
        displayName: 'Lâm',
        email: 'lam@congty.vn',
        username: 'lam',
        password: List.filled(12, 'x').join(),
        device: _device,
      );

      final failure = result.failureOrNull!;
      expect(failure.code, EmailVerificationErrorCode.required);
      final ticket = EmailVerificationTicket.fromJson(failure.details)!;
      expect(ticket.verificationId, 'ver_123');
      expect(ticket.emailHint, 'l***@congty.vn');
      expect(ticket.resendAvailableAt, DateTime.utc(2026, 11, 10, 10, 1));
    });
  });

  group('QR / duyệt thiết bị data source', () {
    test('quét QR gửi secret, đọc thông tin máy tính', () async {
      final payload = QrLoginPayload.tryParse(
        'vpsttt-login:v1?d=chat.example.com&c=chal_12345678&s=secretsecret123456',
      )!;
      final api = _FakeApi(
        posts: {
          '/api/v1/auth/qr/challenges/chal_12345678/scan': {
            'data': {
              'challenge_id': 'chal_12345678',
              'status': 'scanned',
              'expires_at': '2026-11-10T10:02:00Z',
              'requester': {
                'device_name': 'Windows - Chrome',
                'user_agent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/130',
                'ip_address': '203.0.113.5',
                'created_at': '2026-11-10T10:00:00Z',
              },
            },
          },
        },
      );

      final scan = await QrLoginRemoteDataSource(api).scan(payload);

      expect(api.lastData, {'secret': 'secretsecret123456'});
      expect(scan.requester.ipAddress, '203.0.113.5');
      expect(scan.requester.deviceName, 'Windows - Chrome');
    });

    test('đọc danh sách chờ duyệt và trạng thái của máy này', () async {
      final api = _FakeApi(
        gets: {
          '/api/v1/auth/device-approvals': {
            'data': [
              {
                'session_id': 'sess_1',
                'user': {'id': 'u1', 'display_name': 'Lâm'},
                'device_name': 'Android',
                'ip_address': '198.51.100.7',
                'my_role': 'self',
                'decisions': [],
              },
            ],
          },
          '/api/v1/auth/device-approvals/me': {
            'data': {
              'session_id': 'sess_9',
              'approval_status': 'pending',
              'mode': 'two_person',
              'required_roles': ['self', 'admin'],
              'decisions': [
                {'approver_role': 'self', 'decision': 'approve'},
              ],
              'has_trusted_device': true,
            },
          },
        },
      );
      final remote = DeviceApprovalRemoteDataSource(api);

      final items = await remote.listPending(DeviceApprovalScope.mine);
      expect(api.lastQuery, {'scope': 'mine'});
      final mine = await remote.mine();
      expect(items.single.sessionId, 'sess_1');
      expect(items.single.userDisplayName, 'Lâm');
      expect(mine.mode, 'two_person');
      expect(mine.decisions.single.isApproval, isTrue);
      expect(mine.requiredRoles, ['self', 'admin']);
    });
  });
}

const _device = DeviceIdentity(
  id: 'device-1',
  platform: 'android',
  displayName: 'Android',
);

Map<String, Object?> _error(String code) => {
  'success': false,
  'error': {'code': code, 'message': code},
};

Dio _dio(InstanceScope instance, {required int status, required Object body}) {
  return Dio(
    BaseOptions(baseUrl: instance.origin.toString(), followRedirects: false),
  )..httpClientAdapter = _StaticAdapter(status, body);
}

final class _StaticAdapter implements HttpClientAdapter {
  _StaticAdapter(this.status, this.body);

  final int status;
  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _FakeApi implements ApiTransport {
  _FakeApi({this.gets = const {}, this.posts = const {}});

  final Map<String, Object?> gets;
  final Map<String, Object?> posts;
  Object? lastData;
  Map<String, dynamic>? lastQuery;

  Response<T> _response<T>(String path, Map<String, Object?> table) {
    if (!table.containsKey(path)) {
      throw StateError('Unexpected path $path');
    }
    return Response<T>(
      data: table[path] as T,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    lastQuery = queryParameters;
    return _response<T>(path, gets);
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    lastData = data;
    return _response<T>(path, posts);
  }

  @override
  Future<Response<T>> put<T>(
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

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
