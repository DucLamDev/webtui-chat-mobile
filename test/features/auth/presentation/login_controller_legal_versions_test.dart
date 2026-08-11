import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/use_cases/register_use_case.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_session.dart';
import 'package:webtui_chat/features/auth/domain/entities/legal_document_versions.dart';
import 'package:webtui_chat/features/auth/domain/entities/oidc_provider.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/login_controller.dart';

void main() {
  test(
    'registration stays disabled while legal versions are loading',
    () async {
      final response = Completer<Result<LegalDocumentVersions>>();
      final controller = _controller(
        loadLegal: () => response.future,
        expectedTermsVersion: 'server-terms-v2',
        expectedPrivacyVersion: 'server-privacy-v3',
      );

      final refresh = controller.refreshLegalDocumentVersions();
      controller.showRegister();
      controller.updateLegalAcceptance(true);

      expect(
        controller.state.legalDocumentsStatus,
        LegalDocumentsStatus.loading,
      );
      expect(controller.state.legalAccepted, isFalse);
      expect(controller.state.canSubmit, isFalse);

      response.complete(
        const Success(
          LegalDocumentVersions(
            termsVersion: 'server-terms-v2',
            privacyVersion: 'server-privacy-v3',
          ),
        ),
      );
      await refresh;

      expect(controller.state.legalDocumentsStatus, LegalDocumentsStatus.ready);
      expect(
        controller.state.legalDocumentVersions?.termsVersion,
        'server-terms-v2',
      );
    },
  );

  test('legal endpoint failure is fail-closed and can be retried', () async {
    var attempts = 0;
    final controller = _controller(
      expectedTermsVersion: 'terms-current',
      expectedPrivacyVersion: 'privacy-current',
      loadLegal: () async {
        attempts++;
        if (attempts == 1) {
          return const FailureResult(
            Failure(
              kind: FailureKind.network,
              message: 'Cannot load legal documents.',
            ),
          );
        }
        return const Success(
          LegalDocumentVersions(
            termsVersion: 'terms-current',
            privacyVersion: 'privacy-current',
          ),
        );
      },
    );

    await controller.refreshLegalDocumentVersions();

    expect(controller.state.legalDocumentsStatus, LegalDocumentsStatus.error);
    expect(controller.state.legalDocumentVersions, isNull);
    expect(controller.state.canSubmit, isFalse);

    await controller.refreshLegalDocumentVersions();

    expect(controller.state.legalDocumentsStatus, LegalDocumentsStatus.ready);
    expect(attempts, 2);
  });

  test('stale legal response cannot overwrite a changed server', () async {
    final response = Completer<Result<LegalDocumentVersions>>();
    final controller = _controller(loadLegal: () => response.future);

    final refresh = controller.refreshLegalDocumentVersions();
    controller.changeServer();
    response.complete(
      const Success(
        LegalDocumentVersions(
          termsVersion: 'stale-terms',
          privacyVersion: 'stale-privacy',
        ),
      ),
    );
    await refresh;

    expect(controller.state.serverConnected, isFalse);
    expect(controller.state.legalDocumentsStatus, LegalDocumentsStatus.idle);
    expect(controller.state.legalDocumentVersions, isNull);
  });

  test(
    'registration sends only versions loaded from the active server',
    () async {
      RegisterCommand? submitted;
      final controller = _controller(
        expectedTermsVersion: 'runtime-terms',
        expectedPrivacyVersion: 'runtime-privacy',
        loadLegal: () async => const Success(
          LegalDocumentVersions(
            termsVersion: 'runtime-terms',
            privacyVersion: 'runtime-privacy',
          ),
        ),
        register: (command) async {
          submitted = command;
          return const FailureResult(
            Failure(kind: FailureKind.server, message: 'Stop after capture.'),
          );
        },
      );

      await controller.refreshLegalDocumentVersions();
      controller.showRegister();
      controller.updateDisplayName('Production User');
      controller.updateEmail('production@example.com');
      controller.updateUsername('production');
      controller.updatePassword('password123');
      controller.updateConfirmPassword('password123');
      controller.updateLegalAcceptance(true);
      await controller.submit();

      expect(submitted?.termsVersion, 'runtime-terms');
      expect(submitted?.privacyVersion, 'runtime-privacy');
      expect(submitted?.termsAccepted, isTrue);
      expect(submitted?.privacyAccepted, isTrue);
    },
  );

  test(
    'server legal versions must match the published app documents',
    () async {
      final controller = _controller(
        expectedTermsVersion: 'publisher-terms',
        expectedPrivacyVersion: 'publisher-privacy',
        loadLegal: () async => const Success(
          LegalDocumentVersions(
            termsVersion: 'operator-overridden-terms',
            privacyVersion: 'operator-overridden-privacy',
          ),
        ),
      );

      await controller.refreshLegalDocumentVersions();

      expect(controller.state.legalDocumentsStatus, LegalDocumentsStatus.error);
      expect(controller.state.legalDocumentVersions, isNull);
      expect(
        controller.state.legalDocumentsError,
        contains('không tương thích'),
      );
      expect(controller.state.canSubmit, isFalse);
    },
  );
}

LoginController _controller({
  required Future<Result<LegalDocumentVersions>> Function() loadLegal,
  Future<Result<AuthSession>> Function(RegisterCommand command)? register,
  String expectedTermsVersion = '2026-08-07',
  String expectedPrivacyVersion = '2026-08-07',
}) {
  return LoginController(
    initialServer: 'chat.vpsttt.com',
    initialDiscovery: SelfHostedServerDiscovery(
      instanceId: '11111111-1111-4111-8111-111111111111',
      discoveryVersion: '1',
      domain: 'chat.vpsttt.com',
      name: 'WebTUI Chat',
      apiBaseUri: Uri.parse('https://chat.vpsttt.com'),
      wsBaseUri: Uri.parse('wss://chat.vpsttt.com/ws'),
      registrationMode: 'open',
      appVersion: 'test',
      apiContractVersion: 1,
      serverVersion: 'test',
      minimumSupportedMobileVersion: '1.0.0',
      capabilities: const SelfHostedCapabilities(
        moderation: true,
        reporting: true,
        blocking: true,
        accountDeletion: true,
        legalAcceptance: true,
      ),
    ),
    connectToServer: (_) => throw UnimplementedError(),
    login: (_) async => const FailureResult(
      Failure(kind: FailureKind.server, message: 'Not used.'),
    ),
    register:
        register ??
        (_) async => const FailureResult(
          Failure(kind: FailureKind.server, message: 'Not used.'),
        ),
    loadLegalDocumentVersions: loadLegal,
    oidcProviders: (_) async => const Success(<OidcProvider>[]),
    oidcStart: ({required domain, required providerId}) async =>
        const FailureResult(
          Failure(kind: FailureKind.server, message: 'Not used.'),
        ),
    oidcComplete:
        ({
          required code,
          required domain,
          required instanceScopeId,
          required attemptId,
          required remember,
        }) async => const FailureResult(
          Failure(kind: FailureKind.server, message: 'Not used.'),
        ),
    openExternalUrl: (_) async => true,
    recentServers: () async => const [],
    hasStoredSession: () async => false,
    expectedTermsVersion: expectedTermsVersion,
    expectedPrivacyVersion: expectedPrivacyVersion,
  );
}
