import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/redirect_safe_file_downloader.dart';
import '../../../../core/security/instance_scope.dart';
import '../../domain/entities/work_hub.dart';
import 'shared_file_logic.dart';

/// Bộ nhớ đệm tệp chia sẻ: thư mục tạm của app, tối đa 300 MB.
final sharedFileCacheProvider = Provider<SharedFileCache>((ref) {
  return SharedFileCache(
    directory: () async {
      final base = await getTemporaryDirectory();
      return Directory('${base.path}/shared-files');
    },
  );
});

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
