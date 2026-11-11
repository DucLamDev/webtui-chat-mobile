import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/meetings/application/meeting_room_controller.dart';
import 'package:webtui_chat/features/meetings/domain/meeting_models.dart';

MeetingJoinInfo _join({bool audio = true, bool video = true}) =>
    MeetingJoinInfo(
      provider: MeetingProviderKind.livekit,
      serverUrl: 'wss://live.example',
      room: 'r',
      token: 't',
      canPublishAudio: audio,
      canPublishVideo: video,
    );

void main() {
  test('vào phòng: kết nối, bật mic, camera theo yêu cầu', () async {
    final client = _FakeClient();
    final c = MeetingRoomController(
      client: client,
      join: _join(),
      startWithVideo: true,
    );
    await c.start();
    expect(c.state, MeetingConnectionState.connected);
    expect(c.micOn, isTrue);
    expect(c.cameraOn, isTrue);
    await c.toggleMic();
    expect(c.micOn, isFalse);
    await c.leave();
    expect(c.state, MeetingConnectionState.disconnected);
    expect(client.disconnects, 1);
  });

  test('không có quyền phát hình thì không bật camera', () async {
    final c = MeetingRoomController(
      client: _FakeClient(),
      join: _join(video: false),
      startWithVideo: true,
    );
    await c.start();
    expect(c.cameraOn, isFalse);
    expect(c.canToggleCamera, isFalse);
  });

  test('kết nối lỗi rồi thử lại lấy token mới', () async {
    final client = _FakeClient()..failConnect = true;
    var refreshed = 0;
    final c = MeetingRoomController(
      client: client,
      join: _join(),
      refreshJoin: () async {
        refreshed++;
        return _join();
      },
    );
    await c.start();
    expect(c.state, MeetingConnectionState.failed);
    expect(c.error, isNotNull);
    client.failConnect = false;
    await c.retry();
    expect(refreshed, 1);
    expect(c.state, MeetingConnectionState.connected);
  });

  test('mất kết nối và đang kết nối lại', () async {
    final client = _FakeClient();
    final c = MeetingRoomController(client: client, join: _join());
    await c.start();
    client.emit(MeetingRoomSignal.reconnecting);
    await Future<void>.delayed(Duration.zero);
    expect(c.state, MeetingConnectionState.reconnecting);
    client.emit(MeetingRoomSignal.disconnected);
    await Future<void>.delayed(Duration.zero);
    expect(c.state, MeetingConnectionState.disconnected);
    expect(c.error, 'Mất kết nối với cuộc họp.');
  });

  test('thiếu quyền micro chỉ báo nhẹ, không rớt phòng', () async {
    final client = _FakeClient()..denyMic = true;
    final c = MeetingRoomController(client: client, join: _join());
    await c.start();
    expect(c.state, MeetingConnectionState.connected);
    expect(c.micOn, isFalse);
    expect(c.mediaNotice, contains('micro'));
  });

  test('đóng màn khi connect chưa xong: rời phòng sau khi nối xong', () async {
    final client = _FakeClient()..connectGate = Completer<void>();
    final c = MeetingRoomController(client: client, join: _join());
    final started = c.start();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    client.connectGate!.complete();
    await started;
    expect(client.disconnects, 1);
    expect(c.micOn, isFalse);
  });
}

final class _FakeClient implements MeetingRoomClient {
  final _ctrl = StreamController<MeetingRoomSignal>.broadcast();
  bool failConnect = false;
  bool denyMic = false;
  int disconnects = 0;
  Completer<void>? connectGate;

  void emit(MeetingRoomSignal s) => _ctrl.add(s);

  @override
  Stream<MeetingRoomSignal> get signals => _ctrl.stream;
  @override
  List<MeetingParticipantView> get participants => const [];
  @override
  Future<void> connect({
    required String serverUrl,
    required String token,
  }) async {
    await connectGate?.future;
    if (failConnect) throw StateError('lỗi');
  }

  @override
  Future<void> setMicrophone(bool enabled) async {
    if (denyMic) throw const MeetingMediaPermissionException('microphone');
  }

  @override
  Future<void> setCamera(bool enabled) async {}
  @override
  Future<void> flipCamera() async {}
  @override
  Future<void> setSpeakerphone(bool enabled) async {}
  @override
  Future<void> disconnect() async => disconnects++;
  @override
  Future<void> dispose() async {}
  @override
  Widget? videoFor(String participantId) => null;
}
