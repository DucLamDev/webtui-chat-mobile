import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/api_response.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/entities/conversation_realtime_event.dart';

class WebRtcCallScreen extends ConsumerStatefulWidget {
  const WebRtcCallScreen({
    required this.workspaceId,
    required this.channelId,
    required this.callId,
    required this.title,
    required this.mode,
    this.incoming = false,
    this.onConnected,
    this.onLeave,
    super.key,
  });

  final String workspaceId;
  final String channelId;
  final String callId;
  final String title;
  final CallMode mode;
  final bool incoming;
  final Future<void> Function()? onConnected;
  final Future<void> Function()? onLeave;

  @override
  ConsumerState<WebRtcCallScreen> createState() => _WebRtcCallScreenState();
}

class _WebRtcCallScreenState extends ConsumerState<WebRtcCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingCandidates = [];
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  MediaStream? _screenShareStream;
  StreamSubscription<ConversationRealtimeEvent>? _signals;
  Timer? _stateTimer;
  Timer? _disconnectTimer;
  String? _currentUserId;
  String? _error;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  CallStatus _status = CallStatus.ringing;
  bool _ready = false;
  bool _leaving = false;
  bool _leaveCallbackCalled = false;
  bool _fatalErrorHandled = false;
  bool _allowPop = false;
  bool _offerSent = false;
  bool _hasRemoteDescription = false;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _speakerEnabled = false;
  bool _usingFrontCamera = true;
  bool _reconnecting = false;
  bool _iceRestartAttempted = false;
  bool _sharingScreen = false;
  Offset? _localPreviewPosition;

  @override
  void initState() {
    super.initState();
    _speakerEnabled = widget.mode == CallMode.video;
    unawaited(_initialize());
    _stateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_syncCall()),
    );
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    unawaited(_signals?.cancel());
    unawaited(_peer?.close());
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    for (final track
        in _screenShareStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      unawaited(FlutterBackground.disableBackgroundExecution());
    }
    unawaited(_localRenderer.dispose());
    unawaited(_remoteRenderer.dispose());
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      final appSettings = await ref
          .read(loadAppSettingsUseCaseProvider)
          .execute();
      _microphoneEnabled = appSettings.microphoneEnabledOnJoin;
      _cameraEnabled =
          widget.mode == CallMode.video && appSettings.cameraEnabledOnJoin;
      _currentUserId = (await ref.read(loadProfileUseCaseProvider).execute())
          .valueOrNull
          ?.id;
      _signals = ref
          .read(conversationRealtimeRepositoryProvider)
          .subscribeToChannel(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          )
          .listen(_handleSignal);

      final peer = await createPeerConnection({
        'iceServers': await _loadIceServers(),
        'sdpSemantics': 'unified-plan',
      });
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.mode == CallMode.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });
      for (final track in stream.getAudioTracks()) {
        track.enabled = _microphoneEnabled;
      }
      for (final track in stream.getVideoTracks()) {
        track.enabled = _cameraEnabled;
      }
      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
      }
      peer.onTrack = (event) {
        if (event.streams.isNotEmpty && mounted) {
          setState(() => _remoteRenderer.srcObject = event.streams.first);
        }
      };
      peer.onIceCandidate = (candidate) {
        if (candidate.candidate?.isNotEmpty == true) {
          unawaited(
            _sendSignal(CallSignalType.iceCandidate, {
              'candidate': {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              },
            }),
          );
        }
      };
      peer.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _disconnectTimer?.cancel();
          setState(() {
            _status = CallStatus.accepted;
            _startedAt ??= DateTime.now().toUtc();
            _reconnecting = false;
            _iceRestartAttempted = false;
          });
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _scheduleConnectionRecovery();
        }
      };
      await Helper.setSpeakerphoneOn(_speakerEnabled);
      if (!mounted) {
        await peer.close();
        return;
      }
      setState(() {
        _peer = peer;
        _localStream = stream;
        _localRenderer.srcObject = stream;
        _ready = true;
      });
      if (widget.incoming) {
        await _acceptIncomingCall();
        await widget.onConnected?.call();
        await _sendSignal(CallSignalType.ready, const {});
      }
      await _syncCall();
    } on Object catch (error) {
      await _abortCall(error, reason: 'media_setup_failed');
    }
  }

  Future<void> _acceptIncomingCall() async {
    final current =
        (await ref
                .read(getCallUseCaseProvider)
                .execute(
                  workspaceId: widget.workspaceId,
                  callId: widget.callId,
                ))
            .valueOrNull;
    if (current == null || current.isTerminal) {
      throw StateError('Cuộc gọi không còn khả dụng.');
    }
    if (current.status == CallStatus.ringing) {
      final accepted = await ref
          .read(acceptCallUseCaseProvider)
          .execute(workspaceId: widget.workspaceId, callId: widget.callId);
      if (accepted.isFailure) {
        throw StateError(
          accepted.failureOrNull?.message ?? 'Không thể nhận cuộc gọi.',
        );
      }
    }
  }

  Future<List<Map<String, Object?>>> _loadIceServers() async {
    try {
      final response = await ref
          .read(apiTransportProvider)
          .get<Object>('/api/v1/calls/ice-servers');
      final data = jsonMap(envelopeData(response.data));
      final servers = jsonMapList(
        field(data, const ['ice_servers', 'iceServers']),
      );
      if (servers.isNotEmpty) {
        return servers
            .map<Map<String, Object?>>(Map<String, Object?>.from)
            .toList(growable: false);
      }
    } on Object {
      // Use the instance STUN endpoint as a conservative fallback.
    }
    return [
      {'urls': 'stun:${ref.read(activeServerUriProvider).host}:3478'},
    ];
  }

  void _handleSignal(ConversationRealtimeEvent event) {
    if (event.callId != widget.callId ||
        (_currentUserId != null && event.userId == _currentUserId)) {
      return;
    }
    switch (event.type) {
      case ConversationRealtimeEventType.callAccepted:
        break;
      case ConversationRealtimeEventType.callReady:
        if (!widget.incoming) _runSignaling(_sendOffer());
      case ConversationRealtimeEventType.callOffer:
        if (widget.incoming && event.callSdp.isNotEmpty) {
          _runSignaling(_receiveOffer(event.callSdp));
        }
      case ConversationRealtimeEventType.callAnswer:
        if (!widget.incoming && event.callSdp.isNotEmpty) {
          _runSignaling(_receiveAnswer(event.callSdp));
        }
      case ConversationRealtimeEventType.callIceCandidate:
        if (event.callCandidate.isNotEmpty) {
          _runSignaling(_receiveCandidate(event.callCandidate));
        }
      case ConversationRealtimeEventType.callRejected:
      case ConversationRealtimeEventType.callCancelled:
      case ConversationRealtimeEventType.callEnded:
      case ConversationRealtimeEventType.callMissed:
        unawaited(_leaveFromRemote());
      default:
        break;
    }
  }

  void _runSignaling(Future<void> operation) {
    unawaited(
      operation.catchError((Object error) async {
        await _abortCall(error, reason: 'signaling_failed');
      }),
    );
  }

  Future<void> _sendOffer() async {
    final peer = _peer;
    if (peer == null || _offerSent) return;
    _offerSent = true;
    try {
      final offer = await peer.createOffer();
      await peer.setLocalDescription(offer);
      await _sendSignal(CallSignalType.offer, {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } on Object {
      _offerSent = false;
      rethrow;
    }
  }

  Future<void> _receiveOffer(Map<String, dynamic> value) async {
    final peer = _peer;
    if (peer == null) return;
    await peer.setRemoteDescription(
      RTCSessionDescription(
        value['sdp']?.toString(),
        value['type']?.toString(),
      ),
    );
    _hasRemoteDescription = true;
    await _flushCandidates();
    final answer = await peer.createAnswer();
    await peer.setLocalDescription(answer);
    await _sendSignal(CallSignalType.answer, {
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });
  }

  Future<void> _receiveAnswer(Map<String, dynamic> value) async {
    final peer = _peer;
    if (peer == null) return;
    await peer.setRemoteDescription(
      RTCSessionDescription(
        value['sdp']?.toString(),
        value['type']?.toString(),
      ),
    );
    _hasRemoteDescription = true;
    await _flushCandidates();
  }

  Future<void> _receiveCandidate(Map<String, dynamic> value) async {
    final candidate = RTCIceCandidate(
      value['candidate']?.toString(),
      value['sdpMid']?.toString(),
      _asInt(value['sdpMLineIndex']),
    );
    if (!_hasRemoteDescription || _peer == null) {
      _pendingCandidates.add(candidate);
      return;
    }
    await _peer!.addCandidate(candidate);
  }

  Future<void> _flushCandidates() async {
    final peer = _peer;
    if (peer == null) return;
    final candidates = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final candidate in candidates) {
      await peer.addCandidate(candidate);
    }
  }

  Future<void> _sendSignal(
    CallSignalType type,
    Map<String, Object?> payload,
  ) async {
    final result = await ref
        .read(sendCallSignalUseCaseProvider)
        .execute(
          workspaceId: widget.workspaceId,
          callId: widget.callId,
          signalType: type,
          payload: {...payload, 'mode': widget.mode.name},
        );
    if (result.isFailure) {
      throw StateError(
        'Không thể gửi tín hiệu WebRTC: ${result.failureOrNull?.message}',
      );
    }
  }

  Future<void> _syncCall() async {
    if (_leaving) return;
    final call =
        (await ref
                .read(getCallUseCaseProvider)
                .execute(
                  workspaceId: widget.workspaceId,
                  callId: widget.callId,
                ))
            .valueOrNull;
    if (!mounted || call == null || _leaving) return;
    if (call.isTerminal) {
      await _leaveFromRemote();
      return;
    }
    final startedAt = call.status == CallStatus.accepted
        ? call.startedAt ?? _startedAt ?? DateTime.now().toUtc()
        : null;
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().toUtc().difference(startedAt);
    setState(() {
      _status = call.status;
      _startedAt = startedAt;
      _elapsed = elapsed.isNegative ? Duration.zero : elapsed;
    });
  }

  Future<void> _leaveFromRemote() async {
    if (_leaving) return;
    _leaving = true;
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    await _notifyLeave();
    await _closeScreen();
  }

  Future<void> _finishLeave() async {
    if (_leaving) return;
    _leaving = true;
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    await _terminateServerCall(reason: 'user_ended');
    await _notifyLeave();
    await _closeScreen();
  }

  Future<void> _terminateServerCall({required String reason}) async {
    final call =
        (await ref
                .read(getCallUseCaseProvider)
                .execute(
                  workspaceId: widget.workspaceId,
                  callId: widget.callId,
                ))
            .valueOrNull;
    if (call != null && !call.isTerminal) {
      if (call.status == CallStatus.ringing && widget.incoming) {
        await ref
            .read(rejectCallUseCaseProvider)
            .execute(
              workspaceId: widget.workspaceId,
              callId: widget.callId,
              reason: reason,
            );
      } else {
        await ref
            .read(endCallUseCaseProvider)
            .execute(
              workspaceId: widget.workspaceId,
              callId: widget.callId,
              currentStatus: call.status,
              reason: reason,
            );
      }
    }
  }

  Future<void> _abortCall(Object error, {required String reason}) async {
    if (_fatalErrorHandled || _leaving) return;
    _fatalErrorHandled = true;
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    if (mounted) {
      setState(() => _error = _friendlyError(error));
    }
    await _terminateServerCall(reason: reason);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await _leaveFromRemote();
  }

  Future<void> _notifyLeave() async {
    if (_leaveCallbackCalled) return;
    _leaveCallbackCalled = true;
    await widget.onLeave?.call();
  }

  Future<void> _closeScreen() async {
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  void _toggleMicrophone() {
    final tracks = _localStream?.getAudioTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    setState(() {
      _microphoneEnabled = !_microphoneEnabled;
      for (final track in tracks) {
        track.enabled = _microphoneEnabled;
      }
    });
  }

  void _toggleCamera() {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    setState(() {
      _cameraEnabled = !_cameraEnabled;
      for (final track in tracks) {
        track.enabled = _cameraEnabled;
      }
    });
  }

  Future<void> _toggleSpeaker() async {
    final enabled = !_speakerEnabled;
    await Helper.setSpeakerphoneOn(enabled);
    if (mounted) {
      setState(() => _speakerEnabled = enabled);
    }
  }

  Future<void> _switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
    if (mounted) {
      setState(() => _usingFrontCamera = !_usingFrontCamera);
    }
  }

  Future<void> _toggleScreenShare() async {
    if (_sharingScreen) {
      await _stopScreenShare();
      return;
    }
    final peer = _peer;
    if (peer == null || widget.mode != CallMode.video) return;
    try {
      if (Platform.isAndroid) {
        const backgroundConfig = FlutterBackgroundAndroidConfig(
          notificationTitle: 'Đang chia sẻ màn hình',
          notificationText:
              'WebTui Chat đang chia sẻ màn hình trong cuộc gọi video.',
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
          showBadge: false,
          shouldRequestBatteryOptimizationsOff: false,
        );
        final initialized = await FlutterBackground.initialize(
          androidConfig: backgroundConfig,
        );
        if (!initialized) {
          throw StateError(
            'Không thể bật foreground service chia sẻ màn hình.',
          );
        }
        if (!FlutterBackground.isBackgroundExecutionEnabled) {
          final enabled = await FlutterBackground.enableBackgroundExecution();
          if (!enabled) {
            throw StateError(
              'Không thể giữ phiên chia sẻ màn hình ở foreground.',
            );
          }
        }
      }
      final screenStream = await navigator.mediaDevices.getDisplayMedia({
        'audio': false,
        'video': true,
      });
      final screenTracks = screenStream.getVideoTracks();
      if (screenTracks.isEmpty) {
        throw StateError('Thiết bị không trả về luồng chia sẻ màn hình.');
      }
      RTCRtpSender? videoSender;
      for (final sender in await peer.getSenders()) {
        if (sender.track?.kind == 'video') {
          videoSender = sender;
          break;
        }
      }
      if (videoSender == null) {
        for (final track in screenStream.getTracks()) {
          track.stop();
        }
        throw StateError('Cuộc gọi chưa có kênh video để chia sẻ màn hình.');
      }
      final screenTrack = screenTracks.first;
      await videoSender.replaceTrack(screenTrack);
      screenTrack.onEnded = () {
        if (mounted && _sharingScreen) {
          unawaited(_stopScreenShare());
        }
      };
      if (!mounted) {
        for (final track in screenStream.getTracks()) {
          track.stop();
        }
        return;
      }
      setState(() {
        _screenShareStream = screenStream;
        _localRenderer.srcObject = screenStream;
        _sharingScreen = true;
      });
    } on Object catch (error) {
      if (Platform.isAndroid &&
          FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyScreenShareError(error))),
        );
      }
    }
  }

  Future<void> _stopScreenShare() async {
    final peer = _peer;
    final cameraTrack = _localStream?.getVideoTracks().firstOrNull;
    if (peer != null && cameraTrack != null) {
      for (final sender in await peer.getSenders()) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(cameraTrack);
          break;
        }
      }
    }
    for (final track
        in _screenShareStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }
    if (mounted) {
      setState(() {
        _screenShareStream = null;
        _localRenderer.srcObject = _localStream;
        _sharingScreen = false;
      });
    }
  }

  void _scheduleConnectionRecovery() {
    if (_leaving || _fatalErrorHandled) return;
    _disconnectTimer?.cancel();
    if (mounted) {
      setState(() => _reconnecting = true);
    }
    _disconnectTimer = Timer(Duration(seconds: widget.incoming ? 15 : 3), () {
      if (_leaving || _fatalErrorHandled) return;
      if (widget.incoming) {
        unawaited(
          _abortCall(
            StateError('Kết nối cuộc gọi đã bị gián đoạn.'),
            reason: 'webrtc_disconnected',
          ),
        );
        return;
      }
      unawaited(_restartIce());
    });
  }

  Future<void> _restartIce() async {
    final peer = _peer;
    if (peer == null || _iceRestartAttempted || _leaving) return;
    _iceRestartAttempted = true;
    try {
      final offer = await peer.createOffer({'iceRestart': true});
      await peer.setLocalDescription(offer);
      await _sendSignal(CallSignalType.offer, {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
      _disconnectTimer?.cancel();
      _disconnectTimer = Timer(const Duration(seconds: 12), () {
        if (_reconnecting && !_leaving) {
          unawaited(
            _abortCall(
              StateError(
                'Không thể khôi phục đường truyền WebRTC. Hãy kiểm tra TURN và firewall của server.',
              ),
              reason: 'webrtc_disconnected',
            ),
          );
        }
      });
    } on Object catch (error) {
      await _abortCall(error, reason: 'webrtc_recovery_failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_finishLeave());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07111F),
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: _media()),
              Positioned(
                left: 20,
                right: 20,
                top: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WebTuiSpacing.md,
                    vertical: WebTuiSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF07111F).withValues(alpha: 0.62),
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _reconnecting
                            ? 'Đang khôi phục kết nối…'
                            : _status == CallStatus.accepted
                            ? _duration(_elapsed)
                            : 'Đang kết nối',
                        style: TextStyle(
                          color: _reconnecting
                              ? const Color(0xFFFBBF24)
                              : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_status == CallStatus.accepted &&
                  _elapsed >= const Duration(hours: 1))
                Positioned(
                  left: 28,
                  right: 28,
                  top: 102,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WebTuiSpacing.md,
                        vertical: WebTuiSpacing.sm,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                          const SizedBox(width: WebTuiSpacing.sm),
                          Text(
                            'Cuộc họp đã kéo dài ${_elapsed.inMinutes} phút',
                            style: WebTuiTypography.bodySmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WebTuiSpacing.md,
                    vertical: WebTuiSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF07111F).withValues(alpha: 0.78),
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 28,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _control(
                        _microphoneEnabled ? Icons.mic : Icons.mic_off,
                        _microphoneEnabled ? 'Mic' : 'Bật mic',
                        _toggleMicrophone,
                        active: !_microphoneEnabled,
                      ),
                      _control(
                        _speakerEnabled
                            ? Icons.volume_up
                            : Icons.hearing_outlined,
                        _speakerEnabled ? 'Loa ngoài' : 'Tai nghe',
                        () => unawaited(_toggleSpeaker()),
                        active: _speakerEnabled,
                      ),
                      if (widget.mode == CallMode.video) ...[
                        _control(
                          _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                          _cameraEnabled ? 'Camera' : 'Bật cam',
                          _toggleCamera,
                          active: !_cameraEnabled,
                        ),
                        if (!_sharingScreen)
                          _control(
                            Icons.cameraswitch_outlined,
                            'Đổi cam',
                            () => unawaited(_switchCamera()),
                          ),
                        _control(
                          _sharingScreen
                              ? Icons.stop_screen_share_outlined
                              : Icons.screen_share_outlined,
                          _sharingScreen ? 'Dừng share' : 'Chia sẻ',
                          () => unawaited(_toggleScreenShare()),
                          active: _sharingScreen,
                        ),
                      ],
                      _control(
                        Icons.call_end,
                        'Kết thúc',
                        () => unawaited(_finishLeave()),
                        destructive: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _media() {
    if (_error != null) {
      return _state(Icons.videocam_off_outlined, 'Không thể kết nối', _error!);
    }
    if (!_ready) {
      return _state(
        Icons.sync,
        'Đang chuẩn bị cuộc gọi',
        'Đang kết nối media...',
        loading: true,
      );
    }
    if (widget.mode == CallMode.audio) {
      return _state(
        Icons.person,
        widget.title,
        _status == CallStatus.accepted ? 'Đã kết nối' : 'Đang đổ chuông...',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const previewWidth = 112.0;
        const previewHeight = 168.0;
        final defaultPosition = Offset(
          (constraints.maxWidth - previewWidth - 16).clamp(
            8,
            constraints.maxWidth,
          ),
          88,
        );
        final previewPosition = _localPreviewPosition ?? defaultPosition;
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                panEnabled: true,
                scaleEnabled: true,
                clipBehavior: Clip.hardEdge,
                child: SizedBox.expand(
                  child: RTCVideoView(
                    _remoteRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  ),
                ),
              ),
            ),
            Positioned(
              left: previewPosition.dx,
              top: previewPosition.dy,
              width: previewWidth,
              height: previewHeight,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    final current = _localPreviewPosition ?? defaultPosition;
                    _localPreviewPosition = Offset(
                      (current.dx + details.delta.dx).clamp(
                        8,
                        constraints.maxWidth - previewWidth - 8,
                      ),
                      (current.dy + details.delta.dy).clamp(
                        72,
                        constraints.maxHeight - previewHeight - 96,
                      ),
                    );
                  });
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 18,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: !_sharingScreen && _usingFrontCamera,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _state(
    IconData icon,
    String title,
    String message, {
    bool loading = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator(color: Colors.white)
            else
              Icon(icon, color: Colors.white, size: 48),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: WebTuiTypography.titleLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _control(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool active = false,
    bool destructive = false,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filled(
            onPressed: onPressed,
            tooltip: label,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              backgroundColor: destructive
                  ? const Color(0xFFDC2626)
                  : active
                  ? const Color(0xFF3153D8)
                  : Colors.white.withValues(alpha: 0.14),
              foregroundColor: Colors.white,
              side: BorderSide(
                color: destructive || active
                    ? Colors.transparent
                    : Colors.white24,
              ),
              minimumSize: const Size.square(52),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _duration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return value.inHours > 0
      ? '${value.inHours.toString().padLeft(2, '0')}:$minutes:$seconds'
      : '$minutes:$seconds';
}

String _friendlyError(Object error) {
  final message = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  if (message.contains('NotAllowed') || message.contains('Permission')) {
    return 'Cần cấp quyền camera và microphone để thực hiện cuộc gọi.';
  }
  return message.trim().isEmpty ? 'Không thể bắt đầu cuộc gọi.' : message;
}

String _friendlyScreenShareError(Object error) {
  final message = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  if (message.contains('NotAllowed') ||
      message.contains('Permission') ||
      message.contains('permission')) {
    return 'Bạn chưa cấp quyền ghi/chia sẻ màn hình.';
  }
  if (Platform.isIOS) {
    return 'Chia sẻ màn hình trên iOS cần Broadcast Upload Extension khi build bản phân phối.';
  }
  return message.trim().isEmpty
      ? 'Thiết bị hiện không hỗ trợ chia sẻ màn hình.'
      : message;
}
