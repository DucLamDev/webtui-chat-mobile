enum WebTuiThemePreference { system, light, dark }

/// Cỡ chữ của app (Cài đặt > Cỡ chữ): hệ số nhân thêm vào cỡ chữ hệ thống,
/// 7 nấc từ 85% tới 130%, mặc định 100%.
const appTextScaleMin = 0.85;
const appTextScaleMax = 1.3;
const appTextScaleDivisions = 6;
const appTextScaleDefault = 1.0;

/// Âm lượng chuông trong app (Cài đặt > Âm lượng): nhạc chuông cuộc gọi đến
/// khi đang mở app và chuông chờ khi gọi đi; 0 = tắt tiếng, nấc 10%.
const appSoundVolumeDefault = 0.8;
const appSoundVolumeDivisions = 10;

/// Đưa cỡ chữ về nấc gần nhất trong khoảng cho phép (giá trị lạ / cũ không làm
/// vỡ bố cục).
double normalizeAppTextScale(double value) {
  if (value.isNaN) return appTextScaleDefault;
  const step = (appTextScaleMax - appTextScaleMin) / appTextScaleDivisions;
  final index = ((value - appTextScaleMin) / step).round().clamp(
    0,
    appTextScaleDivisions,
  );
  return double.parse((appTextScaleMin + index * step).toStringAsFixed(3));
}

/// Đưa âm lượng về nấc 10% gần nhất trong 0..1.
double normalizeAppSoundVolume(double value) {
  if (value.isNaN) return appSoundVolumeDefault;
  final index = (value * appSoundVolumeDivisions).round().clamp(
    0,
    appSoundVolumeDivisions,
  );
  return index / appSoundVolumeDivisions;
}

/// Vị trí thanh kéo (0..1) ↔ cỡ chữ.
double appTextScaleToSlider(double scale) =>
    ((normalizeAppTextScale(scale) - appTextScaleMin) /
            (appTextScaleMax - appTextScaleMin))
        .clamp(0.0, 1.0);

double appTextScaleFromSlider(double position) => normalizeAppTextScale(
  appTextScaleMin + position * (appTextScaleMax - appTextScaleMin),
);

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
    this.textScale = appTextScaleDefault,
    this.soundVolume = appSoundVolumeDefault,
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

  /// Hệ số cỡ chữ của app (xem [normalizeAppTextScale]).
  final double textScale;

  /// Âm lượng chuông trong app, 0..1 (xem [normalizeAppSoundVolume]).
  final double soundVolume;

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
    double? textScale,
    double? soundVolume,
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
      textScale: textScale ?? this.textScale,
      soundVolume: soundVolume ?? this.soundVolume,
    );
  }
}
