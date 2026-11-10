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
import '../../core/notifications/native_incoming_call_service.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/notifications/scoped_local_notification_service.dart';
import '../../core/platform/biometric_auth_service.dart';
import '../../core/platform/chat_share_intent_service.dart';
import '../../core/platform/external_url_launcher.dart';
import '../../core/platform/native_deep_link_service.dart';
import '../../core/platform/native_instance_binding_service.dart';
import '../../core/security/instance_scope.dart';
import '../../core/security/secure_key_value_store.dart';
import '../../core/security/server_account_registry.dart';
import '../../features/auth/application/legal_acceptance_access_policy.dart';

import '../../features/auth/application/use_cases/app_lock_timeout_use_cases.dart';

import '../../features/auth/application/session_termination.dart';

import '../../features/auth/application/use_cases/app_lock_use_cases.dart';
import '../../features/auth/application/use_cases/delete_account_use_case.dart';
import '../../features/auth/application/use_cases/device_approval_use_cases.dart';
import '../../features/auth/application/use_cases/email_verification_use_cases.dart';
import '../../features/auth/application/use_cases/legal_acceptance_use_cases.dart';
import '../../features/auth/application/use_cases/load_legal_document_versions_use_case.dart';
import '../../features/auth/application/use_cases/login_use_case.dart';
import '../../features/auth/application/use_cases/logout_use_case.dart';
import '../../features/auth/application/use_cases/oidc_login_use_case.dart';
import '../../features/auth/application/use_cases/qr_login_use_cases.dart';
import '../../features/auth/application/use_cases/refresh_access_token_use_case.dart';
import '../../features/auth/application/use_cases/register_use_case.dart';
import '../../features/auth/application/use_cases/session_use_cases.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/datasources/device_approval_remote_data_source.dart';
import '../../features/auth/data/datasources/email_verification_remote_data_source.dart';
import '../../features/auth/data/datasources/qr_login_remote_data_source.dart';
import '../../features/auth/data/interceptors/legal_acceptance_interceptor.dart';
import '../../features/auth/data/network/auth_refresh_interceptor.dart';
import '../../features/auth/data/repositories/account_repository_impl.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/data/repositories/core2_auth_repositories.dart';
import '../../features/auth/data/repositories/local_session_state_repository.dart';
import '../../features/auth/data/repositories/secure_app_lock_repository.dart';
import '../../features/auth/data/repositories/secure_app_lock_timeout_repository.dart';
import '../../features/auth/data/repositories/secure_auth_token_repository.dart';
import '../../features/auth/data/repositories/secure_device_identity_repository.dart';
import '../../features/auth/domain/entities/app_lock_timeout_policy.dart';
import '../../features/auth/domain/repositories/account_repository.dart';
import '../../features/auth/domain/repositories/app_lock_repository.dart';
import '../../features/auth/domain/repositories/app_lock_timeout_repository.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/repositories/auth_token_repository.dart';
import '../../features/auth/domain/repositories/device_approval_repository.dart';
import '../../features/auth/domain/repositories/device_identity_repository.dart';
import '../../features/auth/domain/repositories/email_verification_repository.dart';
import '../../features/auth/domain/repositories/qr_login_repository.dart';
import '../../features/auth/domain/repositories/session_state_repository.dart';
import '../../features/business/application/use_cases/business_dashboard_use_cases.dart';
import '../../features/business/data/datasources/business_remote_data_source.dart';
import '../../features/business/data/repositories/business_repository_impl.dart';
import '../../features/business/domain/repositories/business_repository.dart';
import '../../features/call_privacy/application/use_cases/call_privacy_use_cases.dart';
import '../../features/call_privacy/data/datasources/call_privacy_remote_data_source.dart';
import '../../features/call_privacy/data/repositories/call_privacy_repository_impl.dart';
import '../../features/call_privacy/domain/repositories/call_privacy_repository.dart';
import '../../features/conversations/application/use_cases/call_use_cases.dart';
import '../../features/conversations/application/use_cases/channel_use_cases.dart';
import '../../features/conversations/application/use_cases/collaboration_document_history_use_cases.dart';
import '../../features/conversations/application/use_cases/collaboration_task_use_cases.dart';
import '../../features/conversations/application/use_cases/load_conversation_home_use_case.dart';
import '../../features/conversations/application/use_cases/message_attachment_use_cases.dart';
import '../../features/conversations/application/use_cases/message_outbox_dispatcher.dart';
import '../../features/conversations/application/use_cases/message_outbox_use_cases.dart';
import '../../features/conversations/application/use_cases/message_use_cases.dart';
import '../../features/conversations/application/use_cases/open_direct_conversation_use_case.dart';
import '../../features/conversations/application/use_cases/presence_use_cases.dart';

import '../../features/conversations/application/use_cases/rich_message_use_cases.dart';

import '../../features/conversations/application/use_cases/secret_message_use_cases.dart';

import '../../features/conversations/data/datasources/call_remote_data_source.dart';
import '../../features/conversations/data/datasources/collaboration_document_history_remote_data_source.dart';
import '../../features/conversations/data/datasources/conversation_cache_data_source.dart';
import '../../features/conversations/data/datasources/conversation_remote_data_source.dart';
import '../../features/conversations/data/datasources/message_attachment_remote_data_source.dart';
import '../../features/conversations/data/datasources/message_outbox_data_source.dart';
import '../../features/conversations/data/datasources/rich_message_remote_data_source.dart';
import '../../features/conversations/data/files/scoped_attachment_file_store.dart';
import '../../features/conversations/data/repositories/audio_message_attachment_repository.dart';
import '../../features/conversations/data/repositories/caching_conversation_repository.dart';
import '../../features/conversations/data/repositories/call_repository_impl.dart';
import '../../features/conversations/data/repositories/collaboration_document_history_repository_impl.dart';
import '../../features/conversations/data/repositories/collaboration_task_repository_impl.dart';
import '../../features/conversations/data/repositories/conversation_repository_impl.dart';
import '../../features/conversations/data/repositories/image_picker_message_attachment_repository.dart';
import '../../features/conversations/data/repositories/local_conversation_draft_repository.dart';
import '../../features/conversations/data/repositories/local_message_outbox_repository.dart';
import '../../features/conversations/data/repositories/message_attachment_repository_impl.dart';

