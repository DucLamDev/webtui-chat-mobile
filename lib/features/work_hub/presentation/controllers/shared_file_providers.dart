import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/redirect_safe_file_downloader.dart';
import '../../../../core/platform/video_compressor.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../auth/domain/repositories/auth_token_repository.dart';
import '../../../conversations/data/files/scoped_attachment_file_store.dart';
import '../../domain/entities/work_hub.dart';
import 'shared_file_logic.dart';
import 'shared_video_poster_cache.dart';

/// Bộ nhớ đệm tệp chia sẻ, tối đa 300 MB, nằm trong kho đệm lâu dài của tài
/// khoản trên máy chủ (`ScopedAttachmentFileStore.cacheDirectoryFor`): mở lại
/// app vẫn dùng lại được tới 7 ngày; đăng xuất, đổi máy chủ hay phiên bị thu
/// hồi thì bị xoá cùng tệp đính kèm chat; tài khoản khác không đọc lại.
final sharedFileCacheProvider = Provider<SharedFileCache>((ref) {
  return SharedFileCache(directory: () => _activeSharedFileDirectory(ref));
});

Future<Directory> _activeSharedFileDirectory(Ref ref) async {
  final tokenRepository = ref.read(authTokenRepositoryProvider);
  final guard = await tokenRepository.captureMutationGuard();
  return scopedSharedFileDirectory(
    scope: ref.read(activeServerDiscoveryProvider)?.instanceScope,
    guard: guard,
    accountKey: guard == null
        ? null
        : mediaCacheAccountKey(
            accessToken: await tokenRepository.readAccessTokenIfCurrent(guard),
            sessionGeneration: guard.generation,
          ),
  );
}

/// Thư mục bộ nhớ đệm tệp chia sẻ của phiên hiện tại; không có phiên (hoặc
/// phiên thuộc máy chủ khác) thì báo lỗi, không ghi tệp ra ngoài kho có phạm vi.
/// Có [accountKey] (xem `mediaCacheAccountKey`) thì dùng kho đệm lâu dài của
/// tài khoản; không có thì dùng thư mục theo phiên (mất khi mở lại app).
Future<Directory> scopedSharedFileDirectory({
  required InstanceScope? scope,
  required AuthTokenMutationGuard? guard,
  String? accountKey,
  ScopedAttachmentFileStore store = const ScopedAttachmentFileStore(),
}) async {
  if (scope == null ||
      guard == null ||
      guard.instanceScopeId != scope.storageId) {
    throw const RedirectSafeDownloadException('instance binding changed');
  }
  if (accountKey != null && accountKey.trim().isNotEmpty) {
    return store.cacheDirectoryFor(
      instanceScope: scope,
      accountKey: accountKey,
      purpose: 'shared-files',
    );
  }
  return store.directoryFor(
    instanceScope: scope,
    sessionGeneration: guard.generation,
    purpose: 'shared-files',
  );
}

/// Thư mục WAV giải mã từ ghi âm WebM / Ogg để iPhone phát được (mục Tệp):
/// nằm trong thư mục tệp chia sẻ của phiên nên đăng xuất / đổi máy chủ / thu
/// hồi phiên xoá luôn; phiên hay máy chủ khác không đọc lại.
Future<Directory> scopedPlayableAudioDirectory({
  required InstanceScope? scope,
  required AuthTokenMutationGuard? guard,
  String? accountKey,
  ScopedAttachmentFileStore store = const ScopedAttachmentFileStore(),
}) async {
  final base = await scopedSharedFileDirectory(
    scope: scope,
    guard: guard,
    accountKey: accountKey,
    store: store,
  );
  return Directory('${base.path}/playable-audio');
}

final sharedPlayableAudioDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) {
      return () async {
        final base = await _activeSharedFileDirectory(ref);
        return Directory('${base.path}/playable-audio');
      };
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

/// Ảnh bìa tự cắt trên máy cho video chưa có ảnh bìa trên máy chủ.
final sharedVideoPosterCacheProvider =
    Provider.family<SharedVideoPosterCache, String>((ref, workspaceId) {
      final resolver = ref.watch(sharedFileMediaResolverProvider(workspaceId));
      final compressor = ref.watch(videoCompressorProvider);
      return SharedVideoPosterCache(
        directory: () async {
          final base = await _activeSharedFileDirectory(ref);
          return Directory('${base.path}/video-posters');
        },
        streamUri: (fileId) async {
          // Chỉ cần id để xin đường dẫn phát dần.
          return resolver.streamUriById(fileId);
        },
        extract: (url, output) async {
          if (compressor is! VideoUrlPoster) return false;
          final poster = await (compressor as VideoUrlPoster).posterFromUrl(
            url: url,
            outputPath: output,
          );
          return poster != null;
        },
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
