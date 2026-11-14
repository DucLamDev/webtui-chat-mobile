import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../work_hub/presentation/controllers/shared_file_logic.dart';
import '../../../work_hub/presentation/controllers/shared_file_providers.dart';

/// Lấy mã workspace từ đường tải `/api/v1/workspaces/{ws}/files/{id}/download`
/// của tệp đính kèm; null nếu đường dẫn không đúng dạng đó.
String? workspaceIdFromFilePath(String path) {
  final match = RegExp(r'/workspaces/([^/]+)/files/[^/]+').firstMatch(path);
  if (match == null) return null;
  final id = Uri.decodeComponent(match.group(1)!);
  return id.isEmpty ? null : id;
}

/// Bộ nhớ đệm đường phát dần video trong tin nhắn, theo workspace. Nằm trong
/// bộ nhớ của provider nên mất khi đổi máy chủ / phiên (provider dựng lại).
final messageVideoLinksProvider =
    Provider.family<SharedFileStreamLinkCache, String>((ref, workspaceId) {
      ref.watch(activeServerDiscoveryProvider);
      return SharedFileStreamLinkCache(
        fetch: (fileId) async {
          final result = await ref
              .read(createSharedFileStreamLinkUseCaseProvider)
              .execute(workspaceId: workspaceId, fileId: fileId);
          return result.valueOrNull;
        },
      );
    });

/// Xin địa chỉ phát dần của tệp video; [fresh] bỏ link đã nhớ (khi hết hạn /
/// bị từ chối). Null nếu máy chủ không cấp hoặc địa chỉ không hợp lệ.
Future<Uri?> resolveMessageVideoStream(
  WidgetRef ref, {
  required String workspaceId,
  required String fileId,
  bool fresh = false,
}) async {
  try {
    final links = ref.read(messageVideoLinksProvider(workspaceId));
    if (fresh) links.invalidate(fileId);
    final link = await links.linkFor(fileId);
    if (link == null) return null;
    return resolveSharedFileUrl(ref.read(activeServerUriProvider), link.url);
  } on Object {
    return null;
  }
}

/// Trình phát cho địa chỉ phát dần. Địa chỉ tự mang mã ngắn hạn do máy chủ cấp
/// nên không gửi kèm thông tin đăng nhập nào của app (khác với tải tệp thường).
VideoPlayerController messageVideoStreamController(Uri stream) {
  return VideoPlayerController.networkUrl(
    stream,
    videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
  );
}
