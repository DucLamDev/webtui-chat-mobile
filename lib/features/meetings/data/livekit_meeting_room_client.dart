import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../application/meeting_room_controller.dart';

/// Cài đặt [MeetingRoomClient] bằng SDK LiveKit.
final class LiveKitMeetingRoomClient implements MeetingRoomClient {
  LiveKitMeetingRoomClient() {
    _room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: lk.AudioPublishOptions(dtx: true),
      ),
    );
    _listener = _room.createListener()
      ..on<lk.RoomReconnectingEvent>(
        (_) => _signals.add(MeetingRoomSignal.reconnecting),
      )
      ..on<lk.RoomReconnectedEvent>(
        (_) => _signals.add(MeetingRoomSignal.reconnected),
      )
      ..on<lk.RoomDisconnectedEvent>(
        (_) => _signals.add(MeetingRoomSignal.disconnected),
      );
    _room.addListener(_onRoomChanged);
  }

  late final lk.Room _room;
  late final lk.EventsListener<lk.RoomEvent> _listener;
  final _signals = StreamController<MeetingRoomSignal>.broadcast();
  lk.CameraPosition _cameraPosition = lk.CameraPosition.front;
  bool _disposed = false;

  @override
  Stream<MeetingRoomSignal> get signals => _signals.stream;

  @override
  List<MeetingParticipantView> get participants {
    final local = _room.localParticipant;
    return [
      ?(local == null ? null : _view(local, isLocal: true)),
      for (final remote in _room.remoteParticipants.values) _view(remote),
    ];
  }

  MeetingParticipantView _view(
    lk.Participant participant, {
    bool isLocal = false,
  }) {
    final name = participant.name.trim().isEmpty
        ? participant.identity
        : participant.name;
    return MeetingParticipantView(
      id: participant.identity,
      name: name,
      isLocal: isLocal,
      micOn: !participant.isMuted && participant.hasAudio,
      cameraOn: _cameraTrack(participant) != null,
      speaking: participant.isSpeaking,
    );
  }

  lk.VideoTrack? _cameraTrack(lk.Participant participant) {
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (!publication.muted && !publication.isScreenShare && track != null) {
        return track as lk.VideoTrack;
      }
    }
    return null;
  }

  lk.Participant? _find(String id) {
    final local = _room.localParticipant;
    if (local != null && local.identity == id) return local;
    return _room.remoteParticipants[id];
  }

  @override
  Widget? videoFor(String participantId) {
    final participant = _find(participantId);
    final track = participant == null ? null : _cameraTrack(participant);
    if (track == null) return null;
    return lk.VideoTrackRenderer(
      track,
      fit: lk.VideoViewFit.cover,
      mirrorMode: participant is lk.LocalParticipant
          ? lk.VideoViewMirrorMode.auto
          : lk.VideoViewMirrorMode.off,
    );
  }

  @override
  Future<void> connect({required String serverUrl, required String token}) =>
      _room.connect(serverUrl, token);

  @override
  Future<void> setMicrophone(bool enabled) => _publish(
    () => _room.localParticipant?.setMicrophoneEnabled(enabled),
    'microphone',
  );

  @override
  Future<void> setCamera(bool enabled) => _publish(
    () => _room.localParticipant?.setCameraEnabled(
      enabled,
      cameraCaptureOptions: lk.CameraCaptureOptions(
        cameraPosition: _cameraPosition,
      ),
    ),
    'camera',
  );

  Future<void> _publish(
    Future<Object?>? Function() action,
    String device,
  ) async {
    try {
      await action();
    } on Object catch (error) {
      final text = error.toString().toLowerCase();
      if (text.contains('permission') || text.contains('notallowed')) {
        throw MeetingMediaPermissionException(device);
      }
      rethrow;
    }
  }

  @override
  Future<void> flipCamera() async {
    final next = _cameraPosition == lk.CameraPosition.front
        ? lk.CameraPosition.back
        : lk.CameraPosition.front;
    for (final publication
        in _room.localParticipant?.videoTrackPublications ?? const []) {
      final track = publication.track;
      if (track is lk.LocalVideoTrack && !publication.isScreenShare) {
        await track.setCameraPosition(next);
        _cameraPosition = next;
        return;
      }
    }
  }

  @override
  Future<void> setSpeakerphone(bool enabled) =>
      lk.AudioManager.instance.setSpeakerOutputPreferred(enabled);

  @override
  Future<void> disconnect() => _room.disconnect();

  void _onRoomChanged() {
    if (!_disposed) _signals.add(MeetingRoomSignal.participantsChanged);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _room.removeListener(_onRoomChanged);
    await _listener.dispose();
    await _room.dispose();
    await _signals.close();
  }
}
