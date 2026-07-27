import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api/openapi_client_boundary.dart';
import '../../core/database/app_database.dart';
import '../../core/logging/redacting_logger.dart';
import '../../core/network/api_transport.dart';
import '../../core/network/request_id.dart';
import '../../core/network/self_hosted_server_discovery.dart';
import '../../core/network/self_hosted_server_discovery_client.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/platform/external_url_launcher.dart';
import '../../core/security/secure_key_value_store.dart';
import '../../features/auth/application/use_cases/app_lock_use_cases.dart';
import '../../features/auth/application/use_cases/google_login_use_case.dart';
import '../../features/auth/application/use_cases/login_use_case.dart';
import '../../features/auth/application/use_cases/logout_use_case.dart';
import '../../features/auth/application/use_cases/refresh_access_token_use_case.dart';
import '../../features/auth/application/use_cases/register_use_case.dart';
import '../../features/auth/application/use_cases/session_use_cases.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/google/google_sign_in_identity_provider.dart';
import '../../features/auth/data/network/auth_refresh_interceptor.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/data/repositories/local_session_state_repository.dart';
import '../../features/auth/data/repositories/secure_app_lock_repository.dart';
import '../../features/auth/data/repositories/secure_auth_token_repository.dart';
import '../../features/auth/data/repositories/secure_device_identity_repository.dart';
import '../../features/auth/domain/repositories/app_lock_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/repositories/auth_token_repository.dart';
import '../../features/auth/domain/repositories/device_identity_repository.dart';
import '../../features/auth/domain/repositories/google_identity_provider.dart';
import '../../features/auth/domain/repositories/session_state_repository.dart';
import '../../features/business/application/use_cases/business_dashboard_use_cases.dart';
import '../../features/business/data/datasources/business_remote_data_source.dart';
import '../../features/business/data/repositories/business_repository_impl.dart';
import '../../features/business/domain/repositories/business_repository.dart';
import '../../features/conversations/application/use_cases/call_use_cases.dart';
import '../../features/conversations/application/use_cases/channel_use_cases.dart';
import '../../features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import '../../features/conversations/application/use_cases/message_attachment_use_cases.dart';
import '../../features/conversations/application/use_cases/message_outbox_use_cases.dart';
import '../../features/conversations/application/use_cases/message_use_cases.dart';
import '../../features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import '../../features/conversations/application/use_cases/presence_use_cases.dart';
import '../../features/conversations/data/datasources/call_remote_data_source.dart';
import '../../features/conversations/data/datasources/conversation_cache_data_source.dart';
import '../../features/conversations/data/datasources/conversation_remote_data_source.dart';
import '../../features/conversations/data/datasources/message_attachment_remote_data_source.dart';
import '../../features/conversations/data/datasources/message_outbox_data_source.dart';
import '../../features/conversations/data/repositories/audio_message_attachment_repository.dart';
import '../../features/conversations/data/repositories/caching_conversation_repository.dart';
import '../../features/conversations/data/repositories/call_repository_impl.dart';
import '../../features/conversations/data/repositories/conversation_repository_impl.dart';
import '../../features/conversations/data/repositories/image_picker_message_attachment_repository.dart';
import '../../features/conversations/data/repositories/local_conversation_draft_repository.dart';
import '../../features/conversations/data/repositories/local_message_outbox_repository.dart';
import '../../features/conversations/data/repositories/message_attachment_repository_impl.dart';
import '../../features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import '../../features/conversations/domain/repositories/call_repository.dart';
import '../../features/conversations/domain/repositories/conversation_repository.dart';
import '../../features/conversations/domain/repositories/message_attachment_repository.dart';
import '../../features/conversations/domain/repositories/message_outbox_repository.dart';
import '../../features/notifications/application/use_cases/notification_use_cases.dart';
import '../../features/notifications/data/datasources/notification_remote_data_source.dart';
import '../../features/notifications/data/repositories/notification_repository_impl.dart';
import '../../features/notifications/domain/repositories/notification_repository.dart';
import '../../features/profile/application/use_cases/profile_use_cases.dart';
import '../../features/profile/data/datasources/avatar_remote_data_source.dart';
import '../../features/profile/data/datasources/profile_remote_data_source.dart';
import '../../features/profile/data/repositories/avatar_upload_repository_impl.dart';
import '../../features/profile/data/repositories/image_picker_avatar_repository.dart';
import '../../features/profile/data/repositories/profile_repository_impl.dart';
import '../../features/profile/domain/repositories/avatar_repository.dart';
import '../../features/profile/domain/repositories/profile_repository.dart';
import '../../features/settings/application/use_cases/app_settings_use_cases.dart';
import '../../features/settings/application/use_cases/cache_maintenance_use_cases.dart';
import '../../features/settings/application/use_cases/mobile_release_use_cases.dart';
import '../../features/settings/data/datasources/mobile_release_remote_data_source.dart';
import '../../features/settings/data/repositories/local_app_settings_repository.dart';
import '../../features/settings/domain/repositories/app_settings_repository.dart';
import '../../features/sync/application/use_cases/workspace_sync_use_cases.dart';
import '../../features/sync/data/datasources/local_workspace_sync_cursor_data_source.dart';
import '../../features/sync/data/datasources/workspace_sync_remote_data_source.dart';
import '../../features/sync/data/repositories/workspace_sync_repository_impl.dart';
import '../../features/sync/domain/repositories/workspace_sync_repository.dart';
import '../../features/workspace/application/use_cases/load_workspace_session_use_case.dart';
import '../../features/workspace/application/use_cases/select_workspace_use_case.dart';
import '../../features/workspace/data/datasources/permission_remote_data_source.dart';
import '../../features/workspace/data/datasources/workspace_remote_data_source.dart';
import '../../features/workspace/data/repositories/local_workspace_session_repository.dart';
import '../../features/workspace/data/repositories/permission_repository_impl.dart';
import '../../features/workspace/data/repositories/workspace_repository_impl.dart';
import '../../features/workspace/domain/repositories/permission_repository.dart';
import '../../features/workspace/domain/repositories/workspace_repository.dart';
import '../../features/workspace/domain/repositories/workspace_session_repository.dart';
import '../flavor/app_config.dart';

