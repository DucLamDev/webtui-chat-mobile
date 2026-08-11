import 'package:flutter/services.dart';

import '../security/instance_scope.dart';

final class NativeInstanceBindingService {
  const NativeInstanceBindingService();

  static const _channel = MethodChannel('webtui/instance_binding');

  Future<void> setValidatedInstance(
    InstanceScope scope, {
    required bool durableSession,
  }) async {
    try {
      await _channel.invokeMethod<void>('setValidatedInstance', {
        'instance_id': scope.instanceId,
        'scope_id': scope.storageId,
        'origin': scope.origin.toString(),
        'durable_session': durableSession,
      });
    } on MissingPluginException {
      // Android push is filtered by Dart/background secure storage.
    } on PlatformException {
      // Secure Dart gates remain authoritative if native persistence fails.
    }
  }

  Future<void> setSessionDurability(bool durable) async {
    try {
      await _channel.invokeMethod<void>('setSessionDurability', {
        'durable_session': durable,
      });
    } on MissingPluginException {
      // Android headless delivery is filtered by secure Dart storage.
    } on PlatformException {
      // Best effort. iOS PushKit also requires this native durable marker.
    }
  }

  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clearValidatedInstance');
    } on MissingPluginException {
      // No native PushKit path on this platform.
    } on PlatformException {
      // Best effort; iOS PushKit also requires the live-valid flag.
    }
  }
}
