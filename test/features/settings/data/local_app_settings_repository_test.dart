import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/features/settings/data/repositories/local_app_settings_repository.dart';
import 'package:webtui_chat/features/settings/domain/entities/app_settings.dart';

void main() {
  late AppDatabase database;
  late LocalAppSettingsRepository repository;

  setUp(() {
    database = AppDatabase(createInMemoryDriftConnection());
    repository = LocalAppSettingsRepository(database);
  });
  tearDown(() => database.close());

  test('lưu rồi đọc lại cỡ chữ và âm lượng, giữ các cài đặt khác', () async {
    await repository.save(
      const AppSettings(
        theme: WebTuiThemePreference.dark,
        languageCode: 'en',
        textScale: 1.15,
        soundVolume: 0.3,
      ),
    );
    final settings = await repository.read();
    expect(settings.textScale, 1.15);
    expect(settings.soundVolume, 0.3);
    expect(settings.theme, WebTuiThemePreference.dark);
    expect(settings.languageCode, 'en');
  });

  test('dữ liệu bản cũ chưa có hai trường: dùng mặc định', () async {
    await database.putKeyValue(
      scope: 'app_settings',
      key: 'current',
      value: jsonEncode({'theme': 'light', 'languageCode': 'vi'}),
    );
    final settings = await repository.read();
    expect(settings.textScale, appTextScaleDefault);
    expect(settings.soundVolume, appSoundVolumeDefault);
    expect(settings.theme, WebTuiThemePreference.light);
  });

  test('giá trị lạ không làm vỡ bố cục: về nấc / khoảng cho phép', () async {
    await database.putKeyValue(
      scope: 'app_settings',
      key: 'current',
      value: jsonEncode({'textScale': 9, 'soundVolume': -2}),
    );
    var settings = await repository.read();
    expect(settings.textScale, appTextScaleMax);
    expect(settings.soundVolume, 0);

    await database.putKeyValue(
      scope: 'app_settings',
      key: 'current',
      value: jsonEncode({'textScale': 'to', 'soundVolume': 'nho'}),
    );
    settings = await repository.read();
    expect(settings.textScale, appTextScaleDefault);
    expect(settings.soundVolume, appSoundVolumeDefault);
  });
}
