import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../application/use_cases/channel_notification_preference_use_cases.dart';

/// Khoá (workspace, kênh) của một cài đặt báo kênh.
final class ChannelMuteKey {
  const ChannelMuteKey({required this.workspaceId, required this.channelId});

  final String workspaceId;
  final String channelId;

  @override
  bool operator ==(Object other) =>
      other is ChannelMuteKey &&
      other.workspaceId == workspaceId &&
      other.channelId == channelId;

  @override
  int get hashCode => Object.hash(workspaceId, channelId);
}

final channelMuteControllerProvider = StateNotifierProvider.autoDispose
    .family<ChannelMuteController, ChannelMuteState, ChannelMuteKey>((
      ref,
      key,
    ) {
      return ChannelMuteController(
        key: key,
        loadUseCase: ref.watch(
          loadChannelNotificationPreferenceUseCaseProvider,
        ),
        setMutedUseCase: ref.watch(setChannelNotificationMutedUseCaseProvider),
      )..load();
    });

final class ChannelMuteState {
  const ChannelMuteState({
    this.muted,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
  });

  /// `null` khi chưa đọc được cài đặt.
  final bool? muted;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  ChannelMuteState copyWith({
    bool? muted,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChannelMuteState(
      muted: muted ?? this.muted,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final class ChannelMuteController extends StateNotifier<ChannelMuteState> {
  ChannelMuteController({
    required this.key,
    required LoadChannelNotificationPreferenceUseCase loadUseCase,
    required SetChannelNotificationMutedUseCase setMutedUseCase,
  }) : _loadUseCase = loadUseCase,
       _setMutedUseCase = setMutedUseCase,
       super(const ChannelMuteState());

  @visibleForTesting
  ChannelMuteController.forTesting({
    required ChannelMuteKey key,
    required LoadChannelNotificationPreferenceUseCase loadUseCase,
    required SetChannelNotificationMutedUseCase setMutedUseCase,
  }) : this(
         key: key,
         loadUseCase: loadUseCase,
         setMutedUseCase: setMutedUseCase,
       );

  final ChannelMuteKey key;
  final LoadChannelNotificationPreferenceUseCase _loadUseCase;
  final SetChannelNotificationMutedUseCase _setMutedUseCase;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final result = await _loadUseCase.execute(
      workspaceId: key.workspaceId,
      channelId: key.channelId,
    );
    if (!mounted) return;
    state = result.when(
      success: (preference) =>
          state.copyWith(isLoading: false, muted: preference.isMuted),
      failure: (failure) =>
          state.copyWith(isLoading: false, errorMessage: failure.message),
    );
  }

  /// Đảo trạng thái; trả `true` khi lưu xong.
  Future<bool> toggle() async {
    if (state.isSaving) return false;
    final target = !(state.muted ?? false);
    state = state.copyWith(isSaving: true, clearError: true);
    final result = await _setMutedUseCase.execute(
      workspaceId: key.workspaceId,
      channelId: key.channelId,
      muted: target,
    );
    if (!mounted) return result.isSuccess;
    state = result.when(
      success: (preference) =>
          state.copyWith(isSaving: false, muted: preference.isMuted),
      failure: (failure) =>
          state.copyWith(isSaving: false, errorMessage: failure.message),
    );
    return result.isSuccess;
  }
}
