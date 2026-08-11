import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/legal_acceptance_access_policy.dart';
import 'package:webtui_chat/features/auth/domain/entities/legal_acceptance.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/legal_acceptance_controller.dart';

void main() {
  test(
    'incomplete existing user remains fail-closed until explicit POST',
    () async {
      final policy = LegalAcceptanceAccessPolicy();
      Map<String, String>? submitted;
      final controller = _controller(
        policy: policy,
        load: ({required workspaceId}) async =>
            Success(_acceptance(complete: false, workspaceId: workspaceId)),
        submit:
            ({
              required workspaceId,
              required termsVersion,
              required privacyVersion,
            }) async {
              submitted = {
                'workspace': workspaceId,
                'terms': termsVersion,
                'privacy': privacyVersion,
              };
              return Success(_acceptance(complete: true));
            },
      );

      await controller.beginSession(workspaceId: 'workspace-1');
      expect(controller.state.status, LegalAcceptanceStatus.required);
      expect(policy.canCreateUserContent, isFalse);

      controller.setAcceptedBoth(true);
      await controller.accept();

      expect(submitted, {
        'workspace': 'workspace-1',
        'terms': '2026-08-07',
        'privacy': '2026-08-07',
      });
      expect(controller.state.status, LegalAcceptanceStatus.complete);
      expect(policy.canCreateUserContent, isTrue);
      controller.dispose();
      policy.dispose();
    },
  );

  test(
    'stale GET cannot overwrite a newer authenticated session load',
    () async {
      final first = Completer<Result<LegalAcceptance>>();
      final second = Completer<Result<LegalAcceptance>>();
      var request = 0;
      final policy = LegalAcceptanceAccessPolicy();
      final controller = _controller(
        policy: policy,
        load: ({required workspaceId}) =>
            ++request == 1 ? first.future : second.future,
      );

      final firstLoad = controller.beginSession(workspaceId: 'workspace-1');
      final secondLoad = controller.beginSession(workspaceId: 'workspace-2');
      second.complete(
        Success(_acceptance(complete: true, workspaceId: 'workspace-2')),
      );
      await secondLoad;
      first.complete(Success(_acceptance(complete: false)));
      await firstLoad;

      expect(controller.state.status, LegalAcceptanceStatus.complete);
      expect(policy.canCreateUserContent, isTrue);
      controller.dispose();
      policy.dispose();
    },
  );

  test('stale POST cannot complete a newer session scope', () async {
    final pendingSubmission = Completer<Result<LegalAcceptance>>();
    var loads = 0;
    final policy = LegalAcceptanceAccessPolicy();
    final controller = _controller(
      policy: policy,
      load: ({required workspaceId}) async =>
          Success(_acceptance(complete: loads++ > 0, workspaceId: workspaceId)),
      submit:
          ({
            required workspaceId,
            required termsVersion,
            required privacyVersion,
          }) {
            return pendingSubmission.future;
          },
    );

    await controller.beginSession(workspaceId: 'workspace-1');
    controller.setAcceptedBoth(true);
    final oldSubmission = controller.accept();

    await controller.beginSession(workspaceId: 'workspace-2');
    expect(controller.state.status, LegalAcceptanceStatus.complete);
    pendingSubmission.complete(Success(_acceptance(complete: false)));
    await oldSubmission;

    expect(controller.state.status, LegalAcceptanceStatus.complete);
    expect(policy.canCreateUserContent, isTrue);
    controller.dispose();
    policy.dispose();
  });

  test('publisher/server version mismatch is fail-closed', () async {
    final policy = LegalAcceptanceAccessPolicy();
    final controller = _controller(
      policy: policy,
      load: ({required workspaceId}) async => Success(
        _acceptance(
          complete: true,
          workspaceId: workspaceId,
          termsVersion: 'operator-override',
        ),
      ),
    );

    await controller.beginSession(workspaceId: 'workspace-1');

    expect(controller.state.status, LegalAcceptanceStatus.incompatible);
    expect(controller.state.errorMessage, contains('không khớp'));
    expect(policy.canCreateUserContent, isFalse);
    controller.dispose();
    policy.dispose();
  });

  test('echoed workspace mismatch is fail-closed', () async {
    final policy = LegalAcceptanceAccessPolicy();
    final controller = _controller(
      policy: policy,
      load: ({required workspaceId}) async =>
          Success(_acceptance(complete: true, workspaceId: 'workspace-other')),
    );

    await controller.beginSession(workspaceId: 'workspace-1');

    expect(controller.state.status, LegalAcceptanceStatus.incompatible);
    expect(controller.state.errorMessage, contains('workspace khác'));
    expect(policy.canCreateUserContent, isFalse);
    controller.dispose();
    policy.dispose();
  });

  test(
    'server complete without acceptance timestamps remains fail-closed',
    () async {
      final policy = LegalAcceptanceAccessPolicy();
      final controller = _controller(
        policy: policy,
        load: ({required workspaceId}) async => Success(
          _acceptance(
            complete: true,
            workspaceId: workspaceId,
            includeAcceptanceEvidence: false,
          ),
        ),
      );

      await controller.beginSession(workspaceId: 'workspace-1');

      expect(controller.state.status, LegalAcceptanceStatus.required);
      expect(controller.state.acceptance?.serverComplete, isTrue);
      expect(policy.canCreateUserContent, isFalse);
      controller.dispose();
      policy.dispose();
    },
  );

  test('failed GET supports retry without using a fallback version', () async {
    var attempts = 0;
    final policy = LegalAcceptanceAccessPolicy();
    final controller = _controller(
      policy: policy,
      load: ({required workspaceId}) async {
        attempts++;
        if (attempts == 1) {
          return const FailureResult(
            Failure(kind: FailureKind.network, message: 'Không tải được.'),
          );
        }
        return Success(_acceptance(complete: false, workspaceId: workspaceId));
      },
    );

    await controller.beginSession(workspaceId: 'workspace-1');
    expect(controller.state.status, LegalAcceptanceStatus.error);
    expect(policy.canCreateUserContent, isFalse);

    await controller.retry();
    expect(controller.state.status, LegalAcceptanceStatus.required);
    expect(attempts, 2);
    controller.dispose();
    policy.dispose();
  });

  test(
    'LEGAL_ACCEPTANCE_REQUIRED event invalidates complete state and reloads',
    () async {
      var attempts = 0;
      final policy = LegalAcceptanceAccessPolicy();
      final controller = _controller(
        policy: policy,
        load: ({required workspaceId}) async {
          attempts++;
          return Success(
            _acceptance(complete: attempts == 1, workspaceId: workspaceId),
          );
        },
      );

      await controller.beginSession(workspaceId: 'workspace-1');
      expect(controller.state.status, LegalAcceptanceStatus.complete);

      policy.requireAcceptance();
      await Future<void>.delayed(Duration.zero);

      expect(attempts, 2);
      expect(controller.state.status, LegalAcceptanceStatus.required);
      expect(controller.state.gateVisible, isTrue);
      expect(policy.canCreateUserContent, isFalse);
      controller.dispose();
      policy.dispose();
    },
  );
}

