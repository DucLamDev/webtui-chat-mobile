import '../../../../core/result/result.dart';
import '../entities/user_profile.dart';

final class UpdateProfileCommand {
  const UpdateProfileCommand({
    this.displayName,
    this.avatarUrl,
    this.phoneNumber,
    this.locale,
    this.timezone,
  });

  final String? displayName;
  final String? avatarUrl;
  final String? phoneNumber;
  final String? locale;
  final String? timezone;
}

abstract interface class ProfileRepository {
  Future<Result<UserProfile>> me();

  Future<Result<UserProfile>> updateMe(UpdateProfileCommand command);
}
