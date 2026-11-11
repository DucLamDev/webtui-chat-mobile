import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/features/meetings/application/group_call_coordinator.dart';
import 'package:webtui_chat/features/meetings/data/meeting_remote_data_source.dart';
import 'package:webtui_chat/features/meetings/domain/meeting_models.dart';
import 'package:webtui_chat/features/meetings/presentation/group_call_button.dart';
import 'package:webtui_chat/features/notifications/domain/entities/mobile_notification.dart';

const _call = GroupCall(
  id: 'g1',
  workspaceId: 'w1',
  channelId: 'c1',
  meetingId: 'm1',
  kind: 'audio',
  status: GroupCallStatus.ringing,
  startedByName: 'An',
  channelName: 'Kinh doanh',
);

void main() {
  test('tiêu đề chuông: người gọi đang gọi nhóm kênh', () {
    expect(_call.ringTitle, 'An đang gọi nhóm Kinh doanh');
  });

  test('invite hiện chuông, ring_stopped / cancel tắt chuông', () async {
    final presenter = _Presenter();
    final coordinator = GroupCallCoordinator(api: _Api(), presenter: presenter);
    final shown = coordinator.handleStarted(_call);
    await Future<void>.delayed(Duration.zero);
    expect(presenter.shown, ['g1']);
    expect(coordinator.isRinging('g1'), isTrue);
    await coordinator.handleStopped('g1');
    expect(presenter.dismissed, ['g1']);
    presenter.finish(null);
    await shown;
    expect(coordinator.isRinging('g1'), isFalse);
  });

  test('chính người gọi không bị đổ chuông', () async {
    final presenter = _Presenter();
    final c = GroupCallCoordinator(
      api: _Api(),
      presenter: presenter,
      currentUserId: () => 'u1',
    );
    await c.handleStarted(
      const GroupCall(
        id: 'g2',
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
        kind: 'audio',
        status: GroupCallStatus.ringing,
        startedBy: 'u1',
      ),
    );
    expect(presenter.shown, isEmpty);
  });

  test('nhận gọi đúng API rồi vào họp', () async {
    final api = _Api();
    final presenter = _Presenter();
    final ok = await GroupCallCoordinator(
      api: api,
      presenter: presenter,
    ).accept(_call);
    expect(ok, isTrue);
    expect(api.log, ['accept w1/c1/g1']);
    expect(presenter.opened, ['g1']);
  });

  test(
    'nhận gọi gửi kèm mã máy push để máy chủ dừng chuông máy khác',
    () async {
      final api = _Api();
      await GroupCallCoordinator(
        api: api,
        presenter: _Presenter(),
        localDeviceId: () async => 'dev-1',
      ).accept(_call);
      expect(api.acceptedDeviceId, 'dev-1');
    },
  );

  test('không đọc được mã máy: vẫn nhận gọi, không gửi mã', () async {
    final api = _Api();
    final ok = await GroupCallCoordinator(
      api: api,
      presenter: _Presenter(),
      localDeviceId: () async => throw StateError('x'),
    ).accept(_call);
    expect(ok, isTrue);
    expect(api.acceptedDeviceId, isNull);
  });

  test('mở lại app: hiện lại cuộc gọi nhóm còn đổ chuông', () async {
    final api = _Api()
      ..ringing = [
        const GroupCall(
          id: 'g9',
          workspaceId: '',
          channelId: 'c1',
          meetingId: 'm1',
          kind: 'video',
          status: GroupCallStatus.ringing,
        ),
        GroupCall(
          id: 'old',
          workspaceId: 'w1',
          channelId: 'c1',
          meetingId: 'm1',
          kind: 'audio',
          status: GroupCallStatus.ringing,
          ringEndsAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ];
    final presenter = _Presenter();
    final coordinator = GroupCallCoordinator(api: api, presenter: presenter);
    await coordinator.restoreRinging('w1');
    await Future<void>.delayed(Duration.zero);
    expect(api.log, ['ringing w1']);
    expect(presenter.shown, ['g9']);
    // Gọi lại lần nữa khi đang chuông: không hiện trùng.
    await coordinator.restoreRinging('w1');
    await Future<void>.delayed(Duration.zero);
    expect(presenter.shown, ['g9']);
  });

  test('hỏi danh sách đang chuông lỗi mạng: im lặng', () async {
    final api = _Api()
      ..ringingError = const Failure(
        kind: FailureKind.network,
        message: 'mất mạng',
      );
    final presenter = _Presenter();
    await GroupCallCoordinator(
      api: api,
      presenter: presenter,
    ).restoreRinging('w1');
    expect(presenter.shown, isEmpty);
    expect(presenter.errors, isEmpty);
  });

  test('đã từ chối: push invite tới muộn không đổ chuông lại', () async {
    var now = DateTime(2026, 1, 1, 10);
    final presenter = _Presenter();
    final coordinator = GroupCallCoordinator(
      api: _Api(),
      presenter: presenter,
      now: () => now,
    );
    final first = coordinator.handleStarted(_call);
    await Future<void>.delayed(Duration.zero);
    presenter.finish(GroupCallChoice.decline);
    await first;
    expect(presenter.shown, ['g1']);
    await coordinator.handleStarted(_call);
    expect(presenter.shown, ['g1']);
    // Quá hạn nhớ thì cuộc gọi mới cùng mã mới được hiện lại.
    now = now.add(const Duration(minutes: 3));
    final again = coordinator.handleStarted(_call);
    await Future<void>.delayed(Duration.zero);
    expect(presenter.shown, ['g1', 'g1']);
    presenter.finish(null);
    await again;
  });

  test('đã hết giờ chuông theo máy chủ: không đổ chuông', () async {
    final presenter = _Presenter();
    await GroupCallCoordinator(api: _Api(), presenter: presenter).handleStarted(
      GroupCall(
        id: 'g3',
        workspaceId: 'w1',
        channelId: 'c1',
        meetingId: 'm1',
        kind: 'audio',
        status: GroupCallStatus.ringing,
        ringEndsAt: DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    expect(presenter.shown, isEmpty);
  });

  test('từ chối gọi đúng API', () async {
    final api = _Api();
    final ok = await GroupCallCoordinator(
      api: api,
      presenter: _Presenter(),
    ).decline(_call);
    expect(ok, isTrue);
    expect(api.log, ['decline w1/c1/g1']);
  });

  test('nhận khi cuộc gọi đã kết thúc (409): báo lỗi, coi như xong', () async {
    final api = _Api()
      ..acceptError = const Failure(
        kind: FailureKind.conflict,
        message: 'Cuộc gọi nhóm đã kết thúc.',
      );
    final presenter = _Presenter();
    final ok = await GroupCallCoordinator(
      api: api,
      presenter: presenter,
    ).accept(_call);
    expect(ok, isTrue);
    expect(presenter.errors, ['Cuộc gọi nhóm đã kết thúc.']);
    expect(presenter.opened, isEmpty);
  });

  test('push group_call_invite / cancel đọc thành NotificationTarget', () {
    final invite = NotificationTarget.fromPayload(
      workspaceId: 'w1',
      data: const {
        'event_type': 'group_call_invite',
        'group_call_id': 'g1',
        'channel_id': 'c1',
        'meeting_id': 'm1',
        'kind': 'video',
        'caller_name': 'An',
        'channel_name': 'Kinh doanh',
      },
    );
    expect(invite.isGroupCallInvite, isTrue);
    expect(invite.groupCallId, 'g1');
    expect(invite.callId, 'g1');
    expect(invite.callMode, 'video');
    final cancel = NotificationTarget.fromPayload(
      workspaceId: 'w1',
      data: const {'event_type': 'group_call_cancel', 'group_call_id': 'g1'},
    );
    expect(cancel.isGroupCallCancel, isTrue);
  });

  testWidgets('nút Gọi cả nhóm ẩn khi capability tắt, hiện khi bật', (
    tester,
  ) async {
    Future<void> pump(bool enabled) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeServerDiscoveryProvider.overrideWithValue(
              _discovery(groupCalls: enabled),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: GroupCallButton(onStart: (_) {})),
          ),
        ),
      );
    }

    await pump(false);
    expect(find.byKey(const Key('group-call-button')), findsNothing);
    await pump(true);
    expect(find.byKey(const Key('group-call-button')), findsOneWidget);
  });
}

