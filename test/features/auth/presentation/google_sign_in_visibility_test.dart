import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/auth/presentation/google_sign_in_visibility.dart';

void main() {
  test('shows Google on Android only when both OAuth IDs are configured', () {
    expect(
      canShowGoogleSignIn(
        targetPlatform: TargetPlatform.android,
        clientId: 'android-client',
        serverClientId: 'server-client',
      ),
      isTrue,
    );
    expect(
      canShowGoogleSignIn(
        targetPlatform: TargetPlatform.android,
        clientId: '',
        serverClientId: 'server-client',
      ),
      isFalse,
    );
  });

  test('hides Google on iOS until Sign in with Apple is implemented', () {
    expect(
      canShowGoogleSignIn(
        targetPlatform: TargetPlatform.iOS,
        clientId: 'ios-client',
        serverClientId: 'server-client',
      ),
      isFalse,
    );
  });
}
