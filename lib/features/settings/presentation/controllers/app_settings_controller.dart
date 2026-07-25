import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../notifications/application/use_cases/notification_use_cases.dart';
import '../../../notifications/domain/entities/mobile_notification.dart';
import '../../application/use_cases/app_settings_use_cases.dart';
import '../../application/use_cases/cache_maintenance_use_cases.dart';
import '../../application/use_cases/mobile_release_use_cases.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/mobile_release_policy.dart';

final appSettingsControllerProvider =
    StateNotifierProvider.autoDispose<AppSettingsController, AppSettingsState>((
      ref,
    ) {
      return AppSettingsController(
          loadUseCase: ref.watch(loadAppSettingsUseCaseProvider),
          saveUseCase: ref.watch(saveAppSettingsUseCaseProvider),
          loadNotificationPreferenceUseCase: ref.watch(
            loadNotificationPreferenceUseCaseProvider,
          ),
          saveNotificationPreferenceUseCase: ref.watch(
            saveNotificationPreferenceUseCaseProvider,
          ),
          clearWorkspaceCacheUseCase: ref.watch(
            clearWorkspaceCacheUseCaseProvider,
          ),
          checkMobileReleasePolicyUseCase: ref.watch(
            checkMobileReleasePolicyUseCaseProvider,
          ),
        )
        ..load()
        ..checkReleasePolicy();
    });

final class AppSettingsState {
  const AppSettingsState({
    this.settings = const AppSettings(),
    this.isLoading = false,
    this.isCheckingRelease = false,
    this.mobileReleasePolicy,
    this.errorMessage,
    this.releaseErrorMessage,
  });

  final AppSettings settings;
  final bool isLoading;
  final bool isCheckingRelease;
  final MobileReleasePolicy? mobileReleasePolicy;
  final String? errorMessage;
  final String? releaseErrorMessage;

  AppSettingsState copyWith({
    AppSettings? settings,
    bool? isLoading,
    bool? isCheckingRelease,
    MobileReleasePolicy? mobileReleasePolicy,
    String? errorMessage,
    String? releaseErrorMessage,
    bool clearError = false,
    bool clearReleaseError = false,
  }) {
    return AppSettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      isCheckingRelease: isCheckingRelease ?? this.isCheckingRelease,
      mobileReleasePolicy: mobileReleasePolicy ?? this.mobileReleasePolicy,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      releaseErrorMessage: clearReleaseError
          ? null
          : releaseErrorMessage ?? this.releaseErrorMessage,
    );
  }
}

final class AppSettingsController extends StateNotifier<AppSettingsState> {
  AppSettingsController({
    required this.loadUseCase,
    required this.saveUseCase,
    required this.loadNotificationPreferenceUseCase,
    required this.saveNotificationPreferenceUseCase,
    required this.clearWorkspaceCacheUseCase,
    required this.checkMobileReleasePolicyUseCase,
  }) : super(const AppSettingsState());

  final LoadAppSettingsUseCase loadUseCase;
  final SaveAppSettingsUseCase saveUseCase;
  final LoadNotificationPreferenceUseCase loadNotificationPreferenceUseCase;
  final SaveNotificationPreferenceUseCase saveNotificationPreferenceUseCase;
  final ClearWorkspaceCacheUseCase clearWorkspaceCacheUseCase;
  final CheckMobileReleasePolicyUseCase checkMobileReleasePolicyUseCase;
  String? _loadedPreferenceWorkspaceId;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final settings = await loadUseCase.execute();
      state = state.copyWith(settings: settings, isLoading: false);
    } on Object {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải thiết lập.',
      );
    }
  }

  Future<void> loadNotificationPreference(String workspaceId) async {
    final normalizedWorkspaceId = workspaceId.trim();
    if (normalizedWorkspaceId.isEmpty ||
        _loadedPreferenceWorkspaceId == normalizedWorkspaceId) {
      return;
    }
    _loadedPreferenceWorkspaceId = normalizedWorkspaceId;
    final result = await loadNotificationPreferenceUseCase.execute(
      workspaceId: normalizedWorkspaceId,
    );
    switch (result) {
      case Success<NotificationPreference>(value: final preference):
        final merged = state.settings.mergeNotificationPreference(preference);
        state = state.copyWith(settings: merged, clearError: true);
        await saveUseCase.execute(merged);
      case FailureResult<NotificationPreference>():
        return;
    }
  }

  Future<void> update(AppSettings settings, {String? workspaceId}) async {
    state = state.copyWith(settings: settings, clearError: true);
    try {
      await saveUseCase.execute(settings);
      final normalizedWorkspaceId = workspaceId?.trim();
      if (normalizedWorkspaceId != null && normalizedWorkspaceId.isNotEmpty) {
        final result = await saveNotificationPreferenceUseCase.fromAppSettings(
          workspaceId: normalizedWorkspaceId,
          settings: settings,
        );
        switch (result) {
          case Success<NotificationPreference>():
            return;
          case FailureResult<NotificationPreference>(failure: final failure):
            state = state.copyWith(errorMessage: failure.message);
        }
      }
    } on Object {
      state = state.copyWith(errorMessage: 'Không thể lưu thiết lập.');
    }
  }

  Future<void> clearWorkspaceCache(String workspaceId) async {
    try {
      await clearWorkspaceCacheUseCase.execute(workspaceId: workspaceId);
      state = state.copyWith(clearError: true);
    } on Object {
      state = state.copyWith(errorMessage: 'Không thể xóa cache lúc này.');
    }
  }

  Future<void> checkReleasePolicy() async {
    state = state.copyWith(isCheckingRelease: true, clearReleaseError: true);
    final result = await checkMobileReleasePolicyUseCase.execute();
    switch (result) {
      case Success<MobileReleasePolicy>(value: final policy):
        state = state.copyWith(
          mobileReleasePolicy: policy,
          isCheckingRelease: false,
        );
      case FailureResult<MobileReleasePolicy>(failure: final failure):
        state = state.copyWith(
          isCheckingRelease: false,
          releaseErrorMessage: failure.message,
        );
    }
  }
}