SelfHostedServerDiscovery _discovery({required bool groupCalls}) {
  return SelfHostedServerDiscovery.fromApiResponse(
    payload: {
      'data': {
        'discovery': {
          'version': '1',
          'instance_id': '11111111-1111-4111-8111-111111111111',
          'domain': 'chat.company.example',
          'zone': {
            'name': 'Company Chat',
            'status': 'active',
            'registration_mode': 'open',
          },
          'runtime': {
            'app_name': 'Company Chat',
            'logo_url': '/branding/company-logo.png',
            'app_version': 'self-hosted',
            'server_version': 'self-hosted',
            'api_contract_version': 1,
            'minimum_supported_mobile_version': '1.1.0',
            'api_base_url': 'https://chat.company.example',
            'ws_base_url': 'wss://chat.company.example/ws',
          },
          'capabilities': {
            'self_hosted': true,
            'chat': true,
            'files': true,
            'calls': true,
            'bots': true,
            'automation': true,
            'moderation': true,
            'reporting': true,
            'blocking': true,
            'account_deletion': true,
            'legal_acceptance': true,
            'group_calls': groupCalls,
          },
          'deployment': {'status': 'ready'},
        },
      },
    },
    requestedServer: Uri.parse('https://chat.company.example'),
    mobileVersion: '1.2.0',
  );
}

