import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/notifications/native_incoming_call_service.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';

const _instanceAId = '11111111-1111-4111-8111-111111111111';
const _instanceBId = '22222222-2222-4222-8222-222222222222';
final _instanceA = InstanceScope(
  instanceId: _instanceAId,
  serverOrigin: Uri.parse('https://server-a.example'),
);
final _instanceB = InstanceScope(
  instanceId: _instanceBId,
  serverOrigin: Uri.parse('https://server-b.example'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_callkit_incoming');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    FlutterSecureStorage.setMockInitialValues(
      _activeCallBinding(_instanceA, workspaceId: 'workspace-1'),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'outgoing audio call starts native lifecycle with scoped metadata',
    () async {
      await NativeIncomingCallService.startOutgoingCall(
        instanceScope: _instanceA,
        callId: ' call-123 ',
        workspaceId: ' workspace-1 ',
        channelId: ' channel-1 ',
        title: ' Support ',
        isVideo: false,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'startCall');
      final arguments = Map<String, Object?>.from(
        calls.single.arguments as Map,
      );
      expect(arguments['id'], 'call-123');
      expect(arguments['nameCaller'], 'Support');
      expect(arguments['appName'], 'WebTUI Chat');
      expect(arguments['type'], 0);
      final extra = Map<String, Object?>.from(arguments['extra'] as Map);
      expect(extra, containsPair('workspace_id', 'workspace-1'));
      expect(extra, containsPair('channel_id', 'channel-1'));
      expect(extra, containsPair('mode', 'audio'));
      expect(extra, containsPair('event_type', 'call_started'));
      expect(extra, containsPair('instance_id', _instanceAId));
      expect(
        extra,
        containsPair('server_base_url', 'https://server-a.example'),
      );
    },
  );

  test('outgoing video call identifies camera media type', () async {
    await NativeIncomingCallService.startOutgoingCall(
      instanceScope: _instanceA,
      callId: 'video-call',
      workspaceId: 'workspace-1',
      channelId: 'channel-1',
      title: '',
      isVideo: true,
    );

    final arguments = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(arguments['type'], 1);
    expect(arguments['nameCaller'], 'Cuộc gọi WebTUI Chat');
    expect(
      Map<String, Object?>.from(arguments['extra'] as Map)['mode'],
      'video',
    );
  });

  test('blank outgoing call id fails before invoking native code', () async {
    await expectLater(
      NativeIncomingCallService.startOutgoingCall(
        instanceScope: _instanceA,
        callId: '  ',
        workspaceId: 'workspace-1',
        channelId: 'channel-1',
        title: 'Support',
        isVideo: false,
      ),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
  });

  test('outgoing call fails closed after active instance switch', () async {
    FlutterSecureStorage.setMockInitialValues(
      _activeCallBinding(_instanceB, workspaceId: 'workspace-1'),
    );

    await expectLater(
      NativeIncomingCallService.startOutgoingCall(
        instanceScope: _instanceA,
        callId: 'shared-call',
        workspaceId: 'workspace-1',
        channelId: 'shared-channel',
        title: 'Support',
        isVideo: false,
      ),
      throwsStateError,
    );
    expect(calls, isEmpty);
  });

  test('outgoing call requires a live-validated instance binding', () async {
    final values = _activeCallBinding(_instanceA, workspaceId: 'workspace-1')
      ..remove(SecureStoreKey.liveDiscoveryValidatedScopeId.value);
    FlutterSecureStorage.setMockInitialValues(values);

    await expectLater(
      NativeIncomingCallService.startOutgoingCall(
        instanceScope: _instanceA,
        callId: 'call-123',
        workspaceId: 'workspace-1',
        channelId: 'channel-1',
        title: 'Support',
        isVideo: false,
      ),
      throwsStateError,
    );
    expect(calls, isEmpty);
  });

  test('end call always forwards the terminal call id', () async {
    await NativeIncomingCallService.endCall(' call-123 ');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'endCall');
    expect(calls.single.arguments, <String, Object?>{'id': 'call-123'});
  });

  test('cold-process pending action restores scoped target and stable id', () {
    final actionId = NativeIncomingCallAction.actionIdFor(
      NativeIncomingCallActionType.decline,
      'call-123',
      instanceId: _instanceAId,
    );
    final action = NativeIncomingCallAction.tryFromPendingPayload({
      'action_id': actionId,
      'event': 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE',
      'call_id': 'call-123',
      'instance_id': _instanceAId,
      'workspace_id': 'workspace-1',
      'channel_id': 'channel-1',
      'mode': 'video',
      'status': 'ringing',
      'target_type': 'call',
      'event_type': 'call_invite',
      'caller_name': 'Support',
      'organization_name': 'WebTUI Chat',
      'server_base_url': 'https://server-a.example',
    });

    expect(action, isNotNull);
    expect(action!.type, NativeIncomingCallActionType.decline);
    expect(action.target.callId, 'call-123');
    expect(action.target.workspaceId, 'workspace-1');
    expect(action.target.channelId, 'channel-1');
    expect(action.target.callMode, 'video');
    expect(action.target.callerName, 'Support');
    expect(
      action.actionId,
      NativeIncomingCallAction.actionIdFor(
        NativeIncomingCallActionType.decline,
        'call-123',
        instanceId: _instanceAId,
      ),
    );
  });

  test('same call id on two instances yields distinct durable action ids', () {
    final actionA = NativeIncomingCallAction.actionIdFor(
      NativeIncomingCallActionType.ended,
      'shared-call',
      instanceId: _instanceAId,
    );
    final actionB = NativeIncomingCallAction.actionIdFor(
      NativeIncomingCallActionType.ended,
      'shared-call',
      instanceId: _instanceBId,
    );

    expect(actionA, isNot(actionB));
    expect(actionA, contains(_instanceAId));
    expect(actionB, contains(_instanceBId));
  });

  test('pending action parser fails closed without workspace evidence', () {
    expect(
      NativeIncomingCallAction.tryFromPendingPayload({
        'event': 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT',
        'call_id': 'call-123',
        'instance_id': _instanceAId,
        'server_base_url': 'https://server-a.example',
      }),
      isNull,
    );
  });

  test('timeout event keeps workspace and trusted-server selector', () {
    final action = NativeIncomingCallService.actionFromCallkitEvent(
      const CallEventActionCallTimeout(
        CallKitParams(
          id: 'call-123',
          extra: {
            'call_id': 'call-123',
            'workspace_id': 'workspace-1',
            'channel_id': 'channel-1',
            'instance_id': _instanceAId,
            'server_base_url': 'https://chat.example.com',
          },
        ),
      ),
    );

    expect(action, isNotNull);
    expect(action!.type, NativeIncomingCallActionType.timeout);
    expect(action.target.workspaceId, 'workspace-1');
    expect(action.serverBaseUrl, 'https://chat.example.com');
  });

  test('background origin validation rejects SSRF and bearer redirects', () {
    expect(
      validatedBackgroundCallHttpsOrigin('https://chat.example.com'),
      Uri.parse('https://chat.example.com'),
    );
    expect(validatedBackgroundCallHttpsOrigin('http://chat.example.com'), null);
    expect(validatedBackgroundCallHttpsOrigin('https://user@evil.test'), null);
    expect(
      validatedBackgroundCallHttpsOrigin('https://chat.example.com/api'),
      null,
    );
    expect(
      validatedBackgroundCallHttpsOrigin(
        'https://chat.example.com?next=https://evil.test',
      ),
      null,
    );
  });

  test('background bearer binding requires exact server and workspace', () {
    final active = Uri.parse('https://chat.example.com');

    expect(
      backgroundCallBindingMatches(
        activeOrigin: active,
        actionOrigin: Uri.parse('https://chat.example.com'),
        activeWorkspaceId: 'workspace-1',
        actionWorkspaceId: 'workspace-1',
      ),
      isTrue,
    );
    expect(
      backgroundCallBindingMatches(
        activeOrigin: active,
        actionOrigin: Uri.parse('https://evil.test'),
        activeWorkspaceId: 'workspace-1',
        actionWorkspaceId: 'workspace-1',
      ),
      isFalse,
    );
    expect(
      backgroundCallBindingMatches(
        activeOrigin: active,
        actionOrigin: Uri.parse('https://chat.example.com'),
        activeWorkspaceId: 'workspace-1',
        actionWorkspaceId: 'workspace-2',
      ),
      isFalse,
    );
  });

  test(
    'background credentials become invalid after instance generation switch',
    () {
      bool matches({
        String activeScope = 'scope-a',
        String generation = 'generation-a',
        String persistence = durableSessionPersistenceValue,
        bool durableAccountRecord = true,
        Uri? origin,
      }) {
        return backgroundCallCredentialBindingMatches(
          expectedOrigin: Uri.parse('https://server-a.example'),
          currentOrigin: origin ?? Uri.parse('https://server-a.example'),
          expectedWorkspaceId: 'workspace-shared',
          currentWorkspaceId: 'workspace-shared',
          expectedInstanceId: '11111111-1111-4111-8111-111111111111',
          currentInstanceId: '11111111-1111-4111-8111-111111111111',
          expectedInstanceScopeId: 'scope-a',
          activeInstanceScopeId: activeScope,
          liveInstanceScopeId: activeScope,
          sessionInstanceScopeId: activeScope,
          workspaceInstanceScopeId: activeScope,
          expectedGeneration: 'generation-a',
          currentGeneration: generation,
          sessionPersistence: persistence,
          durableAccountRecord: durableAccountRecord,
        );
      }

      expect(matches(), isTrue);
      expect(matches(generation: 'generation-b'), isFalse);
      expect(matches(activeScope: 'scope-b'), isFalse);
      expect(matches(persistence: 'session_only'), isFalse);
      expect(matches(durableAccountRecord: false), isFalse);
      expect(matches(origin: Uri.parse('https://server-b.example')), isFalse);
    },
  );

  test('background call client never rotates or persists refresh tokens', () {
    final source = File(
      'lib/core/notifications/native_incoming_call_service.dart',
    ).readAsStringSync();
    final clientStart = source.indexOf(
      'final class _BackgroundCallActionClient',
    );
    final bindingStart = source.indexOf(
      'final class _BackgroundServerBinding',
      clientStart,
    );
    expect(clientStart, greaterThanOrEqualTo(0));
    expect(bindingStart, greaterThan(clientStart));
    final clientSource = source.substring(clientStart, bindingStart);

    expect(clientSource, isNot(contains('/api/v1/auth/refresh')));
    expect(clientSource, isNot(contains('SecureStoreKey.refreshToken')));
    expect(clientSource, isNot(contains('_storage.write(')));
    expect(
      clientSource,
      contains('if (!await _bindingIsStillCurrent(binding))'),
    );
  });

  test(
    'vendored channel exposes durable drain and explicit acknowledgement',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'getPendingCallActions') {
              return <Object?>[
                <String, Object?>{
                  'action_id': 'decline:call-123',
                  'event':
                      'com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE',
                },
              ];
            }
            return true;
          });

      final pending = await FlutterCallkitIncoming.getPendingCallActions();
      await FlutterCallkitIncoming.ackPendingCallAction('decline:call-123');

      expect(pending.single['action_id'], 'decline:call-123');
      expect(calls.map((call) => call.method), <String>[
        'getPendingCallActions',
        'ackPendingCallAction',
      ]);
      expect(calls.last.arguments, <String, Object?>{
        'action_id': 'decline:call-123',
      });
    },
  );
}

Map<String, String> _activeCallBinding(
  InstanceScope instanceScope, {
  required String workspaceId,
}) {
  return <String, String>{
    SecureStoreKey.instanceBaseUrl.value: instanceScope.origin.toString(),
    SecureStoreKey.instanceId.value: instanceScope.instanceId,
    SecureStoreKey.activeInstanceScopeId.value: instanceScope.storageId,
    SecureStoreKey.liveDiscoveryValidatedScopeId.value: instanceScope.storageId,
    SecureStoreKey.sessionInstanceScopeId.value: instanceScope.storageId,
    SecureStoreKey.activeWorkspaceId.value: workspaceId,
    SecureStoreKey.activeWorkspaceInstanceScopeId.value:
        instanceScope.storageId,
    SecureStoreKey.activeInstanceGeneration.value: 'generation-a',
  };
}
