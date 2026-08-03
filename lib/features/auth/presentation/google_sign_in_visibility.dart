import 'package:flutter/foundation.dart';

bool canShowGoogleSignIn({
  required TargetPlatform targetPlatform,
  required String clientId,
  required String serverClientId,
}) {
  return targetPlatform != TargetPlatform.iOS &&
      clientId.trim().isNotEmpty &&
      serverClientId.trim().isNotEmpty;
}
