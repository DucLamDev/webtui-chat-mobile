import '../entities/app_settings.dart';

abstract interface class AppSettingsRepository {
  Future<AppSettings> read();

  Future<void> save(AppSettings settings);
}
