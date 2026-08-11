import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'iOS release and debug targets declare the production universal link',
    () {
      for (final path in const [
        'ios/Runner/Runner.entitlements',
        'ios/Runner/RunnerDebug.entitlements',
      ]) {
        final contents = File(path).readAsStringSync();
        expect(contents, contains('com.apple.developer.associated-domains'));
        expect(contents, contains('applinks:chat.vpsttt.com'));
      }
    },
  );

  test('iOS forwards universal links to the Flutter deep-link boundary', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(appDelegate, contains('continue userActivity: NSUserActivity'));
    expect(appDelegate, contains('NSUserActivityTypeBrowsingWeb'));
    expect(appDelegate, contains('isTrustedUniversalLink(url)'));
    expect(appDelegate, contains('chat.vpsttt.com'));
    expect(appDelegate, contains('let flutterHandled = super.application('));
    expect(appDelegate, contains('deepLinkChannel?.invokeMethod("url"'));
  });

  test('built-in iOS deep linking cannot bypass the app coordinator', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(infoPlist, contains('<key>FlutterDeepLinkingEnabled</key>'));
    expect(
      infoPlist,
      matches(
        RegExp(
          r'<key>FlutterDeepLinkingEnabled</key>\s*<false\s*/>',
          multiLine: true,
        ),
      ),
    );
  });

  test('native PushKit is fail-closed on the persisted instance binding', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate, contains('"webtui/instance_binding"'));
    expect(appDelegate, contains('sanitizePersistedInstanceBinding()'));
    expect(
      appDelegate,
      contains('defaults.bool(forKey: validatedInstanceKey)'),
    );
    expect(appDelegate, contains('defaults.bool(forKey: durableSessionKey)'));
    expect(appDelegate, contains('call.method == "setSessionDurability"'));
    expect(appDelegate, contains('info["instance_id"] as? String'));
    expect(appDelegate, contains('payloadInstanceID == activeInstanceID'));
    expect(appDelegate, contains('info["call_id"] as? String'));
    expect(appDelegate, contains('info["workspace_id"] as? String'));
    expect(appDelegate, contains('extra["instance_id"] = payloadInstanceID'));
    expect(appDelegate, contains('extra["server_base_url"] = activeOrigin'));
    expect(
      appDelegate,
      matches(
        RegExp(r'else \{\s*completion\(\)\s*return\s*\}', multiLine: true),
      ),
    );
  });

  test('native instance binding supports canonical HTTPS custom ports', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(appDelegate, contains('if let port = components.port, port != 443'));
    expect(appDelegate, contains('normalized.port = port'));
    expect(
      appDelegate,
      isNot(contains('components.port == nil || components.port == 443')),
    );
  });
}