final class _Presenter implements GroupCallPresenter {
  final shown = <String>[];
  final dismissed = <String>[];
  final opened = <String>[];
  final errors = <String>[];
  late void Function(GroupCallChoice?) finish;

  @override
  Future<GroupCallChoice?> showRinging(GroupCall call) {
    shown.add(call.id);
    final completer = Completer<GroupCallChoice?>();
    finish = completer.complete;
    return completer.future;
  }

  @override
  Future<void> dismissRinging(String id) async => dismissed.add(id);
  @override
  Future<void> openMeeting(GroupCall call, MeetingJoinInfo join) async =>
      opened.add(call.id);
  @override
  void showError(String message) => errors.add(message);
}

final class _Api implements MeetingApi {
  final log = <String>[];
  Failure? acceptError;
  String? acceptedDeviceId;
  List<GroupCall> ringing = const [];
  Failure? ringingError;

  @override
  Future<GroupCallAcceptance> acceptGroupCall({
    required String workspaceId,
    required String channelId,
    required String groupCallId,
    String? deviceId,
  }) async {
    log.add('accept $workspaceId/$channelId/$groupCallId');
    acceptedDeviceId = deviceId;
    if (acceptError != null) throw acceptError!;
    return const GroupCallAcceptance(
      call: null,
      join: MeetingJoinInfo(
        provider: MeetingProviderKind.livekit,
        serverUrl: 'wss://x',
        room: 'r',
        token: 't',
      ),
    );
  }

  @override
  Future<void> declineGroupCall({
    required String workspaceId,
    required String channelId,
    required String groupCallId,
  }) async => log.add('decline $workspaceId/$channelId/$groupCallId');

  @override
  Future<void> endGroupCall({
    required String workspaceId,
    required String channelId,
    required String groupCallId,
  }) async {}

  @override
  Future<MeetingJoinInfo> fetchJoinToken({
    required String workspaceId,
    required String channelId,
    required String meetingId,
  }) => throw UnimplementedError();

  @override
  Future<List<GroupCall>> fetchRingingGroupCalls({
    required String workspaceId,
  }) async {
    log.add('ringing $workspaceId');
    if (ringingError != null) throw ringingError!;
    return ringing;
  }

  @override
  Future<GroupCall> startGroupCall({
    required String workspaceId,
    required String channelId,
    required String meetingId,
    required String kind,
  }) => throw UnimplementedError();
}
