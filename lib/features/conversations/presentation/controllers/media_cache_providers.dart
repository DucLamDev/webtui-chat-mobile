import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/connectivity_network_type_reader.dart';
import '../../../../core/network/media_auto_download_policy.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../../core/storage/local_media_cache_usage.dart';
import '../../data/files/attachment_cache_evictor.dart';
import '../../data/files/scoped_attachment_file_store.dart';
import '../../domain/entities/chat_message.dart';

/// Công tắc "Tự tải ảnh khi dùng dữ liệu di động" (mặc định bật). Thiết lập
/// ứng dụng ghi giá trị đã lưu vào đây sau khi đọc / đổi cài đặt; widget media
/// chỉ đọc provider nhỏ này (không kéo cả bộ điều khiển Thiết lập).
final mediaAutoDownloadOnCellularProvider = StateProvider<bool>((ref) => true);

/// Đọc loại mạng (Wi-Fi / di động); test thay bằng bản giả.
final networkTypeReaderProvider = Provider<NetworkTypeReader>((ref) {
  return ConnectivityNetworkTypeReader();
});

/// Có được tự tải ảnh / lưu ngầm video theo công tắc + loại mạng hiện tại.
final mediaAutoDownloadPolicyProvider = Provider<MediaAutoDownloadPolicy>((
  ref,
) {
  return MediaAutoDownloadPolicy(
    allowOnCellular: ref.watch(mediaAutoDownloadOnCellularProvider),
    networkTypeReader: ref.watch(networkTypeReaderProvider),
  );
});

/// Máy chủ + tài khoản đang đăng nhập (chọn thư mục kho đệm); `null` khi chưa
/// đăng nhập / phiên thuộc máy chủ khác.
Future<({InstanceScope instanceScope, String accountKey})?>
_activeMediaCacheAccount(Ref ref) async {
  final instanceScope = ref.read(activeServerDiscoveryProvider)?.instanceScope;
  if (instanceScope == null) return null;
  final tokenRepository = ref.read(authTokenRepositoryProvider);
  final guard = await tokenRepository.captureMutationGuard();
  if (guard == null || guard.instanceScopeId != instanceScope.storageId) {
    return null;
  }
  final accessToken = await tokenRepository.readAccessTokenIfCurrent(guard);
  return (
    instanceScope: instanceScope,
    accountKey: mediaCacheAccountKey(
      accessToken: accessToken?.trim(),
      sessionGeneration: guard.generation,
    ),
  );
}

/// Xoá tệp đã lưu trên máy của các tệp đính kèm (tin bị thu hồi / xoá / hết
/// hạn) trong kho của tài khoản hiện tại.
final messageAttachmentCacheEvictionProvider =
    Provider<Future<void> Function(List<MessageAttachment> attachments)>((ref) {
      const evictor = AttachmentCacheEvictor();
      return (attachments) async {
        if (attachments.isEmpty) return;
        final account = await _activeMediaCacheAccount(ref);
        if (account == null) return;
        await evictor.evict(
          instanceScope: account.instanceScope,
          accountKey: account.accountKey,
          apiBaseUri: ref.read(activeServerUriProvider),
          attachments: attachments,
        );
      };
    });

/// Dung lượng / xoá kho tệp trên máy của tài khoản hiện tại (Thiết lập >
/// Dung lượng lưu trên máy). Xoá xong bỏ luôn bộ nhớ trong đi kèm.
final localMediaCacheUsageProvider = Provider<LocalMediaCacheUsage>((ref) {
  return DirectoryMediaCacheUsage(
    directory: () async {
      final account = await _activeMediaCacheAccount(ref);
      if (account == null) return null;
      final Directory directory = await const ScopedAttachmentFileStore()
          .accountCacheDirectoryFor(
            instanceScope: account.instanceScope,
            accountKey: account.accountKey,
          );
      return directory;
    },
    onCleared: () async {
      ref.read(messageAttachmentMemoProvider).clear();
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    },
  );
});
