import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/redirect_safe_file_downloader.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../auth/domain/repositories/auth_token_repository.dart';
import '../../../conversations/data/files/scoped_attachment_file_store.dart';
import '../../domain/entities/work_hub.dart';
import 'shared_file_logic.dart';

/// Bộ nhớ đệm tệp chia sẻ, tối đa 300 MB, nằm trong kho tệp theo máy chủ +
/// phiên đăng nhập (`ScopedAttachmentFileStore`): đăng xuất, đổi máy chủ hay
/// phiên bị thu hồi thì bị xoá cùng tệp đính kèm chat; phiên mới không đọc lại
/// tệp của phiên cũ.
final sharedFileCacheProvider = Provider<SharedFileCache>((ref) {
  return SharedFileCache(
    directory: () async => scopedSharedFileDirectory(
      scope: ref.read(activeServerDiscoveryProvider)?.instanceScope,
      guard: await ref.read(authTokenRepositoryProvider).captureMutationGuard(),
    ),
  );
});

/// Thư mục bộ nhớ đệm tệp chia sẻ của phiên hiện tại; không có phiên (hoặc
/// phiên thuộc máy chủ khác) thì báo lỗi, không ghi tệp ra ngoài kho có phạm vi.
Future<Directory> scopedSharedFileDirectory({
  required InstanceScope? scope,
  required AuthTokenMutationGuard? guard,
  ScopedAttachmentFileStore store = const ScopedAttachmentFileStore(),
}) async {
  if (scope == null ||
      guard == null ||
      guard.instanceScopeId != scope.storageId) {
    throw const RedirectSafeDownloadException('instance binding changed');
  }
  return store.directoryFor(
    instanceScope: scope,
    sessionGeneration: guard.generation,
    purpose: 'shared-files',
  );
}

/// Tìm nguồn phát / tệp cục bộ cho tệp chia sẻ của một workspace.
final sharedFileMediaResolverProvider =
    Provider.family<SharedFileMediaResolver, String>((ref, workspaceId) {
      final apiBase = ref.watch(activeServerUriProvider);
      final links = SharedFileStreamLinkCache(
        fetch: (fileId) async {
          final result = await ref
              .read(createSharedFileStreamLinkUseCaseProvider)
              .execute(workspaceId: workspaceId, fileId: fileId);
          return result.valueOrNull;
        },
      );
      return SharedFileMediaResolver(
        links: links,
        cache: ref.watch(sharedFileCacheProvider),
        absolute: (url) => resolveSharedFileUrl(apiBase, url),
        download: (file, target) =>
            _downloadSharedFile(ref, apiBase, workspaceId, file, target),
      );
    });

/// Ghép đường dẫn máy chủ trả về với địa chỉ API; chỉ nhận cùng nguồn gốc.
Uri? resolveSharedFileUrl(Uri apiBase, String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parsed = Uri.tryParse(text);
  if (parsed == null) return null;
  final resolved = parsed.hasScheme ? parsed : apiBase.resolve(text);
  if (!redirectSafeHttpUriAllowed(resolved) ||
      resolved.host.isEmpty ||
      resolved.userInfo.isNotEmpty ||
      resolved.fragment.isNotEmpty ||
      !serverOriginsMatch(resolved, apiBase)) {
    return null;
  }
  return resolved;
}

const _maxSharedFileDownloadBytes = 1024 * 1024 * 1024;

Future<void> _downloadSharedFile(
  Ref ref,
  Uri apiBase,
  String workspaceId,
  SharedFile file,
  File target,
) async {
  final scope = ref.read(activeServerDiscoveryProvider)?.instanceScope;
  if (scope == null || !serverOriginsMatch(apiBase, scope.origin)) {
    throw const RedirectSafeDownloadException('instance binding changed');
  }
  final tokens = ref.read(authTokenRepositoryProvider);
  final guard = await tokens.captureMutationGuard();
  if (guard == null || guard.instanceScopeId != scope.storageId) {
    throw const RedirectSafeDownloadException('instance binding changed');
  }
  final bearer = (await tokens.readAccessTokenIfCurrent(guard))?.trim();
  if (bearer == null || bearer.isEmpty) {
    throw const RedirectSafeDownloadException('missing access token');
  }
  final uri = apiBase.resolve(
    '/api/v1/workspaces/${Uri.encodeComponent(workspaceId)}'
    '/files/${Uri.encodeComponent(file.id)}/download',
  );
  await const RedirectSafeFileDownloader().download(
    uri: uri,
    target: target,
    maxBytes: _maxSharedFileDownloadBytes,
    expectedBytes: file.byteSize > 0 ? file.byteSize : null,
    accept: file.mimeType,
    bearerToken: bearer,
    isStillCurrent: () => tokens.isMutationGuardCurrent(guard),
  );
}