import '../../features/conversations/data/repositories/rich_message_repository_impl.dart';

import '../../features/conversations/data/repositories/secret_message_repository_impl.dart';

import '../../features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import '../../features/conversations/domain/repositories/call_repository.dart';
import '../../features/conversations/domain/repositories/collaboration_document_history_repository.dart';
import '../../features/conversations/domain/repositories/collaboration_task_repository.dart';
import '../../features/conversations/domain/repositories/conversation_repository.dart';
import '../../features/conversations/domain/repositories/message_attachment_repository.dart';
import '../../features/conversations/domain/repositories/message_outbox_repository.dart';
import '../../features/conversations/domain/repositories/rich_message_repository.dart';
import '../../features/customer_tickets/application/use_cases/customer_ticket_use_cases.dart';
import '../../features/customer_tickets/data/datasources/customer_ticket_remote_data_source.dart';
import '../../features/customer_tickets/data/repositories/customer_ticket_repository_impl.dart';
import '../../features/customer_tickets/data/repositories/image_picker_customer_ticket_image_repository.dart';
import '../../features/customer_tickets/data/repositories/public_customer_ticket_image_repository.dart';
import '../../features/customer_tickets/data/repositories/web_socket_customer_ticket_realtime_repository.dart';
import '../../features/customer_tickets/domain/repositories/customer_ticket_repository.dart';
import '../../features/mfa/application/mfa_use_cases.dart';
import '../../features/mfa/data/mfa_repository_impl.dart';
import '../../features/moderation/application/use_cases/moderation_use_cases.dart';
import '../../features/moderation/data/datasources/moderation_remote_data_source.dart';
import '../../features/moderation/data/repositories/moderation_repository_impl.dart';
import '../../features/moderation/domain/repositories/moderation_repository.dart';
import '../../features/my_notes/application/use_cases/my_notes_use_cases.dart';
import '../../features/my_notes/data/datasources/my_notes_cache_data_source.dart';
import '../../features/my_notes/data/datasources/my_notes_remote_data_source.dart';
import '../../features/my_notes/data/repositories/my_notes_repository_impl.dart';
import '../../features/my_notes/domain/repositories/my_notes_repository.dart';
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
import '../../features/sync/application/workspace_refresh_signal.dart';
import '../../features/sync/data/datasources/local_workspace_sync_cursor_data_source.dart';
import '../../features/sync/data/datasources/workspace_sync_remote_data_source.dart';
import '../../features/sync/data/repositories/workspace_sync_repository_impl.dart';
import '../../features/sync/domain/repositories/workspace_sync_repository.dart';
import '../../features/workspace/application/use_cases/invite_use_cases.dart';
import '../../features/workspace/application/use_cases/load_workspace_session_use_case.dart';
import '../../features/workspace/application/use_cases/select_workspace_use_case.dart';
import '../../features/workspace/data/datasources/invite_remote_data_source.dart';
import '../../features/workspace/data/datasources/permission_remote_data_source.dart';
import '../../features/workspace/data/datasources/workspace_remote_data_source.dart';
import '../../features/workspace/data/repositories/invite_repository_impl.dart';
import '../../features/workspace/data/repositories/local_workspace_session_repository.dart';
import '../../features/workspace/data/repositories/permission_repository_impl.dart';
import '../../features/workspace/data/repositories/workspace_repository_impl.dart';
import '../../features/workspace/domain/repositories/invite_repository.dart';
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

final class ActiveServerRuntime {
  const ActiveServerRuntime({
    required this.apiBaseUri,
    required this.wsBaseUri,
    required this.discovery,
  });

  factory ActiveServerRuntime.fromDiscovery(
    SelfHostedServerDiscovery discovery,
  ) {
    return ActiveServerRuntime(
      apiBaseUri: discovery.apiBaseUri,
      wsBaseUri: discovery.wsBaseUri,
      discovery: discovery,
    );
  }

  final Uri apiBaseUri;
  final Uri wsBaseUri;
  final SelfHostedServerDiscovery? discovery;
}

final initialServerDiscoveryProvider = Provider<SelfHostedServerDiscovery?>(
  (_) => null,
);

final secretMessageUseCasesProvider = Provider<SecretMessageUseCases>(
  (ref) => SecretMessageUseCases(
    SecretMessageRepositoryImpl(
      ref.watch(apiTransportProvider),
      ref.watch(deviceIdentityRepositoryProvider),
    ),
  ),
);

final mfaUseCasesProvider = Provider<MfaUseCases>(
  (ref) => MfaUseCases(
    MfaRepositoryImpl(
      ref.watch(apiTransportProvider),
      ref.watch(deviceIdentityRepositoryProvider),
    ),
  ),
);

final activeServerRuntimeProvider = StateProvider<ActiveServerRuntime>((ref) {
  final discovery = ref.watch(initialServerDiscoveryProvider);
  if (discovery != null) {
    return ActiveServerRuntime.fromDiscovery(discovery);
  }
  final config = ref.watch(appConfigProvider);
  return ActiveServerRuntime(
    apiBaseUri: config.apiBaseUri,
    wsBaseUri: config.wsBaseUri,
    discovery: null,
  );
});