final redactingLoggerProvider = Provider<RedactingLogger>((_) {
  return RedactingLogger();
});

final requestIdGeneratorProvider = Provider<RequestIdGenerator>((_) {
  return const UuidRequestIdGenerator();
});

final activeServerUriProvider = StateProvider<Uri>((ref) {
  return ref.watch(appConfigProvider).apiBaseUri;
});

final selfHostedServerDiscoveryClientProvider =
    Provider<SelfHostedServerDiscoveryClient>((ref) {
      return SelfHostedServerDiscoveryClient();
    });

final activeServerWsUriProvider = StateProvider<Uri>((ref) {
  return ref.watch(appConfigProvider).wsBaseUri;
});

final initialServerDiscoveryProvider = Provider<SelfHostedServerDiscovery?>(
  (_) => null,
);

final activeServerDiscoveryProvider = StateProvider<SelfHostedServerDiscovery?>(
  (ref) => ref.watch(initialServerDiscoveryProvider),
);

final dioProvider = Provider<Dio>((ref) {
  final activeServerUri = ref.watch(activeServerUriProvider);
  final logger = ref.watch(redactingLoggerProvider);
  final requestIds = ref.watch(requestIdGeneratorProvider);
  final tokenRepository = ref.watch(authTokenRepositoryProvider);
  final refreshUseCase = ref.watch(refreshAccessTokenUseCaseProvider);

  final dio = _configuredDio(activeServerUri);

  dio.interceptors.addAll([
    RequestIdInterceptor(requestIds),
    AuthRefreshInterceptor(
      dio: dio,
      tokenRepository: tokenRepository,
      refreshAccessTokenUseCase: refreshUseCase,
    ),
    RedactingDioLogInterceptor(logger),
  ]);

  return dio;
});

final authDioProvider = Provider<Dio>((ref) {
  final activeServerUri = ref.watch(activeServerUriProvider);
  final logger = ref.watch(redactingLoggerProvider);
  final requestIds = ref.watch(requestIdGeneratorProvider);

  final dio = _configuredDio(activeServerUri);
  dio.interceptors.addAll([
    RequestIdInterceptor(requestIds),
    RedactingDioLogInterceptor(logger),
  ]);
  return dio;
});

final apiTransportProvider = Provider<ApiTransport>((ref) {
  return DioApiTransport(ref.watch(dioProvider));
});

final authApiTransportProvider = Provider<ApiTransport>((ref) {
  return DioApiTransport(ref.watch(authDioProvider));
});

final openApiClientBoundaryProvider = Provider<WebTuiOpenApiClientBoundary>((
  ref,
) {
  return WebTuiOpenApiClientBoundary(ref.watch(dioProvider));
});

