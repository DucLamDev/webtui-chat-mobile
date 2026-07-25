import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/settings/domain/entities/mobile_release_policy.dart';

void main() {
  test('requires update when current version is below minimum version', () {
    const policy = MobileReleasePolicy(
      platform: 'android',
      channel: 'stable',
      currentVersion: '1.2.0+12',
      minimumVersion: '1.2.1',
      recommendedVersion: '1.3.0',
    );

    expect(policy.requiresUpdate, isTrue);
    expect(policy.recommendsUpdate, isTrue);
  });

  test('recommends update without forcing when only recommended is newer', () {
    const policy = MobileReleasePolicy(
      platform: 'android',
      channel: 'stable',
      currentVersion: '1.2.1',
      minimumVersion: '1.2.0',
      recommendedVersion: '1.3.0',
    );

    expect(policy.requiresUpdate, isFalse);
    expect(policy.recommendsUpdate, isTrue);
  });
}
