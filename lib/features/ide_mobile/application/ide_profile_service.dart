import 'dart:convert';
import 'dart:typed_data';

import '../data/ide_rpc_client.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_profile_models.dart';
import 'ide_image_guard.dart';

/// Ảnh đại diện từ IDE có cạnh lớn hơn mức này thì không hiện.
const ideAvatarMaxDisplaySide = 1024;

/// Ảnh đại diện đã tải về.
final class IdeAvatarImage {
  const IdeAvatarImage(this.bytes, this.version);
  final Uint8List bytes;
  final String version;
}

/// Gọi `profile.*` và `ai.*` (chỉ hồ sơ của chính mình).
class IdeProfileService {
  IdeProfileService(this._rpc);

  final IdeRpcClient _rpc;

  Future<IdeProfile> show({int days = 30}) async =>
      IdeProfile.parse(await _rpc.call('profile.show', {'days': days}));

  Future<List<IdeUsageDay>> usageDaily({int days = 30}) async =>
      IdeUsageDay.parseList(
        await _rpc.call('profile.usage_daily', {'days': days}),
      );

  /// `null` khi chưa có ảnh (`not_found`).
  Future<IdeAvatarImage?> avatarGet() async {
    try {
      final d = await _rpc.call('profile.avatar_get', const {});
      final m = d is Map ? d : const <Object?, Object?>{};
      final img = m['image'];
      if (img is! String || img.isEmpty || img.length > 600 * 1024) return null;
      final bytes = base64Decode(img);
      // Ảnh từ IDE là dữ liệu ngoài: kiểm kích thước trước khi cho hiện.
      final size = await ideReadImageSize(bytes);
      if (size == null ||
          !ideImageSizeWithin(size, maxSide: ideAvatarMaxDisplaySide)) {
        return null;
      }
      return IdeAvatarImage(bytes, '${m['version'] ?? ''}');
    } on IdeNotFound {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Gửi PNG 256 × 256; trả `avatar_version`.
  Future<String?> avatarSet(Uint8List png) async {
    final d = await _rpc.call('profile.avatar_set', {
      'image': base64Encode(png),
    });
    final v = d is Map ? d['avatar_version'] : null;
    return v == null ? null : '$v';
  }

  Future<void> avatarRemove() => _rpc.call('profile.avatar_remove', const {});

  Future<IdeAiUsage> aiUsage({String? project}) async => IdeAiUsage.parse(
    await _rpc.call('ai.usage', {
      if (project != null && project.isNotEmpty) 'project': project,
    }),
  );

  Future<List<IdeAiRoute>> aiRoutes() async =>
      IdeAiRoute.parseList(await _rpc.call('ai.routes', const {}));
}
