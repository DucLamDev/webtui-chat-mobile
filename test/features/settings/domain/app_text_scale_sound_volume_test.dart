import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/settings/domain/entities/app_settings.dart';

void main() {
  test(
    'cỡ chữ: 7 nấc 85% → 130%, mặc định 100%, giá trị lạ về nấc gần nhất',
    () {
      expect(const AppSettings().textScale, 1.0);
      expect(normalizeAppTextScale(1.0), 1.0);
      expect(normalizeAppTextScale(0.9), 0.925);
      expect(normalizeAppTextScale(5), appTextScaleMax);
      expect(normalizeAppTextScale(0.1), appTextScaleMin);
      expect(normalizeAppTextScale(double.nan), appTextScaleDefault);
      // Vị trí thanh ↔ cỡ chữ khớp nhau ở mọi nấc (không trôi số lẻ).
      for (var index = 0; index <= appTextScaleDivisions; index++) {
        final position = index / appTextScaleDivisions;
        final scale = appTextScaleFromSlider(position);
        expect(appTextScaleToSlider(scale), closeTo(position, 1e-9));
      }
      expect(appTextScaleFromSlider(2 / appTextScaleDivisions), 1.0);
      expect(appTextScaleFromSlider(1), appTextScaleMax);
    },
  );

  test('âm lượng: nấc 10% trong 0..1, mặc định 80%', () {
    expect(const AppSettings().soundVolume, 0.8);
    expect(normalizeAppSoundVolume(0.83), 0.8);
    expect(normalizeAppSoundVolume(0.06), 0.1);
    expect(normalizeAppSoundVolume(-1), 0);
    expect(normalizeAppSoundVolume(7), 1);
    expect(normalizeAppSoundVolume(double.nan), appSoundVolumeDefault);
  });

  test('copyWith giữ cỡ chữ / âm lượng khi đổi trường khác', () {
    const settings = AppSettings(textScale: 1.15, soundVolume: 0.3);
    final next = settings.copyWith(theme: WebTuiThemePreference.dark);
    expect(next.textScale, 1.15);
    expect(next.soundVolume, 0.3);
  });
}
