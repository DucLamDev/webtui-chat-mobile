/// Lưu mức tự khoá người dùng tự chọn (phút) trên máy.
abstract interface class AppLockTimeoutRepository {
  /// null khi người dùng chưa chọn.
  Future<int?> readIdleMinutes();

  Future<void> writeIdleMinutes(int minutes);
}