LegalAcceptanceController _controller({
  required LegalAcceptanceAccessPolicy policy,
  required LoadLegalAcceptance load,
  SubmitLegalAcceptance? submit,
}) {
  return LegalAcceptanceController(
    load: load,
    submit:
        submit ??
        ({
          required workspaceId,
          required termsVersion,
          required privacyVersion,
        }) async =>
            Success(_acceptance(complete: true, workspaceId: workspaceId)),
    accessPolicy: policy,
    expectedTermsVersion: '2026-08-07',
    expectedPrivacyVersion: '2026-08-07',
    legalLinksConfigured: true,
  );
}

LegalAcceptance _acceptance({
  required bool complete,
  String workspaceId = 'workspace-1',
  String termsVersion = '2026-08-07',
  String privacyVersion = '2026-08-07',
  bool includeAcceptanceEvidence = true,
}) {
  final acceptedAt = complete && includeAcceptanceEvidence
      ? DateTime.utc(2026, 8, 7, 8)
      : null;
  return LegalAcceptance(
    workspaceId: workspaceId,
    serverComplete: complete,
    terms: LegalDocumentAcceptance(
      version: termsVersion,
      accepted: complete,
      acceptedAt: acceptedAt,
    ),
    privacy: LegalDocumentAcceptance(
      version: privacyVersion,
      accepted: complete,
      acceptedAt: acceptedAt,
    ),
  );
}
