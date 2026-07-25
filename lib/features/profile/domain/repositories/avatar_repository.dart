import '../../../../core/result/result.dart';
import '../entities/avatar_upload.dart';

abstract interface class AvatarPickerRepository {
  Future<Result<PickedAvatar?>> pick(AvatarPickerSource source);
}

abstract interface class AvatarUploadRepository {
  Future<Result<UploadedAvatar>> upload({
    required String workspaceId,
    required PickedAvatar avatar,
  });
}
