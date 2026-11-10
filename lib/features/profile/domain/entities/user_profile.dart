final class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.status,
    required this.locale,
    required this.timezone,
    this.avatarUrl,
    this.phoneNumber,
    this.work = const WorkProfile(),
  });

  final String id;
  final String email;
  final String username;
  final String displayName;
  final String status;
  final String locale;
  final String timezone;
  final String? avatarUrl;
  final String? phoneNumber;

  /// `profile {title, department, location, start_date}` theo workspace của
  /// token (Lõi 2.7); máy chủ cũ không trả → rỗng.
  final WorkProfile work;
}

/// Thông tin công việc trong workspace đang dùng.
final class WorkProfile {
  const WorkProfile({
    this.title,
    this.department,
    this.location,
    this.startDate,
  });

  /// Chức danh (người dùng tự sửa được).
  final String? title;
  final String? department;

  /// Nơi làm việc.
  final String? location;

  /// Ngày vào (chỉ ngày, `YYYY-MM-DD`).
  final DateTime? startDate;

  bool get isEmpty =>
      title == null &&
      department == null &&
      location == null &&
      startDate == null;

  /// "chức danh · phòng ban · nơi làm · ngày vào dd/MM/yyyy" (bỏ mục trống).
  String get summary {
    final date = startDate;
    return [
      title,
      department,
      location,
      if (date != null)
        'vào ${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/${date.year}',
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' · ');
  }
}