final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  final service = PushNotificationService(
    api: ref.watch(apiTransportProvider),
    deviceIdentityRepository: ref.watch(deviceIdentityRepositoryProvider),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

final externalUrlLauncherProvider = Provider<ExternalUrlLauncher>((_) {
  return const MethodChannelExternalUrlLauncher();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase(createDriftConnection());
  ref.onDispose(database.close);
  return database;
});

final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>((_) {
  return const FlutterSecureKeyValueStore(FlutterSecureStorage());
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(ref.watch(authApiTransportProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
});

final authSessionRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((
  ref,
) {
  return AuthRemoteDataSource(ref.watch(apiTransportProvider));
});

final authSessionRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authSessionRemoteDataSourceProvider));
});

final authTokenRepositoryProvider = Provider<AuthTokenRepository>((ref) {
  return SecureAuthTokenRepository(ref.watch(secureKeyValueStoreProvider));
});

final authAccessTokenProvider = FutureProvider<String?>((ref) {
  return ref.watch(authTokenRepositoryProvider).readAccessToken();
});

final deviceIdentityRepositoryProvider = Provider<DeviceIdentityRepository>((
  ref,
) {
  return SecureDeviceIdentityRepository(
    secureStore: ref.watch(secureKeyValueStoreProvider),
  );
});

final googleIdentityProvider = Provider<GoogleIdentityProvider>((_) {
  return GoogleSignInIdentityProvider();
});

final sessionStateRepositoryProvider = Provider<SessionStateRepository>((ref) {
  return LocalSessionStateRepository(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    database: ref.watch(appDatabaseProvider),
  );
});

final appLockRepositoryProvider = Provider<AppLockRepository>((ref) {
  return SecureAppLockRepository(ref.watch(secureKeyValueStoreProvider));
});