final activeServerUriProvider = Provider<Uri>((ref) {
  return ref.watch(activeServerRuntimeProvider).apiBaseUri;
});

final activeServerWsUriProvider = Provider<Uri>((ref) {
  return ref.watch(activeServerRuntimeProvider).wsBaseUri;
});

final activeServerDiscoveryProvider = Provider<SelfHostedServerDiscovery?>((
  ref,
) {
  return ref.watch(activeServerRuntimeProvider).discovery;
});

final selfHostedServerDiscoveryClientProvider =
    Provider<SelfHostedServerDiscoveryClient>((ref) {
      return SelfHostedServerDiscoveryClient(
        mobileVersion: ref.watch(appConfigProvider).appVersion,
      );
    });

final activeInstanceScopeProvider = Provider<InstanceScope>((ref) {
  final discovery = ref.watch(activeServerDiscoveryProvider);
  if (discovery == null) {
    throw StateError('A validated server discovery is required.');
  }
  return discovery.instanceScope;
});

final legalAcceptanceAccessPolicyProvider =
    Provider<LegalAcceptanceAccessPolicy>((ref) {
      final policy = LegalAcceptanceAccessPolicy();
      ref.onDispose(policy.dispose);
      return policy;
    });

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
      expectedInstanceScope: ref.watch(activeInstanceScopeProvider),
      tokenRepository: tokenRepository,
      refreshAccessTokenUseCase: refreshUseCase,
      onSessionRevoked: (failure, guard) => ref
          .read(sessionTerminationCoordinatorProvider)
          .endSession(SessionEndedNotice.fromFailure(failure), guard: guard),
      onDeviceApprovalPending: () => ref
          .read(sessionTerminationCoordinatorProvider)
          .reportApprovalPending(),
    ),
    LegalAcceptanceInterceptor(ref.watch(legalAcceptanceAccessPolicyProvider)),
    RedactingDioLogInterceptor(logger),
  ]);
  ref.onDispose(() => dio.close(force: true));

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
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final releaseDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final releaseUri = Uri.parse(config.releaseServiceBaseUrl);
  if (releaseUri.scheme != 'https' || releaseUri.host.isEmpty) {
    throw StateError('WEBTUI_RELEASE_SERVICE_URL must be a public HTTPS URL.');
  }
  final dio = _configuredDio(releaseUri);
  dio.interceptors.addAll([
    RequestIdInterceptor(ref.watch(requestIdGeneratorProvider)),
    RedactingDioLogInterceptor(ref.watch(redactingLoggerProvider)),
  ]);
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final apiTransportProvider = Provider<ApiTransport>((ref) {
  return DioApiTransport(ref.watch(dioProvider));
});

final authApiTransportProvider = Provider<ApiTransport>((ref) {
  return DioApiTransport(ref.watch(authDioProvider));
});

