import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/notifications/push_notification_service.dart';
import 'package:webtui_chat/core/notifications/scoped_local_notification_service.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';

const _instanceAId = '11111111-1111-4111-8111-111111111111';
const _instanceBId = '22222222-2222-4222-8222-222222222222';
final _instanceB = InstanceScope(
  instanceId: _instanceBId,
  serverOrigin: Uri.parse('https://server-b.example'),
);

void main() {
  test('stale A data-only push is not shown while valid B is shown', () async {
    final displayed = <Map<String, Object?>>[];
    Future<bool> display(Map<String, Object?> data) async {
      displayed.add(data);
      return true;
    }

    final staleShown = await displayScopedDataOnlyNotification(
      data: _messageData(instanceId: _instanceAId),
      bindingMatches: (data) async => notificationInstanceMatches(
        payloadInstanceId: data['instance_id']?.toString(),
        activeInstanceId: _instanceBId,
      ),
      display: display,
    );
    final currentShown = await displayScopedDataOnlyNotification(
      data: _messageData(instanceId: _instanceBId),
      bindingMatches: (data) async => notificationInstanceMatches(
        payloadInstanceId: data['instance_id']?.toString(),
        activeInstanceId: _instanceBId,
      ),
      display: display,
    );

    expect(staleShown, isFalse);
    expect(currentShown, isTrue);
    expect(displayed, hasLength(1));
    expect(displayed.single['instance_id'], _instanceBId);
  });

  test('tap A is rejected while same-ID target B is routed', () {
    final stale = scopedNotificationTargetIfCurrent(
      data: _messageData(instanceId: _instanceAId),
      instanceScope: _instanceB,
      workspaceId: 'workspace-shared',
      persistedBindingMatches: true,
    );
    final current = scopedNotificationTargetIfCurrent(
      data: _messageData(instanceId: _instanceBId),
      instanceScope: _instanceB,
      workspaceId: 'workspace-shared',
      persistedBindingMatches: true,
    );
    final invalidated = scopedNotificationTargetIfCurrent(
      data: _messageData(instanceId: _instanceBId),
      instanceScope: _instanceB,
      workspaceId: 'workspace-shared',
      persistedBindingMatches: false,
    );

    expect(stale, isNull);
    expect(current?.channelId, 'channel-shared');
    expect(current?.messageId, 'message-shared');
    expect(invalidated, isNull);
  });

  test('workspace switch accepts W2 and rejects a late W1 notification', () {
    final lateWorkspaceOne = scopedNotificationTargetIfCurrent(
      data: _messageData(
        instanceId: _instanceBId,
        workspaceId: 'workspace-one',
      ),
      instanceScope: _instanceB,
      workspaceId: 'workspace-two',
      persistedBindingMatches: true,
    );
    final currentWorkspaceTwo = scopedNotificationTargetIfCurrent(
      data: _messageData(
        instanceId: _instanceBId,
        workspaceId: 'workspace-two',
      ),
      instanceScope: _instanceB,
      workspaceId: 'workspace-two',
      persistedBindingMatches: true,
    );

    expect(lateWorkspaceOne, isNull);
    expect(currentWorkspaceTwo?.workspaceId, 'workspace-two');
  });

  test('server switch between validation and display fails closed', () async {
    var validationCount = 0;
    var displayCount = 0;

    final shown = await displayScopedDataOnlyNotification(
      data: _messageData(instanceId: _instanceBId),
      bindingMatches: (_) async => ++validationCount == 1,
      display: (_) async {
        displayCount += 1;
        return true;
      },
    );

    expect(shown, isFalse);
    expect(validationCount, 2);
    expect(displayCount, 0);
  });

  test(
    'persisted notification binding requires session and workspace scope',
    () {
      bool matches({
        String? sessionScopeId,
        String? workspaceScopeId,
        String workspaceId = 'workspace-shared',
        String generation = 'generation-b',
        String? persistence,
        bool requireDurableSession = false,
        bool durableAccountRecord = true,
      }) {
        return notificationBindingMatches(
          payloadInstanceId: _instanceBId,
          payloadWorkspaceId: 'workspace-shared',
          activeServerBaseUrl: _instanceB.origin.toString(),
          activeInstanceId: _instanceBId,
          activeInstanceScopeId: _instanceB.storageId,
          liveInstanceScopeId: _instanceB.storageId,
          sessionInstanceScopeId: sessionScopeId ?? _instanceB.storageId,
          activeWorkspaceId: workspaceId,
          workspaceInstanceScopeId: workspaceScopeId ?? _instanceB.storageId,
          activeInstanceGeneration: generation,
          sessionPersistence: persistence,
          requireDurableSession: requireDurableSession,
          durableAccountRecord: durableAccountRecord,
        );
      }

      expect(matches(), isTrue);
      expect(matches(sessionScopeId: 'scope-a'), isFalse);
      expect(matches(workspaceScopeId: 'scope-a'), isFalse);
      expect(matches(workspaceId: 'workspace-a'), isFalse);
      expect(matches(generation: ''), isFalse);
      expect(
        matches(
          persistence: durableSessionPersistenceValue,
          requireDurableSession: true,
        ),
        isTrue,
      );
      expect(
        matches(persistence: 'session_only', requireDurableSession: true),
        isFalse,
        reason: 'a headless isolate must not restore a process-only session',
      );
      expect(
        matches(
          persistence: durableSessionPersistenceValue,
          requireDurableSession: true,
          durableAccountRecord: false,
        ),
        isFalse,
        reason: 'partial durable globals cannot authorize headless display',
      );
    },
  );

  test('routing payload is deterministic and excludes display previews', () {
    final data = _messageData(instanceId: _instanceBId);
    final first = ScopedLocalNotification.fromData(data);
    final second = ScopedLocalNotification.fromData(data);
    final decoded = decodeScopedNotificationRoutingPayload(
      first.encodedRoutingPayload,
    );

    expect(first.id, second.id);
    expect(first.tag, second.tag);
    expect(decoded, containsPair('instance_id', _instanceBId));
    expect(decoded, containsPair('workspace_id', 'workspace-shared'));
    expect(decoded, isNot(contains('title')));
    expect(decoded, isNot(contains('body')));
    expect(first.encodedRoutingPayload, isNot(contains('Sensitive preview')));
  });

  test('ordinary local renderer rejects call and external targets', () {
    expect(
      scopedNotificationRoutingData({
        ..._messageData(instanceId: _instanceBId),
        'target_type': 'call',
        'event_type': 'call_invite',
      }),
      isNull,
    );
    expect(
      scopedNotificationRoutingData({
        ..._messageData(instanceId: _instanceBId),
        'channel_id': null,
        'message_id': null,
        'deep_link': 'https://evil.example/conversations/shared',
      }),
      isNull,
    );
  });

  test('message cleanup preserves active CallKit channel notifications', () {
    final targets = messageNotificationCancelTargets(const [
      ActiveNotification(
        id: 11,
        tag: 'message-tag',
        channelId: 'webtui_messages',
      ),
      ActiveNotification(
        id: 22,
        tag: 'call-tag',
        channelId: 'flutter_callkit_incoming',
      ),
      ActiveNotification(channelId: 'webtui_messages'),
    ]);

    expect(targets, [(id: 11, tag: 'message-tag')]);
  });

  test(
    'switch after show precheck cancels the just-rendered preview',
    () async {
      var current = true;
      var showCount = 0;
      var cancelCount = 0;

      final shown = await showScopedNotificationIfCurrent(
        isStillCurrent: () async => current,
        show: () async {
          showCount += 1;
          current = false;
        },
        cancel: () async => cancelCount += 1,
      );

      expect(shown, isFalse);
      expect(showCount, 1);
      expect(cancelCount, 1);
    },
  );
}

Map<String, Object?> _messageData({
  required String instanceId,
  String workspaceId = 'workspace-shared',
}) {
  return <String, Object?>{
    'instance_id': instanceId,
    'event_id': 'event-shared',
    'event_type': 'message',
    'target_type': 'message',
    'workspace_id': workspaceId,
    'channel_id': 'channel-shared',
    'message_id': 'message-shared',
    'title': 'Workspace',
    'body': 'Sensitive preview',
    'deep_link':
        'webtui://chat/conversations/channel-shared?workspaceId=$workspaceId',
  };
}
