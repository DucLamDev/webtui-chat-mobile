import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/conversations/data/files/scoped_attachment_file_store.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_file_providers.dart';

String _jwt(Map<String, Object?> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(payload)}.signature';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final serverA = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: Uri.parse('https://server-a.example'),
  );
  final serverB = InstanceScope(
    instanceId: '22222222-2222-4222-8222-222222222222',
    serverOrigin: Uri.parse('https://server-b.example'),
  );

  test(
    'khoá tài khoản lấy mã người dùng trong token, thiếu thì theo phiên',
    () {
      expect(
        mediaCacheAccountKey(
          accessToken: _jwt({'sub': 'user-1'}),
          sessionGeneration: 'gen-1',
        ),
        'user:user-1',
      );
      expect(
        mediaCacheAccountKey(
          accessToken: 'not-a-jwt',
          sessionGeneration: 'gen-1',
        ),
        'session:gen-1',
      );
      expect(
        mediaCacheAccountKey(accessToken: null, sessionGeneration: ' gen-2 '),
        'session:gen-2',
      );
    },
  );

  test('kho đệm tách theo máy chủ và tài khoản, không đổi khi mở lại app', () {
    String dir(InstanceScope scope, String account) =>
        scopedMediaCacheDirectoryRelativePath(
          instanceScope: scope,
          accountKey: account,
          purpose: 'image',
        );
    expect(dir(serverA, 'user:a'), dir(serverA, 'user:a'));
    expect(dir(serverA, 'user:a'), isNot(dir(serverA, 'user:b')));
    expect(dir(serverA, 'user:a'), isNot(dir(serverB, 'user:a')));
    expect(dir(serverA, 'user:a'), isNot(contains('user')));

    // Nằm trong thư mục của máy chủ (cùng gốc với kho theo phiên) nên đăng
    // xuất / đổi máy chủ (clearScope) xoá luôn.
    final sessionDir = scopedAttachmentDirectoryRelativePath(
      instanceScope: serverA,
      sessionGeneration: 'gen-1',
      purpose: 'image',
    );
    expect(
      path.split(dir(serverA, 'user:a')).take(2),
      path.split(sessionDir).take(2),
    );

    expect(
      () => scopedMediaCacheDirectoryRelativePath(
        instanceScope: serverA,
        accountKey: 'user:a',
        purpose: '../thoát',
      ),
      throwsArgumentError,
    );
    expect(
      () => scopedMediaCacheDirectoryRelativePath(
        instanceScope: serverA,
        accountKey: '  ',
        purpose: 'image',
      ),
      throwsArgumentError,
    );
  });

  test('tên tệp trong kho là mã băm, chỉ giữ đuôi an toàn', () {
    final name = scopedMediaCacheFileName(
      instanceScope: serverA,
      key: 'https://server-a.example/api/v1/files/file-1/download',
      originalName: 'báo cáo.PDF',
    );
    expect(name, endsWith('.pdf'));
    expect(name, isNot(contains('file-1')));
    expect(
      scopedMediaCacheFileName(
        instanceScope: serverA,
        key: 'k',
        originalName: 'x.p d f',
      ),
      isNot(contains('.')),
    );
    expect(
      scopedMediaCacheFileName(instanceScope: serverA, key: 'k'),
      isNot(scopedMediaCacheFileName(instanceScope: serverB, key: 'k')),
    );
  });

  group('trên máy', () {
    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('scoped-media-cache-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => temp.path,
          );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test(
      'đăng xuất / đổi máy chủ (clearScope) xoá kho đệm của máy chủ đó',
      () async {
        const store = ScopedAttachmentFileStore();
        final cached = await store.cacheFileFor(
          instanceScope: serverA,
          accountKey: 'user:a',
          purpose: 'image',
          key: 'https://server-a.example/a.jpg',
          originalName: 'a.jpg',
        );
        await cached.parent.create(recursive: true);
        await cached.writeAsString('jpg');
        final other = await store.cacheFileFor(
          instanceScope: serverB,
          accountKey: 'user:a',
          purpose: 'image',
          key: 'https://server-b.example/a.jpg',
        );
        await other.parent.create(recursive: true);
        await other.writeAsString('jpg');

        expect(cached.path.startsWith(temp.path), isTrue);
        await store.clearScope(serverA);

        expect(await cached.exists(), isFalse);
        expect(await other.exists(), isTrue);
      },
    );

    test(
      'tệp chia sẻ dùng kho đệm của tài khoản: mở lại app (phiên mới) vẫn cùng thư mục',
      () async {
        Future<Directory> sharedDir(String generation) =>
            scopedSharedFileDirectory(
              scope: serverA,
              guard: AuthTokenMutationGuard(
                instanceScopeId: serverA.storageId,
                generation: generation,
              ),
              accountKey: 'user:a',
            );
        final first = await sharedDir('gen-1');
        final afterRestart = await sharedDir('gen-2');
        expect(afterRestart.path, first.path);

        final otherAccount = await scopedSharedFileDirectory(
          scope: serverA,
          guard: AuthTokenMutationGuard(
            instanceScopeId: serverA.storageId,
            generation: 'gen-3',
          ),
          accountKey: 'user:b',
        );
        expect(otherAccount.path, isNot(first.path));
      },
    );
  });
}
