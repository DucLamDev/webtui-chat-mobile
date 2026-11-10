import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

final class ProfileRemoteDataSource {
  const ProfileRemoteDataSource(this._api, {this.loadWorkspaceId});

  final ApiTransport _api;
  final Future<String?> Function()? loadWorkspaceId;

  Future<Map<String, dynamic>?> _workspaceQuery() async {
    final id = (await loadWorkspaceId?.call())?.trim();
    return id == null || id.isEmpty ? null : {'workspace_id': id};
  }

  Future<UserProfile> me() async {
    final response = await _api.get<Object>(
      '/api/v1/users/me',
      queryParameters: await _workspaceQuery(),
    );
    return userProfileFromMap(envelopeItem(response.data, 'user'));
  }

  Future<UserProfile> updateMe(UpdateProfileCommand command) async {
    final response = await _api.patch<Object>(
      '/api/v1/users/me',
      queryParameters: await _workspaceQuery(),
      data: compactMap({
        'display_name': command.displayName,
        'avatar_url': command.avatarUrl,
        'phone_number': command.phoneNumber,
        'locale': command.locale,
        'timezone': command.timezone,
        'title': command.title,
      }),
    );
    return userProfileFromMap(envelopeItem(response.data, 'user'));
  }
}

WorkProfile _workProfileFromMap(JsonMap map) {
  final startDate = nullableStringField(map, const ['start_date', 'startDate']);
  return WorkProfile(
    title: nullableStringField(map, const ['title']),
    department: nullableStringField(map, const ['department']),
    location: nullableStringField(map, const ['location']),
    startDate: _dateOnly(startDate),
  );
}

/// `YYYY-MM-DD` → ngày (không đổi múi giờ để tránh lệch một ngày).
DateTime? _dateOnly(String? value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value ?? '');
  if (match == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
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
    work: _workProfileFromMap(jsonMap(field(map, const ['profile']))),
  );
}
