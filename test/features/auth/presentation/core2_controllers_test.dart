import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/session_termination.dart';
import 'package:webtui_chat/features/auth/application/use_cases/qr_login_use_cases.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_session.dart';
import 'package:webtui_chat/features/auth/domain/entities/device_approval.dart';
import 'package:webtui_chat/features/auth/domain/entities/email_verification.dart';
import 'package:webtui_chat/features/auth/domain/entities/qr_login.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/device_approval_controllers.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/email_verification_controller.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/qr_login_controller.dart';

import '../support/core2_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 11, 10);

  test('QR khác máy chủ bị chặn trước request, QR đúng cần xác nhận', () async {
    var scans = 0;
    var decisions = 0;
    final controller = QrLoginController(
      readPayload: ReadQrLoginPayloadUseCase(
        loadServerOrigin: () => Uri.parse('https://chat.example.com'),
      ).execute,
      scan: (payload) async {
        scans++;
        return Success(
          QrLoginScan(
            challengeId: payload.challengeId,
            status: 'scanned',
            requester: const QrLoginRequester(deviceName: 'Máy tính'),
          ),
        );
      },
      decide: (_, {required approve}) async {
        decisions++;
        return Success(approve ? 'approved' : 'rejected');
      },
    );
    addTearDown(controller.dispose);
    await controller.submitScannedValue(
      'vpsttt-login:v1?d=other.example.com&c=challenge-123&s=secretsecret123456',
    );
    expect(controller.state.phase, QrLoginPhase.error);
    expect(scans, 0);
    await controller.submitScannedValue(
      'vpsttt-login:v1?d=chat.example.com&c=challenge-123&s=secretsecret123456',
    );
    expect(controller.state.phase, QrLoginPhase.confirm);
    expect(scans, 1);
    expect(decisions, 0);
    await controller.decide(approve: false);
    expect(controller.state.phase, QrLoginPhase.rejected);
    expect(controller.state.payload, isNull);
    await controller.decide(approve: true);
    expect(decisions, 1);
  });

  test('chờ duyệt không chồng request; chỉ refresh sau approved', () async {
    var polls = 0;
    var refreshes = 0;
    final response = Completer<Result<MyDeviceApproval>>();
    final controller = DeviceApprovalPendingController(
      loadApproval: () {
        polls++;
        return response.future;
      },
      refreshSession: () async {
        refreshes++;
        return Success(fakeAuthSession());
      },
      endSession: (_) async => fail('Không được đăng xuất phiên đã duyệt'),
    );
    addTearDown(controller.dispose);
    final first = controller.poll();
    await controller.poll();
    expect(polls, 1);
    expect(refreshes, 0);
    response.complete(
      const Success(
        MyDeviceApproval(sessionId: 'session-1', approvalStatus: 'approved'),
      ),
    );
    await first;
    expect(refreshes, 1);
    expect(controller.state.phase, PendingApprovalPhase.approved);
    await controller.poll();
    expect(polls, 1);
  });

  test('hết hạn duyệt xoá phiên, không refresh', () async {
    final ended = <SessionEndReason>[];
    final controller = DeviceApprovalPendingController(
      clock: () => now,
      loadApproval: () async => Success(
        MyDeviceApproval(
          sessionId: 'session-1',
          approvalStatus: 'pending',
          approvalExpiresAt: now,
        ),
      ),
      refreshSession: () async => throw StateError('Không được refresh'),
      endSession: (reason) async => ended.add(reason),
    );
    addTearDown(controller.dispose);
    await controller.poll();
    expect(controller.state.phase, PendingApprovalPhase.ended);
    expect(ended, [SessionEndReason.approvalExpired]);
  });

  test('duyệt người thứ nhất giữ kết quả pending, không báo đã xong', () async {
    var decisions = 0;
    final controller = DeviceApprovalReviewController(
      sessionId: 'session-1',
      findRequest: (_) async => const Success(
        DeviceApprovalRequest(sessionId: 'session-1', myRole: 'self'),
      ),
      decide: (_, {required approve}) async {
        decisions++;
        return const Success(
          DeviceApprovalResult(
            sessionId: 'session-1',
            approvalStatus: 'pending',
          ),
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.decide(approve: true);
    await controller.decide(approve: true);
    expect(controller.state.resultStatus, 'pending');
    expect(decisions, 1);
  });

  test('mã email sai hết lượt chặn nhập lại, gửi lại theo cooldown', () async {
    var current = now;
    var verifies = 0;
    var resends = 0;
    final controller = EmailVerificationController(
      ticket: EmailVerificationTicket(
        verificationId: 'verify-1',
        resendAvailableAt: now.add(const Duration(seconds: 60)),
      ),
      clock: () => current,
      verify: ({required verificationId, required code}) async {
        verifies++;
        return const FailureResult<AuthSession>(
          Failure(
            kind: FailureKind.validation,
            message: 'Mã chưa đúng',
            code: 'EMAIL_CODE_INVALID',
            details: {'attempts_left': 0},
          ),
        );
      },
      resend: (_) async {
        resends++;
        return const Success(
          EmailVerificationTicket(verificationId: 'verify-1'),
        );
      },
    );
    addTearDown(controller.dispose);
    controller.updateCode('123456');
    await controller.submit();
    expect(controller.state.mustResend, isTrue);
    controller.updateCode('654321');
    await controller.submit();
    expect(verifies, 1);
    await controller.resend();
    expect(resends, 0);
    current = now.add(const Duration(seconds: 60));
    await controller.resend();
    expect(resends, 1);
    expect(controller.state.mustResend, isFalse);
    expect(controller.state.code, isEmpty);
    expect(controller.resendSecondsLeft(), 60);
  });
}
