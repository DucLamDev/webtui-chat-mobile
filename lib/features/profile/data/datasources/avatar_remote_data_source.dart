import 'package:dio/dio.dart';

import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/avatar_upload.dart';

final class AvatarRemoteDataSource {
  const AvatarRemoteDataSource(this._api);

  final ApiTransport _api;

  /// Tải ảnh lên API ảnh đại diện (`POST /api/v1/users/me/avatar`, field
  /// `avatar`). Ảnh lưu công khai theo người dùng, không phải tệp đính kèm riêng
  /// tư của workspace (bản cũ gửi nhầm vào `/workspaces/{id}/files` nên ảnh
  /// không hiện được). `workspaceId` giữ lại cho chữ ký cũ.
  Future<UploadedAvatar> upload({
    required String workspaceId,
    required PickedAvatar avatar,
  }) async {
    final form = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(
        avatar.path,
        filename: avatar.fileName,
        contentType: DioMediaType.parse(avatar.mimeType),
      ),
    });
    final response = await _api.post<Object>(
      '/api/v1/users/me/avatar',
      data: form,
      options: Options(contentType: Headers.multipartFormDataContentType),
    );
    final map = envelopeItem(response.data, 'avatar');
    final avatarPath = stringField(map, const ['avatar_path', 'avatar_url']);
    if (avatarPath.isEmpty) {
      throw StateError('Máy chủ không trả đường dẫn ảnh đại diện.');
    }
    return UploadedAvatar(fileId: avatarPath, downloadPath: avatarPath);
  }
}
