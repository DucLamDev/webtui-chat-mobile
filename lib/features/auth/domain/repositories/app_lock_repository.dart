abstract interface class AppLockRepository {
  Future<bool> isEnabled();

  Future<void> enablePin(String pin);

  Future<bool> verifyPin(String pin);

  Future<void> disable();
}
