import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../../core/security/instance_scope.dart';
import '../../../../core/storage/media_disk_cache.dart';
import '../../../auth/application/use_cases/current_user_id_use_case.dart';

const _cacheRootName = 'webtui-attachments-v2';

/// Tên thư mục kho đệm lâu dài trong thư mục của máy chủ. Không trùng được
/// thư mục theo phiên (tên băm sha256 64 ký tự).
const _mediaCacheDirectoryName = 'cache';

/// Kho đệm dùng chung của app cho mọi tệp dưới `webtui-attachments-v2` (kể cả
/// thư mục theo phiên của các lần mở app trước): giữ tối đa 7 ngày kể từ lần
/// dùng cuối, tổng tối đa 1 GB, xoá tệp lâu không dùng nhất trước.
final MediaDiskCache attachmentMediaCache = MediaDiskCache(
  root: () async => Directory(
    path.join((await getTemporaryDirectory()).path, _cacheRootName),
  ),
);

/// Khoá tài khoản cho kho đệm lâu dài: mã người dùng (`sub`) trong access
/// token. Không đọc được thì dùng thế hệ phiên: kho khi đó chỉ dùng lại được
/// trong lần mở app này (thế hệ phiên đổi mỗi lần khởi động).
String mediaCacheAccountKey({
  required String? accessToken,
  required String sessionGeneration,
}) {
  final userId = accessTokenUserId(accessToken);
  if (userId != null) return 'user:$userId';
  return 'session:${sessionGeneration.trim()}';
}

final class ScopedAttachmentFileStore {
  const ScopedAttachmentFileStore();

  /// Thư mục kho đệm lâu dài (xem [attachmentMediaCache]) của một tài khoản
  /// trên một máy chủ: `webtui-attachments-v2/<máy chủ>/cache/<tài khoản>/<purpose>`.
  /// Khác [directoryFor] (đổi mỗi lần mở app): tệp đã tải dùng lại được tới 7
  /// ngày. Vẫn nằm dưới thư mục của máy chủ nên [clearScope] (đăng xuất / đổi
  /// máy chủ / thu hồi phiên) xoá luôn; mỗi tài khoản một thư mục riêng.
  Future<Directory> cacheDirectoryFor({
    required InstanceScope instanceScope,
    required String accountKey,
    required String purpose,
  }) async {
    final root = await getTemporaryDirectory();
    return Directory(
      path.join(
        root.path,
        scopedMediaCacheDirectoryRelativePath(
          instanceScope: instanceScope,
          accountKey: accountKey,
          purpose: purpose,
        ),
      ),
    );
  }

  /// Tệp trong kho đệm lâu dài cho một [key] (thường là địa chỉ tải): tên là
  /// mã băm, không lộ khoá; giữ đuôi an toàn của [originalName] để app khác
  /// mở được.
  Future<File> cacheFileFor({
    required InstanceScope instanceScope,
    required String accountKey,
    required String purpose,
    required String key,
    String originalName = '',
  }) async {
    final directory = await cacheDirectoryFor(
      instanceScope: instanceScope,
      accountKey: accountKey,
      purpose: purpose,
    );
    return File(
      path.join(
        directory.path,
        scopedMediaCacheFileName(
          instanceScope: instanceScope,
          key: key,
          originalName: originalName,
        ),
      ),
    );
  }

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

  /// Thư mục riêng cho một loại bộ nhớ đệm ([purpose]) trong phiên đăng nhập
  /// hiện tại. Nằm dưới thư mục của máy chủ nên [clearScope] (gọi ở mọi đường
  /// đăng xuất / đổi máy chủ / thu hồi phiên) xoá luôn; phiên mới dùng thư mục
  /// khác nên không đọc lại tệp của phiên cũ.
  Future<Directory> directoryFor({
    required InstanceScope instanceScope,
    required String sessionGeneration,
    required String purpose,
  }) async {
    final root = await getTemporaryDirectory();
    return Directory(
      path.join(
        root.path,
        scopedAttachmentDirectoryRelativePath(
          instanceScope: instanceScope,
          sessionGeneration: sessionGeneration,
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
  final directory = scopedAttachmentDirectoryRelativePath(
    instanceScope: instanceScope,
    sessionGeneration: sessionGeneration,
    purpose: purpose,
  );
  final digest = sha256
      .convert(
        utf8.encode(
          '${instanceScope.storageId}\u0000$fileId\u0000$originalName',
        ),
      )
      .toString();
  final extension = _safeExtension(originalName);
  return path.join(directory, '$digest$extension');
}

/// `webtui-attachments-v2/<máy chủ>/cache/<tài khoản>/<purpose>` (tên băm,
/// không lộ mã máy chủ / người dùng).
String scopedMediaCacheDirectoryRelativePath({
  required InstanceScope instanceScope,
  required String accountKey,
  required String purpose,
}) {
  final normalizedPurpose = _normalizedPurpose(purpose);
  final normalizedAccount = accountKey.trim();
  if (normalizedAccount.isEmpty || normalizedAccount.length > 256) {
    throw ArgumentError.value(
      accountKey,
      'accountKey',
      'must be a bounded account key',
    );
  }
  return path.join(
    _cacheRootName,
    _scopeDirectory(instanceScope),
    _mediaCacheDirectoryName,
    sha256
        .convert(
          utf8.encode('${instanceScope.storageId}\u0000$normalizedAccount'),
        )
        .toString(),
    normalizedPurpose,
  );
}

/// Tên tệp trong kho đệm lâu dài: băm (máy chủ + [key]) + đuôi an toàn.
String scopedMediaCacheFileName({
  required InstanceScope instanceScope,
  required String key,
  String originalName = '',
}) {
  final digest = sha256
      .convert(utf8.encode('${instanceScope.storageId}\u0000$key'))
      .toString();
  return '$digest${_safeExtension(originalName)}';
}

/// `webtui-attachments-v2/<máy chủ>/<phiên>/<purpose>` (tên băm, không lộ mã).
String scopedAttachmentDirectoryRelativePath({
  required InstanceScope instanceScope,
  required String sessionGeneration,
  required String purpose,
}) {
  final normalizedPurpose = _normalizedPurpose(purpose);
  final normalizedGeneration = sessionGeneration.trim();
  if (normalizedGeneration.isEmpty || normalizedGeneration.length > 256) {
    throw ArgumentError.value(
      sessionGeneration,
      'sessionGeneration',
      'must be a bounded active generation',
    );
  }
  return path.join(
    _cacheRootName,
    _scopeDirectory(instanceScope),
    sha256.convert(utf8.encode(normalizedGeneration)).toString(),
    normalizedPurpose,
  );
}

String _normalizedPurpose(String purpose) {
  final normalized = purpose.trim().toLowerCase();
  if (!RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(normalized)) {
    throw ArgumentError.value(purpose, 'purpose', 'must be a safe cache kind');
  }
  return normalized;
}

String _scopeDirectory(InstanceScope instanceScope) {
  return sha256.convert(utf8.encode(instanceScope.storageId)).toString();
}

String _safeExtension(String originalName) {
  final extension = path.extension(originalName).toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension) ? extension : '';
}