final releaseApiTransportProvider = Provider<ApiTransport>((ref) {
  return DioApiTransport(ref.watch(releaseDioProvider));
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
    instanceScope: ref.watch(activeInstanceScopeProvider),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

final notificationPermissionStatusProvider = FutureProvider.autoDispose<String>(
  (ref) =>
      ref.watch(pushNotificationServiceProvider).notificationPermissionStatus(),
);

final externalUrlLauncherProvider = Provider<ExternalUrlLauncher>((_) {
  return const MethodChannelExternalUrlLauncher();
});

final chatShareIntentServiceProvider = Provider<ChatShareIntentService>((ref) {
  final service = ChatShareIntentService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final biometricAuthServiceProvider = Provider<BiometricAuthService>((_) {
  return const BiometricAuthService();
});

final nativeDeepLinkServiceProvider = Provider<NativeDeepLinkService>((ref) {
  final service = NativeDeepLinkService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final nativeInstanceBindingServiceProvider =
    Provider<NativeInstanceBindingService>((_) {
      return const NativeInstanceBindingService();
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
  return SecureAuthTokenRepository(
    ref.watch(secureKeyValueStoreProvider),
    setNativeSessionDurable: (durable) => ref
        .read(nativeInstanceBindingServiceProvider)
        .setSessionDurability(durable),
  );
});

final authAccessTokenProvider = FutureProvider<String?>((ref) {
  return ref.watch(authTokenRepositoryProvider).readAccessToken();
});

final deviceIdentityRepositoryProvider = Provider<DeviceIdentityRepository>((
  ref,
) {
  return SecureDeviceIdentityRepository(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    loadInstanceScope: () => ref.read(activeInstanceScopeProvider),
  );
});

final sessionStateRepositoryProvider = Provider<SessionStateRepository>((ref) {
  return LocalSessionStateRepository(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    database: ref.watch(appDatabaseProvider),
    loadInstanceScope: () =>
        ref.read(activeServerDiscoveryProvider)?.instanceScope,
    clearNativeInstanceBinding: () =>
        ref.read(nativeInstanceBindingServiceProvider).clear(),
    terminateNativeCalls:
        NativeIncomingCallService.terminateCallsForSessionInvalidation,
    clearMessageNotifications: () =>
        ScopedLocalNotificationService.instance.clearMessageNotifications(),
    clearScopedAttachmentFiles: const ScopedAttachmentFileStore().clearScope,
    serverAccountRegistry: ref.watch(serverAccountRegistryProvider),
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

final loadLegalDocumentVersionsUseCaseProvider =
    Provider<LoadLegalDocumentVersionsUseCase>((ref) {
      return LoadLegalDocumentVersionsUseCase(
        ref.watch(authRepositoryProvider),
      );
    });

final loadLegalAcceptanceUseCaseProvider = Provider<LoadLegalAcceptanceUseCase>(
  (ref) {
    return LoadLegalAcceptanceUseCase(ref.watch(authSessionRepositoryProvider));
  },
);

final acceptLegalDocumentsUseCaseProvider =
    Provider<AcceptLegalDocumentsUseCase>((ref) {
      return AcceptLegalDocumentsUseCase(
        ref.watch(authSessionRepositoryProvider),
      );
    });

final oidcLoginUseCaseProvider = Provider<OidcLoginUseCase>((ref) {
  return OidcLoginUseCase(
    authRepository: ref.watch(authRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
    deviceIdentityRepository: ref.watch(deviceIdentityRepositoryProvider),
    loadExpectedServerOrigin: () =>
        ref.read(activeServerDiscoveryProvider)?.instanceScope.origin,
  );
});

final refreshAccessTokenUseCaseProvider = Provider<RefreshAccessTokenUseCase>((
  ref,
) {
  return RefreshAccessTokenUseCase(
    authRepository: ref.watch(authRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
    // Refresh bị 401 (mọi mã) = phiên bị thu hồi / phải đăng nhập lại.
    onRefreshRejected: (failure, guard) async {
      await ref
          .read(sessionTerminationCoordinatorProvider)
          .endSession(SessionEndedNotice.fromFailure(failure), guard: guard);
    },
  );
});

/// Nơi duy nhất kết thúc phiên bị thu hồi (2.1) / phải đăng nhập lại (2.8).
final sessionTerminationCoordinatorProvider =
    Provider<SessionTerminationCoordinator>((ref) {
      final coordinator = SessionTerminationCoordinator(
        sessionStateRepository: ref.watch(sessionStateRepositoryProvider),
        tokenRepository: ref.watch(authTokenRepositoryProvider),
      );
      ref.onDispose(() => unawaited(coordinator.dispose()));
      return coordinator;
    });

final sessionEndedNoticesProvider = StreamProvider<SessionEndedNotice>((ref) {
  return ref.watch(sessionTerminationCoordinatorProvider).endedSessions;
});

/// Mỗi lần máy chủ trả `403 DEVICE_APPROVAL_PENDING` thì số đếm tăng.
final deviceApprovalPendingSignalsProvider = StreamProvider<int>((ref) {
  var count = 0;
  return ref
      .watch(sessionTerminationCoordinatorProvider)
      .approvalPendingSignals
      .map((_) => ++count);
});

final qrLoginRepositoryProvider = Provider<QrLoginRepository>((ref) {
  return QrLoginRepositoryImpl(
    QrLoginRemoteDataSource(ref.watch(apiTransportProvider)),
  );
});

final readQrLoginPayloadUseCaseProvider = Provider<ReadQrLoginPayloadUseCase>((
  ref,
) {
  return ReadQrLoginPayloadUseCase(
    loadServerOrigin: () =>
        ref.read(activeServerDiscoveryProvider)?.instanceScope.origin,
  );
});

final scanQrLoginUseCaseProvider = Provider<ScanQrLoginUseCase>((ref) {
  return ScanQrLoginUseCase(ref.watch(qrLoginRepositoryProvider));
});

final decideQrLoginUseCaseProvider = Provider<DecideQrLoginUseCase>((ref) {
  return DecideQrLoginUseCase(ref.watch(qrLoginRepositoryProvider));
});

final deviceApprovalRepositoryProvider = Provider<DeviceApprovalRepository>((
  ref,
) {
  return DeviceApprovalRepositoryImpl(
    DeviceApprovalRemoteDataSource(ref.watch(apiTransportProvider)),
  );
});

final loadMyDeviceApprovalUseCaseProvider =
    Provider<LoadMyDeviceApprovalUseCase>((ref) {
      return LoadMyDeviceApprovalUseCase(
        ref.watch(deviceApprovalRepositoryProvider),
      );
    });

final listPendingDeviceApprovalsUseCaseProvider =
    Provider<ListPendingDeviceApprovalsUseCase>((ref) {
      return ListPendingDeviceApprovalsUseCase(
        ref.watch(deviceApprovalRepositoryProvider),
      );
    });

final findDeviceApprovalRequestUseCaseProvider =
    Provider<FindDeviceApprovalRequestUseCase>((ref) {
      return FindDeviceApprovalRequestUseCase(
        ref.watch(deviceApprovalRepositoryProvider),
      );
    });

final decideDeviceApprovalUseCaseProvider =
    Provider<DecideDeviceApprovalUseCase>((ref) {
      return DecideDeviceApprovalUseCase(
        ref.watch(deviceApprovalRepositoryProvider),
      );
    });

final emailVerificationRepositoryProvider =
    Provider<EmailVerificationRepository>((ref) {
      return EmailVerificationRepositoryImpl(
        EmailVerificationRemoteDataSource(ref.watch(authApiTransportProvider)),
      );
    });

final verifyEmailCodeUseCaseProvider = Provider<VerifyEmailCodeUseCase>((ref) {
  return VerifyEmailCodeUseCase(
    repository: ref.watch(emailVerificationRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
    deviceIdentityRepository: ref.watch(deviceIdentityRepositoryProvider),
  );
});

final resendEmailCodeUseCaseProvider = Provider<ResendEmailCodeUseCase>((ref) {
  return ResendEmailCodeUseCase(ref.watch(emailVerificationRepositoryProvider));
});

final inviteRepositoryProvider = Provider<InviteRepository>((ref) {
  return InviteRepositoryImpl(
    InviteRemoteDataSource(ref.watch(apiTransportProvider)),
  );
});

final previewInviteUseCaseProvider = Provider<PreviewInviteUseCase>((ref) {
  return PreviewInviteUseCase(
    ref.watch(inviteRepositoryProvider),
    loadServerHost: () =>
        ref.read(activeServerDiscoveryProvider)?.instanceScope.origin.host,
  );
});

final acceptInviteUseCaseProvider = Provider<AcceptInviteUseCase>((ref) {
  return AcceptInviteUseCase(ref.watch(inviteRepositoryProvider));
});

final logoutUseCaseProvider = Provider<LogoutUseCase>((ref) {
  return LogoutUseCase(
    authRepository: ref.watch(authRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
    sessionStateRepository: ref.watch(sessionStateRepositoryProvider),
  );
});

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepositoryImpl(ref.watch(apiTransportProvider));
});

final deleteAccountUseCaseProvider = Provider<DeleteAccountUseCase>((ref) {
  return DeleteAccountUseCase(
    accountRepository: ref.watch(accountRepositoryProvider),
    tokenRepository: ref.watch(authTokenRepositoryProvider),
    sessionStateRepository: ref.watch(sessionStateRepositoryProvider),
    appLockRepository: ref.watch(appLockRepositoryProvider),
  );
});

final listSessionsUseCaseProvider = Provider<ListSessionsUseCase>((ref) {
  return ListSessionsUseCase(ref.watch(authSessionRepositoryProvider));
});

final revokeSessionUseCaseProvider = Provider<RevokeSessionUseCase>((ref) {
  return RevokeSessionUseCase(ref.watch(authSessionRepositoryProvider));
});

final revokeDeviceSessionUseCaseProvider = Provider<RevokeDeviceSessionUseCase>(
  (ref) {
    return RevokeDeviceSessionUseCase(
      authRepository: ref.watch(authSessionRepositoryProvider),
      signOutThisDevice: () => ref.read(logoutUseCaseProvider).execute(),
    );
  },
);

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

final serverAccountRegistryProvider = Provider<SecureServerAccountRegistry>((
  ref,
) {
  return SecureServerAccountRegistry(ref.watch(secureKeyValueStoreProvider));
});

final isAppLockEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(isAppLockEnabledUseCaseProvider).execute();
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

// Lõi 3.1: thời gian tự khoá (người dùng chọn ≤ mức máy chủ trong discovery).
final appLockTimeoutRepositoryProvider = Provider<AppLockTimeoutRepository>((
  ref,
) {
  return SecureAppLockTimeoutRepository(ref.watch(secureKeyValueStoreProvider));
});

final loadAppLockIdleMinutesUseCaseProvider =
    Provider<LoadAppLockIdleMinutesUseCase>((ref) {
      return LoadAppLockIdleMinutesUseCase(
        ref.watch(appLockTimeoutRepositoryProvider),
      );
    });

final saveAppLockIdleMinutesUseCaseProvider =
    Provider<SaveAppLockIdleMinutesUseCase>((ref) {
      return SaveAppLockIdleMinutesUseCase(
        ref.watch(appLockTimeoutRepositoryProvider),
      );
    });

/// Mức người dùng đã chọn (null = chưa chọn).
final appLockIdleMinutesProvider = FutureProvider<int?>((ref) {
  return ref.watch(loadAppLockIdleMinutesUseCaseProvider).execute();
});

/// Mức tối đa máy chủ cho phép (0 = máy chủ không ép).
final appLockServerMaxMinutesProvider = Provider<int>((ref) {
  return ref
          .watch(activeServerDiscoveryProvider)
          ?.privacyPolicy
          .idleLockMinutes ??
      0;
});

/// Số phút tự khoá đang có hiệu lực.
final effectiveAppLockMinutesProvider = Provider<int>((ref) {
  return AppLockTimeoutPolicy.effectiveMinutes(
    serverMaxMinutes: ref.watch(appLockServerMaxMinutesProvider),
    userMinutes: ref.watch(appLockIdleMinutesProvider).valueOrNull,
  );
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
      instanceScope: ref.watch(activeInstanceScopeProvider),
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
  return ProfileRemoteDataSource(
    ref.watch(apiTransportProvider),
    loadWorkspaceId: ref
        .watch(workspaceSessionRepositoryProvider)
        .readActiveWorkspaceId,
  );
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
    return ClearWorkspaceCacheUseCase(
      ref.watch(appDatabaseProvider),
      ref.watch(activeInstanceScopeProvider),
    );
  },
);

final mobileReleaseRemoteDataSourceProvider =
    Provider<MobileReleaseRemoteDataSource>((ref) {
      return MobileReleaseRemoteDataSource(
        ref.watch(releaseApiTransportProvider),
      );
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
      return ConversationCacheDataSource(
        ref.watch(appDatabaseProvider),
        ref.watch(activeInstanceScopeProvider),
      );
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

final richMessageRemoteDataSourceProvider =
    Provider<RichMessageRemoteDataSource>((ref) {
      return RichMessageRemoteDataSource(ref.watch(apiTransportProvider));
    });

final richMessageRepositoryProvider = Provider<RichMessageRepository>((ref) {
  return RichMessageRepositoryImpl(
    ref.watch(richMessageRemoteDataSourceProvider),
  );
});

final collaborationDocumentHistoryRemoteDataSourceProvider =
    Provider<CollaborationDocumentHistoryRemoteDataSource>((ref) {
      return CollaborationDocumentHistoryRemoteDataSource(
        ref.watch(apiTransportProvider),
      );
    });

final collaborationDocumentHistoryRepositoryProvider =
    Provider<CollaborationDocumentHistoryRepository>((ref) {
      return CollaborationDocumentHistoryRepositoryImpl(
        ref.watch(collaborationDocumentHistoryRemoteDataSourceProvider),
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

// Lõi 3.5: ai được gọi cho tôi.
final callPrivacyRemoteDataSourceProvider =
    Provider<CallPrivacyRemoteDataSource>(
      (ref) => CallPrivacyRemoteDataSource(ref.watch(apiTransportProvider)),
    );

final callPrivacyRepositoryProvider = Provider<CallPrivacyRepository>((ref) {
  return CallPrivacyRepositoryImpl(
    ref.watch(callPrivacyRemoteDataSourceProvider),
  );
});

final loadCallPrivacyUseCaseProvider = Provider<LoadCallPrivacyUseCase>((ref) {
  return LoadCallPrivacyUseCase(ref.watch(callPrivacyRepositoryProvider));
});

final updateCallPrivacyUseCaseProvider = Provider<UpdateCallPrivacyUseCase>((
  ref,
) {
  return UpdateCallPrivacyUseCase(ref.watch(callPrivacyRepositoryProvider));
});

final moderationRemoteDataSourceProvider = Provider<ModerationRemoteDataSource>(
  (ref) => ModerationRemoteDataSource(ref.watch(apiTransportProvider)),
);

final moderationRepositoryProvider = Provider<ModerationRepository>((ref) {
  return ModerationRepositoryImpl(
    ref.watch(moderationRemoteDataSourceProvider),
  );
});

final createModerationReportUseCaseProvider =
    Provider<CreateModerationReportUseCase>((ref) {
      return CreateModerationReportUseCase(
        ref.watch(moderationRepositoryProvider),
      );
    });

final listBlockedUsersUseCaseProvider = Provider<ListBlockedUsersUseCase>((
  ref,
) {
  return ListBlockedUsersUseCase(ref.watch(moderationRepositoryProvider));
});

final blockUserUseCaseProvider = Provider<BlockUserUseCase>((ref) {
  return BlockUserUseCase(ref.watch(moderationRepositoryProvider));
});

final unblockUserUseCaseProvider = Provider<UnblockUserUseCase>((ref) {
  return UnblockUserUseCase(ref.watch(moderationRepositoryProvider));
});

// My Note: sổ ghi chú cá nhân, có bản lưu trên máy theo máy chủ + workspace.
final myNotesRepositoryProvider = Provider<MyNotesRepository>((ref) {
  return MyNotesRepositoryImpl(
    remote: MyNotesRemoteDataSource(ref.watch(apiTransportProvider)),
    cache: MyNotesCacheDataSource(
      ref.watch(appDatabaseProvider),
      ref.watch(activeInstanceScopeProvider),
    ),
  );
});

final myNotesUseCasesProvider = Provider<MyNotesUseCases>((ref) {
  return MyNotesUseCases(ref.watch(myNotesRepositoryProvider));
});

final workspaceSyncRemoteDataSourceProvider =
    Provider<WorkspaceSyncRemoteDataSource>((ref) {
      return WorkspaceSyncRemoteDataSource(ref.watch(apiTransportProvider));
    });

final localWorkspaceSyncCursorDataSourceProvider =
    Provider<LocalWorkspaceSyncCursorDataSource>((ref) {
      return LocalWorkspaceSyncCursorDataSource(
        ref.watch(appDatabaseProvider),
        ref.watch(activeInstanceScopeProvider),
      );
    });

final workspaceSyncRepositoryProvider = Provider<WorkspaceSyncRepository>((
  ref,
) {
  return WorkspaceSyncRepositoryImpl(
    remote: ref.watch(workspaceSyncRemoteDataSourceProvider),
    localCursor: ref.watch(localWorkspaceSyncCursorDataSourceProvider),
  );
});

final workspaceRefreshSignalProvider = Provider<WorkspaceRefreshSignal>((ref) {
  final signal = WorkspaceRefreshSignal();
  ref.onDispose(() => unawaited(signal.dispose()));
  return signal;
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
        instanceScope: ref.watch(activeInstanceScopeProvider),
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
        instanceScope: ref.watch(activeInstanceScopeProvider),
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
      return LocalConversationDraftRepository(
        ref.watch(appDatabaseProvider),
        ref.watch(activeInstanceScopeProvider),
      );
    });

final messageOutboxDataSourceProvider = Provider<MessageOutboxDataSource>((
  ref,
) {
  return MessageOutboxDataSource(
    ref.watch(appDatabaseProvider),
    ref.watch(activeInstanceScopeProvider),
    ref.watch(secureKeyValueStoreProvider),
  );
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
        instanceScopeId: ref.watch(activeInstanceScopeProvider).storageId,
      );
    });

final saveMessageOutboxItemUseCaseProvider =
    Provider<SaveMessageOutboxItemUseCase>((ref) {
      return SaveMessageOutboxItemUseCase(
        ref.watch(messageOutboxRepositoryProvider),
      );
    });

final canDispatchMessageOutboxItemUseCaseProvider =
    Provider<CanDispatchMessageOutboxItemUseCase>((ref) {
      return CanDispatchMessageOutboxItemUseCase(
        ref.watch(messageOutboxRepositoryProvider),
      );
    });

final deleteMessageOutboxItemUseCaseProvider =
    Provider<DeleteMessageOutboxItemUseCase>((ref) {
      return DeleteMessageOutboxItemUseCase(
        ref.watch(messageOutboxRepositoryProvider),
      );
    });

/// Bộ gửi lại tin chờ cho toàn app (mọi hội thoại), dùng chung bởi màn chính và
/// các phòng chat.
final messageOutboxDispatcherProvider = Provider<MessageOutboxDispatcher>((
  ref,
) {
  final sendMessage = ref.watch(sendMessageUseCaseProvider);
  final attachUploadedFile = ref.watch(attachUploadedFileUseCaseProvider);
  final legalPolicy = ref.watch(legalAcceptanceAccessPolicyProvider);
  final dispatcher = MessageOutboxDispatcher(
    repository: ref.watch(messageOutboxRepositoryProvider),
    sendMessage: (item) => sendMessage.execute(
      workspaceId: item.workspaceId,
      channelId: item.channelId,
      body: item.body,
      clientMessageId: item.clientMessageId,
      parentId: item.parentId,
      silent: item.silent,
    ),
    attachFile: (item, message, attachment) => attachUploadedFile.execute(
      workspaceId: item.workspaceId,
      channelId: item.channelId,
      messageId: message.id,
      fileId: attachment.fileId,
      sortOrder: attachment.sortOrder,
    ),
    canCreateUserContent: () => legalPolicy.canCreateUserContent,
  );
  ref.onDispose(dispatcher.dispose);
  return dispatcher;
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

final listChannelMembersUseCaseProvider = Provider<ListChannelMembersUseCase>((
  ref,
) {
  return ListChannelMembersUseCase(ref.watch(conversationRepositoryProvider));
});

final collaborationTaskRepositoryProvider =
    Provider<CollaborationTaskRepository>((ref) {
      return CollaborationTaskRepositoryImpl(
        ref.watch(conversationRemoteDataSourceProvider),
      );
    });

final listChannelTasksUseCaseProvider = Provider<ListChannelTasksUseCase>((
  ref,
) {
  return ListChannelTasksUseCase(
    ref.watch(collaborationTaskRepositoryProvider),
  );
});

final createChannelTaskUseCaseProvider = Provider<CreateChannelTaskUseCase>((
  ref,
) {
  return CreateChannelTaskUseCase(
    ref.watch(collaborationTaskRepositoryProvider),
  );
});

final updateChannelTaskUseCaseProvider = Provider<UpdateChannelTaskUseCase>((
  ref,
) {
  return UpdateChannelTaskUseCase(
    ref.watch(collaborationTaskRepositoryProvider),
  );
});

final deleteChannelTaskUseCaseProvider = Provider<DeleteChannelTaskUseCase>((
  ref,
) {
  return DeleteChannelTaskUseCase(
    ref.watch(collaborationTaskRepositoryProvider),
  );
});

final listAssignedTasksUseCaseProvider = Provider<ListAssignedTasksUseCase>((
  ref,
) {
  return ListAssignedTasksUseCase(
    ref.watch(collaborationTaskRepositoryProvider),
  );
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

final resolveCallDeviceIdUseCaseProvider = Provider<ResolveCallDeviceIdUseCase>(
  (ref) {
    return ResolveCallDeviceIdUseCase(
      ref.watch(deviceIdentityRepositoryProvider),
    );
  },
);

final startCallUseCaseProvider = Provider<StartCallUseCase>((ref) {
  return StartCallUseCase(
    ref.watch(callRepositoryProvider),
    resolveDeviceId: ref.watch(resolveCallDeviceIdUseCaseProvider),
  );
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
  return AcceptCallUseCase(
    ref.watch(callRepositoryProvider),
    resolveDeviceId: ref.watch(resolveCallDeviceIdUseCaseProvider),
  );
});

final endCallUseCaseProvider = Provider<EndCallUseCase>((ref) {
  return EndCallUseCase(ref.watch(callRepositoryProvider));
});

final rejectCallUseCaseProvider = Provider<RejectCallUseCase>((ref) {
  return RejectCallUseCase(
    ref.watch(callRepositoryProvider),
    resolveDeviceId: ref.watch(resolveCallDeviceIdUseCaseProvider),
  );
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

final deleteNotificationUseCaseProvider = Provider<DeleteNotificationUseCase>((
  ref,
) {
  return DeleteNotificationUseCase(ref.watch(notificationRepositoryProvider));
});

final deleteAllNotificationsUseCaseProvider =
    Provider<DeleteAllNotificationsUseCase>((ref) {
      return DeleteAllNotificationsUseCase(
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

// ---------------------------------------------------------------------------
// Tin nhắn nâng cao: thẻ có nút / biểu mẫu, tin chạy dần, chép lời tin thoại,
// lịch sử ghi chú / bảng trắng.
// ---------------------------------------------------------------------------

final getMessageUseCaseProvider = Provider<GetMessageUseCase>((ref) {
  return GetMessageUseCase(ref.watch(richMessageRepositoryProvider));
});

final invokeMessageActionUseCaseProvider = Provider<InvokeMessageActionUseCase>(
  (ref) {
    return InvokeMessageActionUseCase(ref.watch(richMessageRepositoryProvider));
  },
);

final submitMessageFormUseCaseProvider = Provider<SubmitMessageFormUseCase>((
  ref,
) {
  return SubmitMessageFormUseCase(ref.watch(richMessageRepositoryProvider));
});

final loadMyMessageInteractionsUseCaseProvider =
    Provider<LoadMyMessageInteractionsUseCase>((ref) {
      return LoadMyMessageInteractionsUseCase(
        ref.watch(richMessageRepositoryProvider),
      );
    });

final decideApprovalUseCaseProvider = Provider<DecideApprovalUseCase>((ref) {
  return DecideApprovalUseCase(ref.watch(richMessageRepositoryProvider));
});

final loadFileTranscriptUseCaseProvider = Provider<LoadFileTranscriptUseCase>((
  ref,
) {
  return LoadFileTranscriptUseCase(ref.watch(richMessageRepositoryProvider));
});

final loadCollaborationDocumentUseCaseProvider =
    Provider<LoadCollaborationDocumentUseCase>((ref) {
      return LoadCollaborationDocumentUseCase(
        ref.watch(collaborationDocumentHistoryRepositoryProvider),
      );
    });

final listCollaborationDocumentVersionsUseCaseProvider =
    Provider<ListCollaborationDocumentVersionsUseCase>((ref) {
      return ListCollaborationDocumentVersionsUseCase(
        ref.watch(collaborationDocumentHistoryRepositoryProvider),
      );
    });

final loadCollaborationDocumentVersionUseCaseProvider =
    Provider<LoadCollaborationDocumentVersionUseCase>((ref) {
      return LoadCollaborationDocumentVersionUseCase(
        ref.watch(collaborationDocumentHistoryRepositoryProvider),
      );
    });

final restoreCollaborationDocumentVersionUseCaseProvider =
    Provider<RestoreCollaborationDocumentVersionUseCase>((ref) {
      return RestoreCollaborationDocumentVersionUseCase(
        ref.watch(collaborationDocumentHistoryRepositoryProvider),
      );
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
      followRedirects: false,
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

// ---------------------------------------------------------------------------
// Ticket khách (chỉ máy chủ nội bộ VPSTTT, bật theo discovery + quyền order.*):
// nhân viên xem / trả lời ticket khách gửi trên hệ thống order.
// ---------------------------------------------------------------------------

final customerTicketRemoteDataSourceProvider =
    Provider<CustomerTicketRemoteDataSource>((ref) {
      return CustomerTicketRemoteDataSource(ref.watch(apiTransportProvider));
    });

final customerTicketRepositoryProvider = Provider<CustomerTicketRepository>((
  ref,
) {
  return CustomerTicketRepositoryImpl(
    ref.watch(customerTicketRemoteDataSourceProvider),
  );
});

/// Kết nối WebSocket riêng cho phòng `workspace:<ws>:order-tickets`: tự ngắt
/// khi không còn màn ticket nào nghe, không ảnh hưởng phòng chat.
final customerTicketRealtimeRepositoryProvider =
    Provider<CustomerTicketRealtimeRepository>((ref) {
      final socket = WebSocketConversationRealtimeRepository(
        apiBaseUri: ref.watch(activeServerUriProvider),
        wsBaseUri: ref.watch(activeServerWsUriProvider),
        instanceScope: ref.watch(activeInstanceScopeProvider),
        tokenRepository: ref.watch(authTokenRepositoryProvider),
      );
      ref.onDispose(() {
        unawaited(socket.disconnect());
      });
      return WebSocketCustomerTicketRealtimeRepository(
        socket.subscribeToOrderTickets,
      );
    });

final customerTicketImagePickerRepositoryProvider =
    Provider<CustomerTicketImagePickerRepository>((ref) {
      return ImagePickerCustomerTicketImageRepository();
    });

/// Ảnh khách gửi (tên miền khác): tải không kèm token; bộ nhớ đệm theo máy chủ.
final customerTicketImageRepositoryProvider =
    Provider<CustomerTicketImageRepository>((ref) {
      ref.watch(activeServerDiscoveryProvider);
      final repository = PublicCustomerTicketImageRepository();
      ref.onDispose(repository.clear);
      return repository;
    });

final listCustomerTicketsUseCaseProvider = Provider<ListCustomerTicketsUseCase>(
  (ref) {
    return ListCustomerTicketsUseCase(
      ref.watch(customerTicketRepositoryProvider),
    );
  },
);

final countUnansweredCustomerTicketsUseCaseProvider =
    Provider<CountUnansweredCustomerTicketsUseCase>((ref) {
      return CountUnansweredCustomerTicketsUseCase(
        ref.watch(customerTicketRepositoryProvider),
      );
    });

final loadCustomerTicketUseCaseProvider = Provider<LoadCustomerTicketUseCase>((
  ref,
) {
  return LoadCustomerTicketUseCase(ref.watch(customerTicketRepositoryProvider));
});

final replyCustomerTicketUseCaseProvider = Provider<ReplyCustomerTicketUseCase>(
  (ref) {
    return ReplyCustomerTicketUseCase(
      ref.watch(customerTicketRepositoryProvider),
    );
  },
);

final setCustomerTicketStatusUseCaseProvider =
    Provider<SetCustomerTicketStatusUseCase>((ref) {
      return SetCustomerTicketStatusUseCase(
        ref.watch(customerTicketRepositoryProvider),
      );
    });

final claimCustomerTicketUseCaseProvider = Provider<ClaimCustomerTicketUseCase>(
  (ref) {
    return ClaimCustomerTicketUseCase(
      ref.watch(customerTicketRepositoryProvider),
    );
  },
);

final requestCustomerTicketAiDraftUseCaseProvider =
    Provider<RequestCustomerTicketAiDraftUseCase>((ref) {
      return RequestCustomerTicketAiDraftUseCase(
        ref.watch(customerTicketRepositoryProvider),
      );
    });

final watchCustomerTicketsUseCaseProvider =
    Provider<WatchCustomerTicketsUseCase>((ref) {
      return WatchCustomerTicketsUseCase(
        ref.watch(customerTicketRealtimeRepositoryProvider),
      );
    });

final pickCustomerTicketImagesUseCaseProvider =
    Provider<PickCustomerTicketImagesUseCase>((ref) {
      return PickCustomerTicketImagesUseCase(
        ref.watch(customerTicketImagePickerRepositoryProvider),
      );
    });

final loadCustomerTicketImageUseCaseProvider =
    Provider<LoadCustomerTicketImageUseCase>((ref) {
      return LoadCustomerTicketImageUseCase(
        ref.watch(customerTicketImageRepositoryProvider),
      );
    });