final loginUseCaseProvider = Provider<LoginUseCase>((ref) {
  return LoginUseCase(
    authRepository: ref.watch(authRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
    deviceIdentityRepository: ref.watch(deviceIdentityRepositoryProvider),
  );
});

final registerUseCaseProvider = Provider<RegisterUseCase>((ref) {
  return RegisterUseCase(
    authRepository: ref.watch(authRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
    deviceIdentityRepository: ref.watch(deviceIdentityRepositoryProvider),
  );
});

final googleLoginUseCaseProvider = Provider<GoogleLoginUseCase>((ref) {
  return GoogleLoginUseCase(
    identityProvider: ref.watch(googleIdentityProvider),
    authRepository: ref.watch(authRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
    deviceIdentityRepository: ref.watch(deviceIdentityRepositoryProvider),
  );
});

final refreshAccessTokenUseCaseProvider = Provider<RefreshAccessTokenUseCase>((
  ref,
) {
  return RefreshAccessTokenUseCase(
    authRepository: ref.watch(authRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
  );
});

final logoutUseCaseProvider = Provider<LogoutUseCase>((ref) {
  return LogoutUseCase(
    authRepository: ref.watch(authRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
    sessionStateRepository: ref.watch(sessionStateRepositoryProvider),
  );
});

final listSessionsUseCaseProvider = Provider<ListSessionsUseCase>((ref) {
  return ListSessionsUseCase(ref.watch(authSessionRepositoryProvider));
});

final revokeSessionUseCaseProvider = Provider<RevokeSessionUseCase>((ref) {
  return RevokeSessionUseCase(ref.watch(authSessionRepositoryProvider));
});

final revokeAllSessionsUseCaseProvider = Provider<RevokeAllSessionsUseCase>((
  ref,
) {
  return RevokeAllSessionsUseCase(ref.watch(authSessionRepositoryProvider));
});

final isAppLockEnabledUseCaseProvider = Provider<IsAppLockEnabledUseCase>((
  ref,
) {
  return IsAppLockEnabledUseCase(ref.watch(appLockRepositoryProvider));
});

final enableAppLockUseCaseProvider = Provider<EnableAppLockUseCase>((ref) {
  return EnableAppLockUseCase(ref.watch(appLockRepositoryProvider));
});

final unlockAppUseCaseProvider = Provider<UnlockAppUseCase>((ref) {
  return UnlockAppUseCase(ref.watch(appLockRepositoryProvider));
});

final disableAppLockUseCaseProvider = Provider<DisableAppLockUseCase>((ref) {
  return DisableAppLockUseCase(ref.watch(appLockRepositoryProvider));
});

final workspaceRemoteDataSourceProvider = Provider<WorkspaceRemoteDataSource>((
  ref,
) {
  return WorkspaceRemoteDataSource(ref.watch(apiTransportProvider));
});

final permissionRemoteDataSourceProvider = Provider<PermissionRemoteDataSource>(
  (ref) {
    return PermissionRemoteDataSource(ref.watch(apiTransportProvider));
  },
);

final workspaceRepositoryProvider = Provider<WorkspaceRepository>((ref) {
  return WorkspaceRepositoryImpl(ref.watch(workspaceRemoteDataSourceProvider));
});

final permissionRepositoryProvider = Provider<PermissionRepository>((ref) {
  return PermissionRepositoryImpl(
    ref.watch(permissionRemoteDataSourceProvider),
  );
});

final workspaceSessionRepositoryProvider = Provider<WorkspaceSessionRepository>(
  (ref) {
    return LocalWorkspaceSessionRepository(
      secureStore: ref.watch(secureKeyValueStoreProvider),
      database: ref.watch(appDatabaseProvider),
    );
  },
);

final loadWorkspaceSessionUseCaseProvider =
    Provider<LoadWorkspaceSessionUseCase>((ref) {
      return LoadWorkspaceSessionUseCase(
        workspaceRepository: ref.watch(workspaceRepositoryProvider),
        permissionRepository: ref.watch(permissionRepositoryProvider),
        sessionRepository: ref.watch(workspaceSessionRepositoryProvider),
      );
    });

final selectWorkspaceUseCaseProvider = Provider<SelectWorkspaceUseCase>((ref) {
  return SelectWorkspaceUseCase(
    permissionRepository: ref.watch(permissionRepositoryProvider),
    sessionRepository: ref.watch(workspaceSessionRepositoryProvider),
  );
});

final profileRemoteDataSourceProvider = Provider<ProfileRemoteDataSource>((
  ref,
) {
  return ProfileRemoteDataSource(ref.watch(apiTransportProvider));
});

final avatarRemoteDataSourceProvider = Provider<AvatarRemoteDataSource>((ref) {
  return AvatarRemoteDataSource(ref.watch(apiTransportProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepositoryImpl(ref.watch(profileRemoteDataSourceProvider));
});

final avatarPickerRepositoryProvider = Provider<AvatarPickerRepository>((ref) {
  return ImagePickerAvatarRepository();
});

final avatarUploadRepositoryProvider = Provider<AvatarUploadRepository>((ref) {
  return AvatarUploadRepositoryImpl(ref.watch(avatarRemoteDataSourceProvider));
});

final loadProfileUseCaseProvider = Provider<LoadProfileUseCase>((ref) {
  return LoadProfileUseCase(ref.watch(profileRepositoryProvider));
});

final updateProfileUseCaseProvider = Provider<UpdateProfileUseCase>((ref) {
  return UpdateProfileUseCase(ref.watch(profileRepositoryProvider));
});

final changeAvatarUseCaseProvider = Provider<ChangeAvatarUseCase>((ref) {
  return ChangeAvatarUseCase(
    pickerRepository: ref.watch(avatarPickerRepositoryProvider),
    uploadRepository: ref.watch(avatarUploadRepositoryProvider),
    profileRepository: ref.watch(profileRepositoryProvider),
    workspaceSessionRepository: ref.watch(workspaceSessionRepositoryProvider),
  );
});

final businessRemoteDataSourceProvider = Provider<BusinessRemoteDataSource>((
  ref,
) {
  return BusinessRemoteDataSource(ref.watch(apiTransportProvider));
});

final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  return BusinessRepositoryImpl(ref.watch(businessRemoteDataSourceProvider));
});

final loadBusinessDashboardUseCaseProvider =
    Provider<LoadBusinessDashboardUseCase>((ref) {
      return LoadBusinessDashboardUseCase(
        ref.watch(businessRepositoryProvider),
      );
    });

final createTicketUseCaseProvider = Provider<CreateTicketUseCase>((ref) {
  return CreateTicketUseCase(ref.watch(businessRepositoryProvider));
});

final testBotFlowUseCaseProvider = Provider<TestBotFlowUseCase>((ref) {
  return TestBotFlowUseCase(ref.watch(businessRepositoryProvider));
});

final publishBotFlowUseCaseProvider = Provider<PublishBotFlowUseCase>((ref) {
  return PublishBotFlowUseCase(ref.watch(businessRepositoryProvider));
});

final updateTicketStatusUseCaseProvider = Provider<UpdateTicketStatusUseCase>((
  ref,
) {
  return UpdateTicketStatusUseCase(ref.watch(businessRepositoryProvider));
});

final revokeApiTokenUseCaseProvider = Provider<RevokeApiTokenUseCase>((ref) {
  return RevokeApiTokenUseCase(ref.watch(businessRepositoryProvider));
});

final runCronJobUseCaseProvider = Provider<RunCronJobUseCase>((ref) {
  return RunCronJobUseCase(ref.watch(businessRepositoryProvider));
});

final updateCronJobStatusUseCaseProvider = Provider<UpdateCronJobStatusUseCase>(
  (ref) {
    return UpdateCronJobStatusUseCase(ref.watch(businessRepositoryProvider));
  },
);

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  return LocalAppSettingsRepository(ref.watch(appDatabaseProvider));
});

final loadAppSettingsUseCaseProvider = Provider<LoadAppSettingsUseCase>((ref) {
  return LoadAppSettingsUseCase(ref.watch(appSettingsRepositoryProvider));
});

final saveAppSettingsUseCaseProvider = Provider<SaveAppSettingsUseCase>((ref) {
  return SaveAppSettingsUseCase(ref.watch(appSettingsRepositoryProvider));
});

final clearWorkspaceCacheUseCaseProvider = Provider<ClearWorkspaceCacheUseCase>(
  (ref) {
    return ClearWorkspaceCacheUseCase(ref.watch(appDatabaseProvider));
  },
);

final mobileReleaseRemoteDataSourceProvider =
    Provider<MobileReleaseRemoteDataSource>((ref) {
      return MobileReleaseRemoteDataSource(ref.watch(apiTransportProvider));
    });

final checkMobileReleasePolicyUseCaseProvider =
    Provider<CheckMobileReleasePolicyUseCase>((ref) {
      final config = ref.watch(appConfigProvider);
      return CheckMobileReleasePolicyUseCase(
        remote: ref.watch(mobileReleaseRemoteDataSourceProvider),
        platform: _mobileReleasePlatform(),
        channel: config.releaseChannel,
        currentVersion: config.appVersion,
      );
    });

final conversationRemoteDataSourceProvider =
    Provider<ConversationRemoteDataSource>((ref) {
      return ConversationRemoteDataSource(ref.watch(apiTransportProvider));
    });

final conversationCacheDataSourceProvider =
    Provider<ConversationCacheDataSource>((ref) {
      return ConversationCacheDataSource(ref.watch(appDatabaseProvider));
    });

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return CachingConversationRepository(
    remote: ConversationRepositoryImpl(
      ref.watch(conversationRemoteDataSourceProvider),
    ),
    cache: ref.watch(conversationCacheDataSourceProvider),
  );
});

final messageAttachmentRemoteDataSourceProvider =
    Provider<MessageAttachmentRemoteDataSource>((ref) {
      return MessageAttachmentRemoteDataSource(ref.watch(apiTransportProvider));
    });

final messageAttachmentPickerRepositoryProvider =
    Provider<MessageAttachmentPickerRepository>((ref) {
      return ImagePickerMessageAttachmentRepository();
    });

final messageVoiceRecorderRepositoryProvider =
    Provider<MessageVoiceRecorderRepository>((ref) {
      final repository = AudioMessageAttachmentRepository();
      ref.onDispose(repository.dispose);
      return repository;
    });

final messageAttachmentRepositoryProvider =
    Provider<MessageAttachmentRepository>((ref) {
      return MessageAttachmentRepositoryImpl(
        ref.watch(messageAttachmentRemoteDataSourceProvider),
      );
    });

final callRemoteDataSourceProvider = Provider<CallRemoteDataSource>((ref) {
  return CallRemoteDataSource(ref.watch(apiTransportProvider));
});

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepositoryImpl(ref.watch(callRemoteDataSourceProvider));
});

