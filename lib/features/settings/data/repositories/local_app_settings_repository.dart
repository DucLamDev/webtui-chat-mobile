import 'dart:convert';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/app_settings_repository.dart';

final class LocalAppSettingsRepository implements AppSettingsRepository {
  const LocalAppSettingsRepository(this._database);

  static const _scope = 'app_settings';
  static const _key = 'current';

  final AppDatabase _database;

  @override
  Future<AppSettings> read() async {
    final raw = await _database.readKeyValue(scope: _scope, key: _key);
    if (raw == null || raw.isEmpty) {
      return const AppSettings();
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const AppSettings();
    }
    final map = decoded.cast<String, dynamic>();
    return AppSettings(
      theme: WebTuiThemePreference.values.firstWhere(
        (theme) => theme.name == map['theme'],
        orElse: () => WebTuiThemePreference.system,
      ),
      languageCode: map['languageCode']?.toString() ?? 'vi',
      notificationsEnabled: map['notificationsEnabled'] == true,
      sensitivePreviewEnabled: map['sensitivePreviewEnabled'] == true,
      quietHoursEnabled: map['quietHoursEnabled'] == true,
      quietStart: map['quietStart']?.toString() ?? '22:00',
      quietEnd: map['quietEnd']?.toString() ?? '07:00',
    );
  }

  @override
  Future<void> save(AppSettings settings) {
    return _database.putKeyValue(
      scope: _scope,
      key: _key,
      value: jsonEncode({
        'theme': settings.theme.name,
        'languageCode': settings.languageCode,
        'notificationsEnabled': settings.notificationsEnabled,
        'sensitivePreviewEnabled': settings.sensitivePreviewEnabled,
        'quietHoursEnabled': settings.quietHoursEnabled,
        'quietStart': settings.quietStart,
        'quietEnd': settings.quietEnd,
      }),
    );
  }
}
