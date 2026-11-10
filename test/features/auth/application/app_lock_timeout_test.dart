import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/use_cases/app_lock_timeout_use_cases.dart';
import 'package:webtui_chat/features/auth/domain/entities/app_lock_timeout_policy.dart';
import 'package:webtui_chat/features/auth/domain/repositories/app_lock_timeout_repository.dart';

void main() {
  group('AppLockTimeoutPolicy', () {
    test('mặc định theo mức máy chủ, máy chủ không ép thì 30 phút', () {
      expect(AppLockTimeoutPolicy.effectiveMinutes(serverMaxMinutes: 15), 15);
      expect(AppLockTimeoutPolicy.effectiveMinutes(serverMaxMinutes: 0), 30);
    });

    test('người dùng chỉ được chọn ngắn hơn mức máy chủ', () {
      expect(
        AppLockTimeoutPolicy.effectiveMinutes(
          serverMaxMinutes: 30,
          userMinutes: 5,
        ),
        5,
      );
      expect(
        AppLockTimeoutPolicy.effectiveMinutes(
          serverMaxMinutes: 30,
          userMinutes: 120,
        ),
        30,
      );
      expect(
        AppLockTimeoutPolicy.effectiveMinutes(
          serverMaxMinutes: 0,
          userMinutes: 120,
        ),
        120,
      );
    });

    test('lựa chọn hiển thị không vượt mức máy chủ và có đúng mức đó', () {
      expect(AppLockTimeoutPolicy.allowedChoices(30), [1, 5, 15, 30]);
      expect(AppLockTimeoutPolicy.allowedChoices(45), [1, 5, 15, 30, 45]);
      expect(
        AppLockTimeoutPolicy.allowedChoices(0),
        AppLockTimeoutPolicy.presetMinutes,
      );
    });

    test('hasExpired so đúng mốc thời gian', () {
      final since = DateTime(2026, 11, 10, 9);
      expect(
        AppLockTimeoutPolicy.hasExpired(
          since: since,
          now: since.add(const Duration(minutes: 29, seconds: 59)),
          minutes: 30,
        ),
        isFalse,
      );
      expect(
        AppLockTimeoutPolicy.hasExpired(
          since: since,
          now: since.add(const Duration(minutes: 30)),
          minutes: 30,
        ),
        isTrue,
      );
      expect(
        AppLockTimeoutPolicy.hasExpired(
          since: since,
          now: since.subtract(const Duration(minutes: 90)),
          minutes: 30,
        ),
        isFalse,
        reason: 'đồng hồ máy lùi không làm khoá nhầm',
      );
    });

    test('nhãn tiếng Việt', () {
      expect(AppLockTimeoutPolicy.label(5), '5 phút');
      expect(AppLockTimeoutPolicy.label(120), '2 giờ');
    });
  });

  group('SaveAppLockIdleMinutesUseCase', () {
    test('từ chối mức dài hơn máy chủ cho phép', () async {
      final repository = _MemoryTimeoutRepository();
      final result = await SaveAppLockIdleMinutesUseCase(
        repository,
      ).execute(minutes: 60, serverMaxMinutes: 30);

      expect(result, isA<FailureResult<void>>());
      expect(
        (result as FailureResult<void>).failure.code,
        'APP_LOCK_TIMEOUT_TOO_LONG',
      );
      expect(repository.value, isNull);
    });

    test('lưu mức hợp lệ', () async {
      final repository = _MemoryTimeoutRepository();
      final result = await SaveAppLockIdleMinutesUseCase(
        repository,
      ).execute(minutes: 15, serverMaxMinutes: 30);

      expect(result, isA<Success<void>>());
      expect(repository.value, 15);
      expect(await LoadAppLockIdleMinutesUseCase(repository).execute(), 15);
    });
  });
}

final class _MemoryTimeoutRepository implements AppLockTimeoutRepository {
  int? value;

  @override
  Future<int?> readIdleMinutes() async => value;

  @override
  Future<void> writeIdleMinutes(int minutes) async {
    value = minutes;
  }
}
