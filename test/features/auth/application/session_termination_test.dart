import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/session_termination.dart';
import 'package:webtui_chat/features/auth/application/use_cases/refresh_access_token_use_case.dart';
import 'package:webtui_chat/features/auth/application/use_cases/session_use_cases.dart';
import 'package:webtui_chat/features/auth/domain/entities/auth_session.dart';
import 'package:webtui_chat/features/auth/domain/entities/user_session.dart';

import '../support/core2_fakes.dart';

void main() {
  group('SessionTerminationCoordinator (SESSION_REVOKED → resetForLogout)', () {
    test('xoá token, gọi resetForLogoutIfCurrent và báo giao diện', () async {
      final tokens = MemoryTokenRepository(
        accessToken: fakeJwt(sid: 'session-1'),
        refreshToken: 'refresh',
      );
      final sessionState = RecordingSessionStateRepository();
      final coordinator = SessionTerminationCoordinator(
        sessionStateRepository: sessionState,
        tokenRepository: tokens,
      );
      final notices = <SessionEndedNotice>[];
      coordinator.endedSessions.listen(notices.add);

      final ended = await coordinator.endSession(
        SessionEndedNotice.fromFailure(
          const Failure(
            kind: FailureKind.unauthorized,
            message: 'revoked',
            code: 'SESSION_REVOKED',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(ended, isTrue);
      expect(tokens.accessToken, isNull);
      expect(tokens.refreshToken, isNull);
      expect(sessionState.resetGuards, [testGuard]);
      expect(notices.single.reason, SessionEndReason.revoked);
      await coordinator.dispose();
    });

    test('nhiều request cùng báo thu hồi chỉ xoá một lần', () async {
      final tokens = MemoryTokenRepository(
        accessToken: 'access',
        refreshToken: 'refresh',
      );
      final sessionState = RecordingSessionStateRepository()
        ..beforeReset = () =>
            Future<void>.delayed(const Duration(milliseconds: 5));
      final coordinator = SessionTerminationCoordinator(
        sessionStateRepository: sessionState,
        tokenRepository: tokens,
      );
      final notices = <SessionEndedNotice>[];
      coordinator.endedSessions.listen(notices.add);
      const notice = SessionEndedNotice(reason: SessionEndReason.revoked);

      await Future.wait([
        coordinator.endSession(notice, guard: testGuard),
        coordinator.endSession(notice, guard: testGuard),
        coordinator.endSession(notice, guard: testGuard),
      ]);
      // Sự kiện WS đến muộn sau khi đã xoá: không còn token → bỏ qua.
      final late = await coordinator.endSession(notice, guard: testGuard);
      await Future<void>.delayed(Duration.zero);

      expect(late, isFalse);
      expect(sessionState.resetGuards, hasLength(1));
      expect(notices, hasLength(1));
      await coordinator.dispose();
    });

    test('SessionRevoked của phiên cũ không xoá phiên đang dùng', () async {
      final tokens = MemoryTokenRepository(
        accessToken: fakeJwt(sid: 'session-new'),
        refreshToken: 'refresh',
      );
      final sessionState = RecordingSessionStateRepository();
      final coordinator = SessionTerminationCoordinator(
        sessionStateRepository: sessionState,
        tokenRepository: tokens,
      );

      final ended = await coordinator.endSession(
        SessionEndedNotice.revokedByServer('user_revoked'),
        revokedSessionId: 'session-old',
      );

      expect(ended, isFalse);
      expect(tokens.accessToken, isNotNull);
      expect(sessionState.resetGuards, isEmpty);
      await coordinator.dispose();
    });

    test('SessionRevoked đúng phiên (khớp sid) thì xoá', () async {
      final tokens = MemoryTokenRepository(
        accessToken: fakeJwt(sid: 'session-1'),
        refreshToken: 'refresh',
      );
      final sessionState = RecordingSessionStateRepository();
      final coordinator = SessionTerminationCoordinator(
        sessionStateRepository: sessionState,
        tokenRepository: tokens,
      );

      final ended = await coordinator.endSession(
        SessionEndedNotice.revokedByServer('device_rejected'),
        revokedSessionId: 'session-1',
      );

      expect(ended, isTrue);
      expect(sessionState.resetGuards, [testGuard]);
      await coordinator.dispose();
    });
  });

  group('SessionEndedNotice', () {
    test('RELOGIN_REQUIRED đọc details.reason', () {
      final notice = SessionEndedNotice.fromFailure(
        const Failure(
          kind: FailureKind.unauthorized,
          message: 'relogin',
          code: 'RELOGIN_REQUIRED',
          details: {'reason': 'idle'},
        ),
      );

      expect(notice.reason, SessionEndReason.reloginRequired);
      expect(notice.message, contains('quá lâu'));
      expect(notice.prefersPrefill, isTrue);
    });

    test('device_rejected từ WS là bị từ chối duyệt', () {
      final notice = SessionEndedNotice.revokedByServer('device_rejected');
      expect(notice.reason, SessionEndReason.approvalRejected);
    });
  });

  test('accessTokenSessionId đọc claim sid, bỏ qua token lạ', () {
    expect(accessTokenSessionId(fakeJwt(sid: 'abc')), 'abc');
    expect(accessTokenSessionId(fakeJwt()), isNull);
    expect(accessTokenSessionId('opaque-token'), isNull);
    expect(accessTokenSessionId('a.%%%.c'), isNull);
    expect(accessTokenSessionId(null), isNull);
  });

  group('RefreshAccessTokenUseCase', () {
    for (final code in ['SESSION_REVOKED', 'RELOGIN_REQUIRED', 'ANY_401']) {
      test('refresh 401 $code → báo kết thúc phiên kèm guard', () async {
        final tokens = MemoryTokenRepository(
          accessToken: 'access',
          refreshToken: 'refresh',
        );
        final rejected = <(Failure, Object)>[];
        final useCase = RefreshAccessTokenUseCase(
          authRepository: ScriptedAuthRepository(
            refreshResult: FailureResult<AuthSession>(
              Failure(kind: FailureKind.unauthorized, message: 'x', code: code),
            ),
          ),
          tokenRepository: tokens,
          onRefreshRejected: (failure, guard) async =>
              rejected.add((failure, guard)),
        );

        final result = await useCase.execute();

        expect(result.isFailure, isTrue);
        expect(rejected.single.$1.code, code);
        expect(rejected.single.$2, testGuard);
        expect(tokens.refreshToken, isNull);
      });
    }

    test('lỗi mạng khi refresh không kết thúc phiên', () async {
      final tokens = MemoryTokenRepository(
        accessToken: 'access',
        refreshToken: 'refresh',
      );
      var rejected = 0;
      final useCase = RefreshAccessTokenUseCase(
        authRepository: ScriptedAuthRepository(
          refreshResult: const FailureResult<AuthSession>(
            Failure(kind: FailureKind.network, message: 'offline'),
          ),
        ),
        tokenRepository: tokens,
        onRefreshRejected: (_, _) async => rejected++,
      );

      await useCase.execute();

      expect(rejected, 0);
      expect(tokens.refreshToken, 'refresh');
    });
  });

  group('RevokeDeviceSessionUseCase (is_current, không dùng isActive)', () {
    UserSession session({required bool isCurrent}) => UserSession(
      id: isCurrent ? 'this-device' : 'other-device',
      createdAt: DateTime.utc(2026, 11, 1),
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      isCurrent: isCurrent,
    );

    test('thu hồi máy khác (đang hoạt động) không đăng xuất máy này', () async {
      final repository = ScriptedAuthRepository();
      var signedOut = 0;
      final useCase = RevokeDeviceSessionUseCase(
        authRepository: repository,
        signOutThisDevice: () async {
          signedOut++;
          return const Success(null);
        },
      );
      final other = session(isCurrent: false);
      expect(other.isActive, isTrue);

      final result = await useCase.execute(other);

      expect(result.valueOrNull, SessionRevokeOutcome.revokedOtherDevice);
      expect(repository.revokedSessionIds, ['other-device']);
      expect(signedOut, 0);
    });

    test('thu hồi phiên is_current thì đăng xuất máy này', () async {
      var signedOut = 0;
      final useCase = RevokeDeviceSessionUseCase(
        authRepository: ScriptedAuthRepository(),
        signOutThisDevice: () async {
          signedOut++;
          return const Success(null);
        },
      );

      final result = await useCase.execute(session(isCurrent: true));

      expect(result.valueOrNull, SessionRevokeOutcome.signedOutThisDevice);
      expect(signedOut, 1);
    });

    test('máy chủ từ chối thu hồi thì không đăng xuất', () async {
      var signedOut = 0;
      final useCase = RevokeDeviceSessionUseCase(
        authRepository: ScriptedAuthRepository(
          revokeResult: const FailureResult(
            Failure(kind: FailureKind.server, message: 'Máy chủ lỗi'),
          ),
        ),
        signOutThisDevice: () async {
          signedOut++;
          return const Success(null);
        },
      );

      final result = await useCase.execute(session(isCurrent: true));

      expect(result.isFailure, isTrue);
      expect(signedOut, 0);
    });
  });
}