final notificationRemoteDataSourceProvider =
    Provider<NotificationRemoteDataSource>((ref) {
      return NotificationRemoteDataSource(ref.watch(apiTransportProvider));
    });

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepositoryImpl(
    ref.watch(notificationRemoteDataSourceProvider),
  );
});

final workspaceSyncRemoteDataSourceProvider =
    Provider<WorkspaceSyncRemoteDataSource>((ref) {
      return WorkspaceSyncRemoteDataSource(ref.watch(apiTransportProvider));
    });

final localWorkspaceSyncCursorDataSourceProvider =
    Provider<LocalWorkspaceSyncCursorDataSource>((ref) {
      return LocalWorkspaceSyncCursorDataSource(ref.watch(appDatabaseProvider));
    });

final workspaceSyncRepositoryProvider = Provider<WorkspaceSyncRepository>((
  ref,
) {
  return WorkspaceSyncRepositoryImpl(
    remote: ref.watch(workspaceSyncRemoteDataSourceProvider),
    localCursor: ref.watch(localWorkspaceSyncCursorDataSourceProvider),
  );
});

final catchUpWorkspaceSyncUseCaseProvider =
    Provider<CatchUpWorkspaceSyncUseCase>((ref) {
      return CatchUpWorkspaceSyncUseCase(
        repository: ref.watch(workspaceSyncRepositoryProvider),
        deviceIdentityRepository: ref.watch(deviceIdentityRepositoryProvider),
      );
    });

