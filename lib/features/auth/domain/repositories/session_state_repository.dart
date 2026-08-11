import 'auth_token_repository.dart';

abstract interface class SessionStateRepository {
  Future<AuthTokenMutationGuard?> captureActiveSessionGuard();

  Future<void> resetForServerSwitch();

  Future<void> resetForLogout();

  /// Clears only the session and local data owned by [guard].
  ///
  /// Returns whether [guard] was still the active runtime and its global
  /// projection was cleared. A stale guard may still have its scoped account
  /// record/cache cleaned without touching the newly active server.
  Future<bool> resetForLogoutIfCurrent(AuthTokenMutationGuard guard);

  Future<bool> hasAnySavedSession();
}
