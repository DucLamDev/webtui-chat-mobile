import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/redirect_safe_file_downloader.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/conversations/data/files/scoped_attachment_file_store.dart';
import 'package:webtui_chat/features/work_hub/presentation/controllers/shared_file_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scope = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: Uri.parse('https://server-a.example'),
  );
  final otherScope = InstanceScope(
    instanceId: '22222222-2222-4222-8222-222222222222',
    serverOrigin: Uri.parse('https://server-b.example'),
  );

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shared-file-scope-');
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

  test('thư mục tệp chia sẻ tách theo máy chủ và phiên đăng nhập', () {
    String dir(InstanceScope s, String generation) =>
        scopedAttachmentDirectoryRelativePath(
          instanceScope: s,
          sessionGeneration: generation,
          purpose: 'shared-files',
        );
    expect(dir(scope, 'gen-1'), isNot(dir(scope, 'gen-2')));
    expect(dir(scope, 'gen-1'), isNot(dir(otherScope, 'gen-1')));
    // Tệp đính kèm chat cùng phiên nằm cạnh (cùng gốc máy chủ + phiên).
    final file = scopedAttachmentRelativePath(
      instanceScope: scope,
      sessionGeneration: 'gen-1',
      fileId: 'f1',
      originalName: 'a.pdf',
      purpose: 'shared-files',
    );
    expect(file.startsWith(dir(scope, 'gen-1')), isTrue);
    expect(
      () => scopedAttachmentDirectoryRelativePath(
        instanceScope: scope,
        sessionGeneration: 'gen-1',
        purpose: '../thoát',
      ),
      throwsArgumentError,
    );
  });

  test(
    'không có phiên hoặc phiên thuộc máy chủ khác thì không cấp thư mục',
    () {
      expect(
        scopedSharedFileDirectory(scope: null, guard: null),
        throwsA(isA<RedirectSafeDownloadException>()),
      );
      expect(
        scopedSharedFileDirectory(
          scope: scope,
          guard: AuthTokenMutationGuard(
            instanceScopeId: otherScope.storageId,
            generation: 'gen-1',
          ),
        ),
        throwsA(isA<RedirectSafeDownloadException>()),
      );
    },
  );

  test(
    'đăng xuất / đổi máy chủ (clearScope) xoá luôn tệp chia sẻ đã lưu',
    () async {
      final directory = await scopedSharedFileDirectory(
        scope: scope,
        guard: AuthTokenMutationGuard(
          instanceScopeId: scope.storageId,
          generation: 'gen-1',
        ),
      );
      expect(directory.path.startsWith(temp.path), isTrue);
      await directory.create(recursive: true);
      final cached = File('${directory.path}/f1-3.pdf');
      await cached.writeAsString('pdf');

      final other = await const ScopedAttachmentFileStore().directoryFor(
        instanceScope: otherScope,
        sessionGeneration: 'gen-1',
        purpose: 'shared-files',
      );
      await other.create(recursive: true);

      await const ScopedAttachmentFileStore().clearScope(scope);

      expect(await cached.exists(), isFalse);
      expect(await directory.exists(), isFalse);
      // Máy chủ khác không bị xoá nhầm.
      expect(await other.exists(), isTrue);
    },
  );
}
