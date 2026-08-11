import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:webtui_chat/features/auth/domain/entities/device_identity.dart';

void main() {
  test('registration sends explicit legal acceptance and versions', () async {
    final api = _RecordingApiTransport();
    final remote = AuthRemoteDataSource(api);

    await remote.register(
      displayName: 'Lâm',
      email: 'lam@example.com',
      username: 'lam',
      password: 'matkhau123',
      termsAccepted: true,
      termsVersion: '2026-08-07',
      privacyAccepted: true,
      privacyVersion: '2026-08-07',
      device: const DeviceIdentity(
        id: 'device-1',
        platform: 'android',
        displayName: 'Android',
      ),
    );

    expect(api.path, '/api/v1/auth/register');
    expect(api.data, containsPair('terms_accepted', true));
    expect(api.data, containsPair('terms_version', '2026-08-07'));
    expect(api.data, containsPair('privacy_accepted', true));
    expect(api.data, containsPair('privacy_version', '2026-08-07'));
  });

  test(
    'loads the current legal document versions from the public endpoint',
    () async {
      final api = _RecordingApiTransport();
      final remote = AuthRemoteDataSource(api);

      final versions = await remote.loadLegalDocumentVersions();

      expect(api.path, '/api/v1/auth/legal-documents');
      expect(versions.termsVersion, '2026-08-07');
      expect(versions.privacyVersion, '2026-08-07');
    },
  );

  test('loads authenticated existing-user legal acceptance', () async {
    final api = _RecordingApiTransport();
    final remote = AuthRemoteDataSource(api);

    final acceptance = await remote.loadLegalAcceptance(
      workspaceId: 'workspace-1',
    );

    expect(api.path, '/api/v1/auth/legal-acceptance');
    expect(api.queryParameters, {'workspace_id': 'workspace-1'});
    expect(acceptance.workspaceId, 'workspace-1');
    expect(acceptance.serverComplete, isFalse);
    expect(acceptance.terms.version, '2026-08-07');
    expect(acceptance.terms.accepted, isFalse);
    expect(acceptance.privacy.accepted, isTrue);
  });

  test('posts explicit current acceptance without backfill fields', () async {
    final api = _RecordingApiTransport();
    final remote = AuthRemoteDataSource(api);

    final acceptance = await remote.acceptLegalDocuments(
      workspaceId: 'workspace-1',
      termsVersion: '2026-08-07',
      privacyVersion: '2026-08-07',
    );

    expect(api.path, '/api/v1/auth/legal-acceptance');
    expect(api.data, <String, Object?>{
      'workspace_id': 'workspace-1',
      'terms_accepted': true,
      'terms_version': '2026-08-07',
      'privacy_accepted': true,
      'privacy_version': '2026-08-07',
    });
    expect(acceptance.isComplete, isTrue);
  });

  test('does not trust complete flags without accepted_at evidence', () async {
    final api = _RecordingApiTransport(
      legalGetPayload: _legalAcceptancePayload(
        complete: true,
        includeAcceptanceEvidence: false,
      ),
    );
    final remote = AuthRemoteDataSource(api);

    final acceptance = await remote.loadLegalAcceptance(
      workspaceId: 'workspace-1',
    );

    expect(acceptance.serverComplete, isTrue);
    expect(acceptance.terms.accepted, isTrue);
    expect(acceptance.terms.acceptedAt, isNull);
    expect(acceptance.privacy.acceptedAt, isNull);
    expect(acceptance.isComplete, isFalse);
  });
}

final class _RecordingApiTransport implements ApiTransport {
  _RecordingApiTransport({this.legalGetPayload});

  final Map<String, Object?>? legalGetPayload;
  String? path;
  Map<String, dynamic>? data;
  Map<String, dynamic>? queryParameters;

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    this.path = path;
    this.data = Map<String, dynamic>.from(data! as Map);
    this.queryParameters = queryParameters;
    if (path == '/api/v1/auth/legal-acceptance') {
      return Response<T>(
        data: _legalAcceptancePayload(complete: true) as T,
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
      );
    }
    return Response<T>(
      data:
          {
                'data': {
                  'auth': {
                    'access_token': 'access',
                    'refresh_token': 'refresh',
                    'session_id': 'session-1',
                  },
                },
              }
              as T,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    this.path = path;
    this.queryParameters = queryParameters;
    if (path == '/api/v1/auth/legal-acceptance') {
      return Response<T>(
        data:
            (legalGetPayload ?? _legalAcceptancePayload(complete: false)) as T,
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
      );
    }
    return Response<T>(
      data:
          {
                'success': true,
                'data': {
                  'documents': [
                    {
                      'document_type': 'terms',
                      'version': '2026-08-07',
                      'includes': ['terms_of_use', 'acceptable_use_policy'],
                    },
                    {
                      'document_type': 'privacy',
                      'version': '2026-08-07',
                      'includes': ['privacy_policy'],
                    },
                  ],
                },
              }
              as T,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}

Map<String, Object?> _legalAcceptancePayload({
  required bool complete,
  bool includeAcceptanceEvidence = true,
}) {
  return {
    'success': true,
    'data': {
      'legal_acceptance': {
        'workspace_id': 'workspace-1',
        'complete': complete,
        'terms': {
          'version': '2026-08-07',
          'accepted': complete,
          if (complete && includeAcceptanceEvidence)
            'accepted_at': '2026-08-07T08:00:00Z',
        },
        'privacy': {
          'version': '2026-08-07',
          'accepted': true,
          if (includeAcceptanceEvidence) 'accepted_at': '2026-08-07T08:00:00Z',
        },
      },
    },
  };
}
