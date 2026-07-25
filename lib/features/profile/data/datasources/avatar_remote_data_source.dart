import 'package:dio/dio.dart';

import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/avatar_upload.dart';

final class AvatarRemoteDataSource {
  const AvatarRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<UploadedAvatar> upload({
    required String workspaceId,
    required PickedAvatar avatar,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        avatar.path,
        filename: avatar.fileName,
        contentType: DioMediaType.parse(avatar.mimeType),
      ),
    });
    final response = await _api.post<Object>(
      '/api/v1/workspaces/$workspaceId/files',
      data: form,
      options: Options(contentType: Headers.multipartFormDataContentType),
    );
    final map = envelopeItem(response.data, 'file');
    final fileId = stringField(map, const ['id', 'file_id']);
    return UploadedAvatar(
      fileId: fileId,
      downloadPath: stringField(map, const [
        'download_url',
        'url',
        'downloadPath',
      ], fallback: '/api/v1/workspaces/$workspaceId/files/$fileId/download'),
    );
  }
}
