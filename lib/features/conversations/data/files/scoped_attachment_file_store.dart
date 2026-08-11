import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../../core/security/instance_scope.dart';

const _cacheRootName = 'webtui-attachments-v2';

final class ScopedAttachmentFileStore {
  const ScopedAttachmentFileStore();

  Future<File> fileFor({
    required InstanceScope instanceScope,
    required String sessionGeneration,
    required String fileId,
    required String originalName,
    required String purpose,
  }) async {
    final root = await getTemporaryDirectory();
    return File(
      path.join(
        root.path,
        scopedAttachmentRelativePath(
          instanceScope: instanceScope,
          sessionGeneration: sessionGeneration,
          fileId: fileId,
          originalName: originalName,
          purpose: purpose,
        ),
      ),
    );
  }

  Future<void> clearScope(InstanceScope? instanceScope) async {
    if (instanceScope == null) return;
    final root = await getTemporaryDirectory();
    final cacheRoot = Directory(path.join(root.path, _cacheRootName));
    final target = Directory(
      path.join(cacheRoot.path, _scopeDirectory(instanceScope)),
    );
    if (path.equals(
          path.dirname(path.normalize(target.path)),
          path.normalize(cacheRoot.path),
        ) &&
        await target.exists()) {
      await target.delete(recursive: true);
    }
  }
}

String scopedAttachmentRelativePath({
  required InstanceScope instanceScope,
  required String sessionGeneration,
  required String fileId,
  required String originalName,
  required String purpose,
}) {
  final normalizedPurpose = purpose.trim().toLowerCase();
  if (!RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(normalizedPurpose)) {
    throw ArgumentError.value(purpose, 'purpose', 'must be a safe cache kind');
  }
  final normalizedGeneration = sessionGeneration.trim();
  if (normalizedGeneration.isEmpty || normalizedGeneration.length > 256) {
    throw ArgumentError.value(
      sessionGeneration,
      'sessionGeneration',
      'must be a bounded active generation',
    );
  }
  final digest = sha256
      .convert(
        utf8.encode(
          '${instanceScope.storageId}\u0000$fileId\u0000$originalName',
        ),
      )
      .toString();
  final extension = _safeExtension(originalName);
  return path.join(
    _cacheRootName,
    _scopeDirectory(instanceScope),
    sha256.convert(utf8.encode(normalizedGeneration)).toString(),
    normalizedPurpose,
    '$digest$extension',
  );
}

String _scopeDirectory(InstanceScope instanceScope) {
  return sha256.convert(utf8.encode(instanceScope.storageId)).toString();
}

String _safeExtension(String originalName) {
  final extension = path.extension(originalName).toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension) ? extension : '';
}
