import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/platform/app_deep_link_coordinator.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_callback_inbox.dart';

import 'support/fakes.dart';

void main() {
  final instance = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: Uri.parse('https://chat.vpsttt.com'),
  );
  final navigations = <String>[];
  final oidc = <Uri>[];
  final ide = <Uri>[];
  String? token;
  var ready = true;
  late AppDeepLinkCoordinator coordinator;
  setUp(() {
    navigations.clear();
    oidc.clear();
    ide.clear();
    token = 'token';
    ready = true;
    coordinator = AppDeepLinkCoordinator(
      loadAccessToken: () async => token,
      loadActiveInstance: () => instance,
      navigate: navigations.add,
      handleOidcCallback: (uri) async => oidc.add(uri),
      handleIdeWebCallback: (uri) async => ide.add(uri),
      isAuthenticationReady: () => ready,
    );
  });

  test('callback IDE và OIDC không lẫn nhau, không vào location', () async {
    await coordinator.handle(callbackUri());
    expect(ide, [callbackUri()]);
    expect(oidc, isEmpty);
    await coordinator.handle(Uri.parse('webtui://oidc/callback?code=a'));
    expect(oidc, hasLength(1));
    expect(ide, hasLength(1));
    expect(navigations, isEmpty);
    expect(coordinator.pendingLocation, isNull);
    expect(
      '${parseAppDeepLink(callbackUri(), activeInstance: instance)}',
      isNot(contains('ma-callback')),
    );
  });

  test(
    'mở lạnh: giữ trong bộ nhớ tới khi phiên sẵn sàng, chỉ một lần',
    () async {
      token = null;
      await coordinator.handle(callbackUri());
      expect(ide, isEmpty);
      expect(navigations, isEmpty);
      expect(coordinator.hasPendingWork, isTrue);
      expect(coordinator.pendingLocation, isNull);
      await coordinator.onAuthenticationChanged(null);
      expect(ide, isEmpty);
      await coordinator.onAuthenticationChanged('token');
      await coordinator.onAuthenticationChanged('token');
      expect(ide, [callbackUri()]);
      expect(coordinator.hasPendingWork, isFalse);

      ide.clear();
      token = 'token';
      ready = false;
      await coordinator.handle(callbackUri());
      expect(ide, isEmpty);
      ready = true;
      await coordinator.onAuthenticationChanged('token');
      expect(ide, hasLength(1));
    },
  );

  test('callback rác chen vào lúc chờ không đè mất callback thật', () async {
    token = '';
    for (var i = 0; i < 10; i++) {
      await coordinator.handle(callbackUri(state: 'rac-$i'));
      if (i == 1) await coordinator.handle(callbackUri());
    }
    token = 'token';
    await coordinator.onAuthenticationChanged('token');
    expect(ide, contains(callbackUri()));
    expect(ide, hasLength(4));
  });

  test('link lạ bị bỏ', () async {
    for (final value in const [
      'webtui://ide-web/callback/x?state=a&code=b',
      'webtui://ide-web/callback?state=a&code=b#x',
      'webtui://u@ide-web/callback?state=a&code=b',
      'webtui://ide-web:9/callback?state=a&code=b',
      'https://ide-web/callback?state=a&code=b',
      'webtui://ide/callback?state=a&code=b',
    ]) {
      await coordinator.handle(Uri.parse(value));
    }
    expect(ide, isEmpty);
  });

  test('hộp trao callback: link lặp không mở màn hai lần', () {
    final inbox = IdeWebCallbackInbox();
    expect(inbox.deliver(callbackUri()), isTrue);
    expect(inbox.deliver(callbackUri()), isFalse);
    expect(inbox.take(), callbackUri());
    expect(inbox.take(), isNull);
    final got = <Uri>[];
    final stop = inbox.listen(got.add);
    expect(inbox.deliver(callbackUri()), isFalse);
    expect(got, hasLength(1));
    stop();
    expect(inbox.deliver(callbackUri()), isTrue);
  });
}
