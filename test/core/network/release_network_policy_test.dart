import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/redirect_safe_file_downloader.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/core/network/self_hosted_server_uri.dart';

void main() {
  tearDown(() => debugReleaseNetworkPolicyOverride = null);

  group('bản phát hành chặn máy chủ localhost qua http', () {
    test('địa chỉ máy chủ', () {
      debugReleaseNetworkPolicyOverride = true;
      for (final value in [
        'http://localhost:8080',
        'http://127.0.0.1:8080',
        'http://dev.localhost',
        'http://LOCALHOST',
      ]) {
        expect(
          () => parseSelfHostedServerUri(value),
          throwsFormatException,
          reason: value,
        );
      }
      expect(
        parseSelfHostedServerUri('chat.example.com').toString(),
        'https://chat.example.com',
      );
    });

    test('WebSocket và tệp tải', () {
      debugReleaseNetworkPolicyOverride = true;
      expect(
        () => parseSelfHostedWebSocketUri('ws://localhost:8080/ws'),
        throwsFormatException,
      );
      expect(
        () => parseSelfHostedWebSocketUri('ws://127.0.0.1/ws'),
        throwsFormatException,
      );
      expect(
        redirectSafeHttpUriAllowed(Uri.parse('http://localhost/f')),
        isFalse,
      );
      expect(
        redirectSafeHttpUriAllowed(Uri.parse('http://127.0.0.1/f')),
        isFalse,
      );
      expect(
        redirectSafeHttpUriAllowed(Uri.parse('https://chat.example.com/f')),
        isTrue,
      );
    });

    test('bản gỡ lỗi vẫn nhận máy chủ thử trên máy', () {
      debugReleaseNetworkPolicyOverride = false;
      expect(
        parseSelfHostedServerUri('http://localhost:8080').toString(),
        'http://localhost:8080',
      );
      expect(
        parseSelfHostedWebSocketUri('ws://localhost:8080/ws').scheme,
        'ws',
      );
      expect(
        redirectSafeHttpUriAllowed(Uri.parse('http://127.0.0.1/f')),
        isTrue,
      );
    });
  });

  group('cấu hình mạng Android khai rõ ràng', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final release = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();
    final debug = File(
      'android/app/src/debug/res/xml/network_security_config.xml',
    ).readAsStringSync();

    test('manifest trỏ tới cấu hình mạng và cấm HTTP thường', () {
      expect(
        manifest,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
    });

    test('bản phát hành: không HTTP thường, chỉ tin chứng chỉ hệ thống', () {
      expect(
        release,
        contains('<base-config cleartextTrafficPermitted="false">'),
      );
      expect(release, contains('<certificates src="system" />'));
      expect(release, isNot(contains('src="user"')));
      expect(release, isNot(contains('cleartextTrafficPermitted="true"')));
      expect(release, isNot(contains('debug-overrides')));
    });

    test('bản debug chỉ mở HTTP cho máy chủ thử trên máy', () {
      expect(debug, isNot(contains('src="user"')));
      expect(
        debug,
        contains('<base-config cleartextTrafficPermitted="false">'),
      );
      final domains = RegExp(
        r'<domain[^>]*>([^<]+)</domain>',
      ).allMatches(debug).map((m) => m.group(1)).toSet();
      expect(domains, {'localhost', '127.0.0.1', '10.0.2.2'});
    });
  });
}
