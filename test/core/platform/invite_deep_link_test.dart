import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/platform/app_deep_link_coordinator.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';

void main() {
  final publisher = InstanceScope(
    instanceId: '11111111-1111-4111-8111-111111111111',
    serverOrigin: Uri.parse('https://chat.vpsttt.com'),
  );

  test('lời mời giữ đích qua login nhưng không sang máy chủ khác', () async {
    InstanceScope? active;
    final locations = <String>[];
    final prefills = <String>[];
    final coordinator = AppDeepLinkCoordinator(
      loadAccessToken: () async => null,
      loadActiveInstance: () => active,
      navigate: locations.add,
      handleOidcCallback: (_) async {},
      onInviteRequiresLogin: (token, host) => prefills.add('$host:$token'),
    );
    await coordinator.handle(
      Uri.parse('https://chat.vpsttt.com/invite/invite-12345'),
    );
    expect(prefills, ['chat.vpsttt.com:invite-12345']);
    expect(locations, ['/login']);
    active = publisher;
    await coordinator.onAuthenticationChanged('new-token');
    expect(locations.last, '/invite/invite-12345');
    expect(coordinator.pendingLocation, isNull);

    await coordinator.handle(
      Uri.parse('https://chat.vpsttt.com/invite/invite-67890'),
    );
    active = InstanceScope(
      instanceId: '22222222-2222-4222-8222-222222222222',
      serverOrigin: Uri.parse('https://other.example.com'),
    );
    await coordinator.onAuthenticationChanged('other-token');
    expect(locations.last, '/login');
    expect(coordinator.pendingLocation, isNull);
  });

  test('lời mời từ domain khác hoặc token có slash bị bỏ', () {
    for (final value in [
      'https://other.example.com/invite/invite-12345',
      'https://chat.vpsttt.com/invite/invite%2F12345',
      'https://chat.vpsttt.com:444/invite/invite-12345',
      'webtui://chat/invite/invite-12345?instance_id=other',
    ]) {
      expect(
        parseAppDeepLink(Uri.parse(value), activeInstance: publisher),
        isNull,
      );
    }
  });

  test('token chờ duyệt không tiêu thụ link mời trước khi vào app', () async {
    var ready = false;
    final locations = <String>[];
    final coordinator = AppDeepLinkCoordinator(
      loadAccessToken: () async => 'pending-token',
      loadActiveInstance: () => publisher,
      navigate: locations.add,
      handleOidcCallback: (_) async {},
      isAuthenticationReady: () => ready,
    );
    await coordinator.handle(
      Uri.parse('https://chat.vpsttt.com/invite/invite-12345'),
    );
    expect(locations, isEmpty);
    expect(coordinator.pendingLocation, '/invite/invite-12345');
    await coordinator.onAuthenticationChanged('pending-token');
    expect(locations, isEmpty);
    expect(coordinator.pendingLocation, '/invite/invite-12345');
    ready = true;
    await coordinator.onAuthenticationChanged('approved-token');
    expect(locations, ['/invite/invite-12345']);
    expect(coordinator.pendingLocation, isNull);
  });
}
