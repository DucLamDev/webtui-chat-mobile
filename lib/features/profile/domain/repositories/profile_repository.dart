import '../../../../core/result/result.dart';
import '../entities/user_profile.dart';

final class UpdateProfileCommand {
  const UpdateProfileCommand({
    this.displayName,
    this.avatarUrl,
    this.phoneNumber,
    this.locale,
    this.timezone,
    this.title,
  });

  final String? displayName;
  final String? avatarUrl;
  final String? phoneNumber;
  final String? locale;
  final String? timezone;

  /// Chức danh trong workspace hiện tại (Lõi 2.7); null = không đổi.
  final String? title;
}

abstract interface class ProfileRepository {
  Future<Result<UserProfile>> me();

  Future<Result<UserProfile>> updateMe(UpdateProfileCommand command);
}
