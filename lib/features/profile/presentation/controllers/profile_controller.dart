import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/profile_use_cases.dart';
import '../../domain/entities/avatar_upload.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

final profileControllerProvider =
    StateNotifierProvider.autoDispose<ProfileController, ProfileState>((ref) {
      return ProfileController(
        loadProfileUseCase: ref.watch(loadProfileUseCaseProvider),
        updateProfileUseCase: ref.watch(updateProfileUseCaseProvider),
        changeAvatarUseCase: ref.watch(changeAvatarUseCaseProvider),
      )..load();
    });

final class ProfileState {
  const ProfileState({
    this.profile,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.successMessage,
  });

  final UserProfile? profile;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final String? successMessage;

  ProfileState copyWith({
    UserProfile? profile,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearMessages ? null : errorMessage ?? this.errorMessage,
      successMessage: clearMessages
          ? null
          : successMessage ?? this.successMessage,
    );
  }
}

final class ProfileController extends StateNotifier<ProfileState> {
  ProfileController({
    required this.loadProfileUseCase,
    required this.updateProfileUseCase,
    required this.changeAvatarUseCase,
  }) : super(const ProfileState());

  final LoadProfileUseCase loadProfileUseCase;
  final UpdateProfileUseCase updateProfileUseCase;
  final ChangeAvatarUseCase changeAvatarUseCase;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearMessages: true);
    final result = await loadProfileUseCase.execute();
    switch (result) {
      case Success<UserProfile>(value: final profile):
        state = state.copyWith(profile: profile, isLoading: false);
      case FailureResult<UserProfile>(failure: final failure):
        state = state.copyWith(isLoading: false, errorMessage: failure.message);
    }
  }

  Future<void> save({
    String? displayName,
    String? phoneNumber,
    String? locale,
    String? timezone,
  }) async {
    state = state.copyWith(isSaving: true, clearMessages: true);
    final result = await updateProfileUseCase.execute(
      UpdateProfileCommand(
        displayName: displayName,
        phoneNumber: phoneNumber,
        locale: locale,
        timezone: timezone,
      ),
    );
    _applyProfileResult(result, success: 'Đã cập nhật hồ sơ.');
  }

  Future<void> changeAvatar(AvatarPickerSource source) async {
    state = state.copyWith(isSaving: true, clearMessages: true);
    final result = await changeAvatarUseCase.execute(source);
    switch (result) {
      case Success<UserProfile?>(value: final profile):
        state = state.copyWith(
          profile: profile ?? state.profile,
          isSaving: false,
          successMessage: profile == null ? null : 'Đã cập nhật ảnh đại diện.',
        );
      case FailureResult<UserProfile?>(failure: final failure):
        state = state.copyWith(isSaving: false, errorMessage: failure.message);
    }
  }

  void _applyProfileResult(
    Result<UserProfile> result, {
    required String success,
  }) {
    switch (result) {
      case Success<UserProfile>(value: final profile):
        state = state.copyWith(
          profile: profile,
          isSaving: false,
          successMessage: success,
        );
      case FailureResult<UserProfile>(failure: final failure):
        state = state.copyWith(isSaving: false, errorMessage: failure.message);
    }
  }
}
