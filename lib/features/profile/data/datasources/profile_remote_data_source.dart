import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

final class ProfileRemoteDataSource {
  const ProfileRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<UserProfile> me() async {
    final response = await _api.get<Object>('/api/v1/users/me');
    return userProfileFromMap(envelopeItem(response.data, 'user'));
  }

  Future<UserProfile> updateMe(UpdateProfileCommand command) async {
    final response = await _api.patch<Object>(
      '/api/v1/users/me',
      data: compactMap({
        'display_name': command.displayName,
        'avatar_url': command.avatarUrl,
        'phone_number': command.phoneNumber,
        'locale': command.locale,
        'timezone': command.timezone,
      }),
    );
    return userProfileFromMap(envelopeItem(response.data, 'user'));
  }
}

UserProfile userProfileFromMap(JsonMap map) {
  return UserProfile(
    id: stringField(map, const ['id']),
    email: stringField(map, const ['email']),
    username: stringField(map, const ['username']),
    displayName: stringField(map, const [
      'display_name',
      'displayName',
      'name',
    ], fallback: stringField(map, const ['username', 'email'])),
    status: stringField(map, const ['status'], fallback: 'active'),
    locale: stringField(map, const ['locale'], fallback: 'vi'),
    timezone: stringField(map, const ['timezone'], fallback: 'Asia/Saigon'),
    avatarUrl: nullableStringField(map, const ['avatar_url', 'avatarUrl']),
    phoneNumber: nullableStringField(map, const [
      'phone_number',
      'phoneNumber',
    ]),
  );
}