final conversationRealtimeRepositoryProvider =
    Provider<ConversationRealtimeRepository>((ref) {
      final activeServerUri = ref.watch(activeServerUriProvider);
      final activeServerWsUri = ref.watch(activeServerWsUriProvider);
      final repository = WebSocketConversationRealtimeRepository(
        apiBaseUri: activeServerUri,
        wsBaseUri: activeServerWsUri,
        tokenRepository: ref.watch(authTokenRepositoryProvider),
      );
      ref.onDispose(() {
        unawaited(repository.disconnect());
      });
      return repository;
    });

final incomingCallRealtimeRepositoryProvider =
    Provider<ConversationRealtimeRepository>((ref) {
      final repository = WebSocketConversationRealtimeRepository(
        apiBaseUri: ref.watch(activeServerUriProvider),
        wsBaseUri: ref.watch(activeServerWsUriProvider),
        tokenRepository: ref.watch(authTokenRepositoryProvider),
      );
      ref.onDispose(() {
        unawaited(repository.disconnect());
      });
      return repository;
    });

final updatePresenceUseCaseProvider = Provider<UpdatePresenceUseCase>((ref) {
  return UpdatePresenceUseCase(
    conversationRepository: ref.watch(conversationRepositoryProvider),
    deviceIdentityRepository: ref.watch(deviceIdentityRepositoryProvider),
  );
});

final conversationDraftRepositoryProvider =
    Provider<ConversationDraftRepository>((ref) {
      return LocalConversationDraftRepository(ref.watch(appDatabaseProvider));
    });

final messageOutboxDataSourceProvider = Provider<MessageOutboxDataSource>((
  ref,
) {
  return MessageOutboxDataSource(ref.watch(appDatabaseProvider));
});

final messageOutboxRepositoryProvider = Provider<MessageOutboxRepository>((
  ref,
) {
  return LocalMessageOutboxRepository(
    ref.watch(messageOutboxDataSourceProvider),
  );
});

final loadMessageOutboxUseCaseProvider = Provider<LoadMessageOutboxUseCase>((
  ref,
) {
  return LoadMessageOutboxUseCase(ref.watch(messageOutboxRepositoryProvider));
});

final enqueueMessageOutboxUseCaseProvider =
    Provider<EnqueueMessageOutboxUseCase>((ref) {
      return EnqueueMessageOutboxUseCase(
        repository: ref.watch(messageOutboxRepositoryProvider),
      );
    });

final saveMessageOutboxItemUseCaseProvider =
    Provider<SaveMessageOutboxItemUseCase>((ref) {
      return SaveMessageOutboxItemUseCase(
        ref.watch(messageOutboxRepositoryProvider),
      );
    });

final deleteMessageOutboxItemUseCaseProvider =
    Provider<DeleteMessageOutboxItemUseCase>((ref) {
      return DeleteMessageOutboxItemUseCase(
        ref.watch(messageOutboxRepositoryProvider),
      );
    });

final newClientMessageIdUseCaseProvider = Provider<NewClientMessageIdUseCase>((
  ref,
) {
  return const NewClientMessageIdUseCase();
});

final loadConversationHomeUseCaseProvider =
    Provider<LoadConversationHomeUseCase>((ref) {
      return LoadConversationHomeUseCase(
        conversationRepository: ref.watch(conversationRepositoryProvider),
        workspaceSessionRepository: ref.watch(
          workspaceSessionRepositoryProvider,
        ),
      );
    });

final openDirectConversationUseCaseProvider =
    Provider<OpenDirectConversationUseCase>((ref) {
      return OpenDirectConversationUseCase(
        ref.watch(conversationRepositoryProvider),
      );
    });

final createChannelUseCaseProvider = Provider<CreateChannelUseCase>((ref) {
  return CreateChannelUseCase(ref.watch(conversationRepositoryProvider));
});

final requestJoinChannelUseCaseProvider = Provider<RequestJoinChannelUseCase>((
  ref,
) {
  return RequestJoinChannelUseCase(ref.watch(conversationRepositoryProvider));
});

final openPrivateChannelSessionUseCaseProvider =
    Provider<OpenPrivateChannelSessionUseCase>((ref) {
      return OpenPrivateChannelSessionUseCase(
        ref.watch(conversationRepositoryProvider),
      );
    });

final loadChannelDetailUseCaseProvider = Provider<LoadChannelDetailUseCase>((
  ref,
) {
  return LoadChannelDetailUseCase(ref.watch(conversationRepositoryProvider));
});

