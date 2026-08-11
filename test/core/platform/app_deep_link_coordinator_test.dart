import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/platform/app_deep_link_coordinator.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';

void main() {
  test(
    'cold authenticated universal link opens the exact conversation',
    () async {
      final navigations = <String>[];
      final coordinator = AppDeepLinkCoordinator(
        loadAccessToken: () async => 'access-token',
        loadActiveInstance: () => _publisherInstance,
        navigate: navigations.add,
        handleOidcCallback: (_) async {},
      );

      await coordinator.handle(
        Uri.parse(
          'https://chat.vpsttt.com/conversations/channel-1'
          '?workspace_id=workspace-1&message_id=message-1&ignored=drop-me',
        ),
      );

      expect(navigations, [
        '/conversations/channel-1?workspaceId=workspace-1&messageId=message-1',
      ]);
    },
  );

  test('warm authenticated notification link opens notifications', () async {
    final navigations = <String>[];
    final coordinator = AppDeepLinkCoordinator(
      loadAccessToken: () async => 'access-token',
      loadActiveInstance: () => _publisherInstance,
      navigate: navigations.add,
      handleOidcCallback: (_) async {},
    );

    await coordinator.handle(
      Uri.parse(
        'webtui://chat/notifications?workspaceId=workspace-1'
        '&instance_id=${_publisherInstance.instanceId}',
      ),
    );

    expect(navigations, ['/notifications?workspaceId=workspace-1']);
  });

  test('exact conversations link opens the messages home', () async {
    final navigations = <String>[];
    final coordinator = AppDeepLinkCoordinator(
      loadAccessToken: () async => 'access-token',
      loadActiveInstance: () => _publisherInstance,
      navigate: navigations.add,
      handleOidcCallback: (_) async {},
    );

    await coordinator.handle(
      Uri.parse('https://chat.vpsttt.com/conversations'),
    );

    expect(navigations, ['/']);
  });

  test('unauthenticated link is retained and resumed after login', () async {
    final navigations = <String>[];
    final coordinator = AppDeepLinkCoordinator(
      loadAccessToken: () async => null,
      loadActiveInstance: () => _publisherInstance,
      navigate: navigations.add,
      handleOidcCallback: (_) async {},
    );

    await coordinator.handle(
      Uri.parse('https://chat.vpsttt.com/conversations/channel-2'),
    );

    expect(navigations, ['/login']);
    expect(coordinator.pendingLocation, '/conversations/channel-2');

    await coordinator.onAuthenticationChanged('new-access-token');

    expect(navigations, ['/login', '/conversations/channel-2']);
    expect(coordinator.pendingLocation, isNull);
  });

  test('malicious and non-allowlisted universal links are ignored', () async {
    final navigations = <String>[];
    final coordinator = AppDeepLinkCoordinator(
      loadAccessToken: () async => 'access-token',
      loadActiveInstance: () => _publisherInstance,
      navigate: navigations.add,
      handleOidcCallback: (_) async {},
    );

    for (final value in const [
      'https://chat.vpsttt.com.evil.example/conversations/channel-1',
      'https://chat.vpsttt.com:444/conversations/channel-1',
      'https://chat.vpsttt.com/settings',
      'https://chat.vpsttt.com/notifications/unread',
      'https://chat.vpsttt.com/conversations/../settings',
      'http://chat.vpsttt.com/conversations/channel-1',
    ]) {
      await coordinator.handle(Uri.parse(value));
    }

    expect(navigations, isEmpty);
  });

  test(
    'OIDC callback remains routed to the auth controller boundary',
    () async {
      Uri? callback;
      final coordinator = AppDeepLinkCoordinator(
        loadAccessToken: () async => null,
        loadActiveInstance: () => _publisherInstance,
        navigate: (_) {},
        handleOidcCallback: (uri) async => callback = uri,
      );
      final uri = Uri.parse(
        'webtui://oidc/callback?server=chat.vpsttt.com&oidc_code=code',
      );

      await coordinator.handle(uri);

      expect(callback, uri);
    },
  );

  test(
    'publisher conversation ID is ignored on another active server',
    () async {
      final navigations = <String>[];
      final coordinator = AppDeepLinkCoordinator(
        loadAccessToken: () async => 'access-token',
        loadActiveInstance: () => _customerInstance,
        navigate: navigations.add,
        handleOidcCallback: (_) async {},
      );

      await coordinator.handle(
        Uri.parse('https://chat.vpsttt.com/conversations/same-channel-id'),
      );

      expect(navigations, isEmpty);
    },
  );
}

final _publisherInstance = InstanceScope(
  instanceId: '11111111-1111-4111-8111-111111111111',
  serverOrigin: Uri.parse('https://chat.vpsttt.com'),
);

final _customerInstance = InstanceScope(
  instanceId: '22222222-2222-4222-8222-222222222222',
  serverOrigin: Uri.parse('https://customer.example'),
);
