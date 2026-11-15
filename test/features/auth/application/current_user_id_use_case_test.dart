import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/auth/application/use_cases/current_user_id_use_case.dart';

String _jwt(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(claims)}.sig';
}

void main() {
  group('accessTokenUserId', () {
    test('đọc claim sub', () {
      expect(accessTokenUserId(_jwt({'sub': ' u-1 ', 'sid': 's'})), 'u-1');
    });

    test('token hỏng / thiếu sub thì null', () {
      expect(accessTokenUserId(null), isNull);
      expect(accessTokenUserId('abc'), isNull);
      expect(accessTokenUserId('a.!!!.c'), isNull);
      expect(accessTokenUserId(_jwt({'sid': 's'})), isNull);
    });
  });

  group('ResolveCurrentUserIdUseCase', () {
    test('lấy từ token trên máy, không gọi hồ sơ', () async {
      var profileCalls = 0;
      final useCase = ResolveCurrentUserIdUseCase(
        readAccessToken: () async => _jwt({'sub': 'u-token'}),
        loadProfileUserId: () async {
          profileCalls++;
          return 'u-profile';
        },
      );
      expect(await useCase.execute(), 'u-token');
      expect(profileCalls, 0);
    });

    test('không có token thì mới tải hồ sơ', () async {
      final useCase = ResolveCurrentUserIdUseCase(
        readAccessToken: () async => null,
        loadProfileUserId: () async => 'u-profile',
      );
      expect(await useCase.execute(), 'u-profile');
    });

    test('kho token và hồ sơ cùng lỗi thì null', () async {
      final useCase = ResolveCurrentUserIdUseCase(
        readAccessToken: () async => throw StateError('kho lỗi'),
        loadProfileUserId: () async => throw StateError('mạng lỗi'),
      );
      expect(await useCase.execute(), isNull);
    });
  });
}