final inviteChannelMemberUseCaseProvider = Provider<InviteChannelMemberUseCase>(
  (ref) {
    return InviteChannelMemberUseCase(
      ref.watch(conversationRepositoryProvider),
    );
  },
);

final loadChannelJoinRequestsUseCaseProvider =
    Provider<LoadChannelJoinRequestsUseCase>((ref) {
      return LoadChannelJoinRequestsUseCase(
        ref.watch(conversationRepositoryProvider),
      );
    });

final approveChannelJoinRequestUseCaseProvider =
    Provider<ApproveChannelJoinRequestUseCase>((ref) {
      return ApproveChannelJoinRequestUseCase(
        ref.watch(conversationRepositoryProvider),
      );
    });

final rejectChannelJoinRequestUseCaseProvider =
    Provider<RejectChannelJoinRequestUseCase>((ref) {
      return RejectChannelJoinRequestUseCase(
        ref.watch(conversationRepositoryProvider),
      );
    });

final loadMessagesUseCaseProvider = Provider<LoadMessagesUseCase>((ref) {
  return LoadMessagesUseCase(ref.watch(conversationRepositoryProvider));
});

final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  return SendMessageUseCase(ref.watch(conversationRepositoryProvider));
});

final editMessageUseCaseProvider = Provider<EditMessageUseCase>((ref) {
  return EditMessageUseCase(ref.watch(conversationRepositoryProvider));
});

final deleteMessageUseCaseProvider = Provider<DeleteMessageUseCase>((ref) {
  return DeleteMessageUseCase(ref.watch(conversationRepositoryProvider));
});

final toggleReactionUseCaseProvider = Provider<ToggleReactionUseCase>((ref) {
  return ToggleReactionUseCase(ref.watch(conversationRepositoryProvider));
});

final togglePinMessageUseCaseProvider = Provider<TogglePinMessageUseCase>((
  ref,
) {
  return TogglePinMessageUseCase(ref.watch(conversationRepositoryProvider));
});

final forwardMessageUseCaseProvider = Provider<ForwardMessageUseCase>((ref) {
  return ForwardMessageUseCase(ref.watch(conversationRepositoryProvider));
});

final loadThreadUseCaseProvider = Provider<LoadThreadUseCase>((ref) {
  return LoadThreadUseCase(ref.watch(conversationRepositoryProvider));
});

final searchMessagesUseCaseProvider = Provider<SearchMessagesUseCase>((ref) {
  return SearchMessagesUseCase(ref.watch(conversationRepositoryProvider));
});

final pickMessageAttachmentUseCaseProvider =
    Provider<PickMessageAttachmentUseCase>((ref) {
      return PickMessageAttachmentUseCase(
        ref.watch(messageAttachmentPickerRepositoryProvider),
      );
    });

final startVoiceMessageRecordingUseCaseProvider =
    Provider<StartVoiceMessageRecordingUseCase>((ref) {
      return StartVoiceMessageRecordingUseCase(
        ref.watch(messageVoiceRecorderRepositoryProvider),
      );
    });

final stopVoiceMessageRecordingUseCaseProvider =
    Provider<StopVoiceMessageRecordingUseCase>((ref) {
      return StopVoiceMessageRecordingUseCase(
        ref.watch(messageVoiceRecorderRepositoryProvider),
      );
    });

final cancelVoiceMessageRecordingUseCaseProvider =
    Provider<CancelVoiceMessageRecordingUseCase>((ref) {
      return CancelVoiceMessageRecordingUseCase(
        ref.watch(messageVoiceRecorderRepositoryProvider),
      );
    });

final uploadMessageAttachmentUseCaseProvider =
    Provider<UploadMessageAttachmentUseCase>((ref) {
      return UploadMessageAttachmentUseCase(
        ref.watch(messageAttachmentRepositoryProvider),
      );
    });

final attachUploadedFileUseCaseProvider = Provider<AttachUploadedFileUseCase>((
  ref,
) {
  return AttachUploadedFileUseCase(
    ref.watch(messageAttachmentRepositoryProvider),
  );
});

final listMessageAttachmentsUseCaseProvider =
    Provider<ListMessageAttachmentsUseCase>((ref) {
      return ListMessageAttachmentsUseCase(
        ref.watch(messageAttachmentRepositoryProvider),
      );
    });

final listChannelMediaUseCaseProvider = Provider<ListChannelMediaUseCase>((
  ref,
) {
  return ListChannelMediaUseCase(
    ref.watch(messageAttachmentRepositoryProvider),
  );
});

