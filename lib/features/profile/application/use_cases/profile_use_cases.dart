import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../workspace/domain/repositories/workspace_session_repository.dart';
import '../../domain/entities/avatar_upload.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/avatar_repository.dart';
import '../../domain/repositories/profile_repository.dart';

final class LoadProfileUseCase {
  const LoadProfileUseCase(this._repository);

  final ProfileRepository _repository;

  Future<Result<UserProfile>> execute() => _repository.me();
}

final class UpdateProfileUseCase {
  const UpdateProfileUseCase(this._repository);

  final ProfileRepository _repository;

  Future<Result<UserProfile>> execute(UpdateProfileCommand command) {
    final displayName = command.displayName?.trim();
    if (displayName != null && displayName.isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Tên hiển thị không được để trống.',
            code: 'PROFILE_NAME_REQUIRED',
          ),
        ),
      );
    }
    return _repository.updateMe(command);
  }
}

final class ChangeAvatarUseCase {
  const ChangeAvatarUseCase({
    required AvatarPickerRepository pickerRepository,
    required AvatarUploadRepository uploadRepository,
    required ProfileRepository profileRepository,
    required WorkspaceSessionRepository workspaceSessionRepository,
  }) : _pickerRepository = pickerRepository,
       _uploadRepository = uploadRepository,
       _profileRepository = profileRepository,
       _workspaceSessionRepository = workspaceSessionRepository;

  final AvatarPickerRepository _pickerRepository;
  final AvatarUploadRepository _uploadRepository;
  final ProfileRepository _profileRepository;
  final WorkspaceSessionRepository _workspaceSessionRepository;

  Future<Result<UserProfile?>> execute(AvatarPickerSource source) async {
    final workspaceId = await _workspaceSessionRepository
        .readActiveWorkspaceId();
    if (workspaceId == null || workspaceId.trim().isEmpty) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Bạn cần chọn workspace trước khi đổi ảnh đại diện.',
          code: 'WORKSPACE_REQUIRED',
        ),
      );
    }

    final pickedResult = await _pickerRepository.pick(source);
    switch (pickedResult) {
      case FailureResult<PickedAvatar?>(failure: final failure):
        return FailureResult(failure);
      case Success<PickedAvatar?>(value: final picked):
        if (picked == null) {
          return const Success(null);
        }

        final uploadResult = await _uploadRepository.upload(
          workspaceId: workspaceId,
          avatar: picked,
        );
        switch (uploadResult) {
          case FailureResult<UploadedAvatar>(failure: final failure):
            return FailureResult(failure);
          case Success<UploadedAvatar>(value: final uploaded):
            return _profileRepository.updateMe(
              UpdateProfileCommand(avatarUrl: uploaded.downloadPath),
            );
        }
    }
  }
}
