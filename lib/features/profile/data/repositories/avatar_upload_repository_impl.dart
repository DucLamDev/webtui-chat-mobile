import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/avatar_upload.dart';
import '../../domain/repositories/avatar_repository.dart';
import '../datasources/avatar_remote_data_source.dart';

final class AvatarUploadRepositoryImpl implements AvatarUploadRepository {
  const AvatarUploadRepositoryImpl(this._remote);

  final AvatarRemoteDataSource _remote;

  @override
  Future<Result<UploadedAvatar>> upload({
    required String workspaceId,
    required PickedAvatar avatar,
  }) {
    return guardResult(
      () => _remote.upload(workspaceId: workspaceId, avatar: avatar),
    );
  }
}