final downloadMessageAttachmentBytesUseCaseProvider =
    Provider<DownloadMessageAttachmentBytesUseCase>((ref) {
      return DownloadMessageAttachmentBytesUseCase(
        ref.watch(messageAttachmentRepositoryProvider),
      );
    });

final newAttachmentUploadItemUseCaseProvider =
    Provider<NewAttachmentUploadItemUseCase>((ref) {
      return const NewAttachmentUploadItemUseCase();
    });

final startCallUseCaseProvider = Provider<StartCallUseCase>((ref) {
  return StartCallUseCase(ref.watch(callRepositoryProvider));
});

final getCallUseCaseProvider = Provider<GetCallUseCase>((ref) {
  return GetCallUseCase(ref.watch(callRepositoryProvider));
});

final findIncomingCallUseCaseProvider = Provider<FindIncomingCallUseCase>((
  ref,
) {
  return FindIncomingCallUseCase(ref.watch(callRepositoryProvider));
});

final acceptCallUseCaseProvider = Provider<AcceptCallUseCase>((ref) {
  return AcceptCallUseCase(ref.watch(callRepositoryProvider));
});

final endCallUseCaseProvider = Provider<EndCallUseCase>((ref) {
  return EndCallUseCase(ref.watch(callRepositoryProvider));
});

final rejectCallUseCaseProvider = Provider<RejectCallUseCase>((ref) {
  return RejectCallUseCase(ref.watch(callRepositoryProvider));
});

final sendCallSignalUseCaseProvider = Provider<SendCallSignalUseCase>((ref) {
  return SendCallSignalUseCase(ref.watch(callRepositoryProvider));
});

final listNotificationsUseCaseProvider = Provider<ListNotificationsUseCase>((
  ref,
) {
  return ListNotificationsUseCase(ref.watch(notificationRepositoryProvider));
});

final markNotificationReadUseCaseProvider =
    Provider<MarkNotificationReadUseCase>((ref) {
      return MarkNotificationReadUseCase(
        ref.watch(notificationRepositoryProvider),
      );
    });

final markAllNotificationsReadUseCaseProvider =
    Provider<MarkAllNotificationsReadUseCase>((ref) {
      return MarkAllNotificationsReadUseCase(
        ref.watch(notificationRepositoryProvider),
      );
    });

final loadNotificationPreferenceUseCaseProvider =
    Provider<LoadNotificationPreferenceUseCase>((ref) {
      return LoadNotificationPreferenceUseCase(
        ref.watch(notificationRepositoryProvider),
      );
    });

final saveNotificationPreferenceUseCaseProvider =
    Provider<SaveNotificationPreferenceUseCase>((ref) {
      return SaveNotificationPreferenceUseCase(
        ref.watch(notificationRepositoryProvider),
      );
    });

final listPushDevicesUseCaseProvider = Provider<ListPushDevicesUseCase>((ref) {
  return ListPushDevicesUseCase(ref.watch(notificationRepositoryProvider));
});

final unregisterPushDeviceUseCaseProvider =
    Provider<UnregisterPushDeviceUseCase>((ref) {
      return UnregisterPushDeviceUseCase(
        ref.watch(notificationRepositoryProvider),
      );
    });

final subscribeConversationRealtimeUseCaseProvider =
    Provider<SubscribeConversationRealtimeUseCase>((ref) {
      return SubscribeConversationRealtimeUseCase(
        ref.watch(conversationRealtimeRepositoryProvider),
      );
    });

final sendTypingUseCaseProvider = Provider<SendTypingUseCase>((ref) {
  return SendTypingUseCase(ref.watch(conversationRealtimeRepositoryProvider));
});

final markConversationReadUseCaseProvider =
    Provider<MarkConversationReadUseCase>((ref) {
      return MarkConversationReadUseCase(
        ref.watch(conversationRepositoryProvider),
      );
    });

final readDraftUseCaseProvider = Provider<ReadDraftUseCase>((ref) {
  return ReadDraftUseCase(ref.watch(conversationDraftRepositoryProvider));
});

final saveDraftUseCaseProvider = Provider<SaveDraftUseCase>((ref) {
  return SaveDraftUseCase(ref.watch(conversationDraftRepositoryProvider));
});

final clearDraftUseCaseProvider = Provider<ClearDraftUseCase>((ref) {
  return ClearDraftUseCase(ref.watch(conversationDraftRepositoryProvider));
});

String _mobileReleasePlatform() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    _ => 'android',
  };
}

Dio _configuredDio(Uri activeServerUri) {
  return Dio(
    BaseOptions(
      baseUrl: activeServerUri.toString(),
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );
}
