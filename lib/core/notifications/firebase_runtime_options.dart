import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

final class FirebaseRuntimeOptions {
  const FirebaseRuntimeOptions._();

  static FirebaseOptions? currentPlatform() {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const messagingSenderId = String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
    );
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    final appId = _firstNonEmpty(
      Platform.isIOS
          ? const String.fromEnvironment('FIREBASE_IOS_APP_ID')
          : const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
      const String.fromEnvironment('FIREBASE_APP_ID'),
    );

    if (_hasBlank([apiKey, appId, messagingSenderId, projectId])) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: _optional('FIREBASE_AUTH_DOMAIN'),
      databaseURL: _optional('FIREBASE_DATABASE_URL'),
      storageBucket: _optional('FIREBASE_STORAGE_BUCKET'),
      measurementId: _optional('FIREBASE_MEASUREMENT_ID'),
      androidClientId: _optional('FIREBASE_ANDROID_CLIENT_ID'),
      iosClientId: _optional('FIREBASE_IOS_CLIENT_ID'),
      iosBundleId: _optional('FIREBASE_IOS_BUNDLE_ID'),
      appGroupId: _optional('FIREBASE_IOS_APP_GROUP_ID'),
    );
  }
}

bool _hasBlank(Iterable<String> values) {
  return values.any((value) => value.trim().isEmpty);
}

String _firstNonEmpty(String primary, String fallback) {
  final trimmed = primary.trim();
  return trimmed.isEmpty ? fallback.trim() : trimmed;
}

String? _optional(String key) {
  final value = switch (key) {
    'FIREBASE_AUTH_DOMAIN' => const String.fromEnvironment(
      'FIREBASE_AUTH_DOMAIN',
    ),
    'FIREBASE_DATABASE_URL' => const String.fromEnvironment(
      'FIREBASE_DATABASE_URL',
    ),
    'FIREBASE_STORAGE_BUCKET' => const String.fromEnvironment(
      'FIREBASE_STORAGE_BUCKET',
    ),
    'FIREBASE_MEASUREMENT_ID' => const String.fromEnvironment(
      'FIREBASE_MEASUREMENT_ID',
    ),
    'FIREBASE_ANDROID_CLIENT_ID' => const String.fromEnvironment(
      'FIREBASE_ANDROID_CLIENT_ID',
    ),
    'FIREBASE_IOS_CLIENT_ID' => const String.fromEnvironment(
      'FIREBASE_IOS_CLIENT_ID',
    ),
    'FIREBASE_IOS_BUNDLE_ID' => const String.fromEnvironment(
      'FIREBASE_IOS_BUNDLE_ID',
    ),
    'FIREBASE_IOS_APP_GROUP_ID' => const String.fromEnvironment(
      'FIREBASE_IOS_APP_GROUP_ID',
    ),
    _ => '',
  };
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
