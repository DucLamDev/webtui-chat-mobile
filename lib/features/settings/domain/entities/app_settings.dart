enum WebTuiThemePreference { system, light, dark }

final class AppSettings {
  const AppSettings({
    this.theme = WebTuiThemePreference.system,
    this.languageCode = 'vi',
    this.notificationsEnabled = true,
    this.sensitivePreviewEnabled = false,
    this.quietHoursEnabled = false,
    this.quietStart = '22:00',
    this.quietEnd = '07:00',
    this.microphoneEnabledOnJoin = true,
    this.cameraEnabledOnJoin = true,
  });

  final WebTuiThemePreference theme;
  final String languageCode;
  final bool notificationsEnabled;
  final bool sensitivePreviewEnabled;
  final bool quietHoursEnabled;
  final String quietStart;
  final String quietEnd;
  final bool microphoneEnabledOnJoin;
  final bool cameraEnabledOnJoin;

  AppSettings copyWith({
    WebTuiThemePreference? theme,
    String? languageCode,
    bool? notificationsEnabled,
    bool? sensitivePreviewEnabled,
    bool? quietHoursEnabled,
    String? quietStart,
    String? quietEnd,
    bool? microphoneEnabledOnJoin,
    bool? cameraEnabledOnJoin,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      languageCode: languageCode ?? this.languageCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      sensitivePreviewEnabled:
          sensitivePreviewEnabled ?? this.sensitivePreviewEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
      microphoneEnabledOnJoin:
          microphoneEnabledOnJoin ?? this.microphoneEnabledOnJoin,
      cameraEnabledOnJoin: cameraEnabledOnJoin ?? this.cameraEnabledOnJoin,
    );
  }
}
