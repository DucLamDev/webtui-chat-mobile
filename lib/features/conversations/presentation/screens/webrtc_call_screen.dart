import 'dart:async';

import 'package:flutter/material.dart';
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
    this.onLeave,
    super.key,
  });

  final String workspaceId;
  final String channelId;
  final String callId;
  final String title;
  final CallMode mode;
  final bool incoming;
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
  StreamSubscription<ConversationRealtimeEvent>? _signals;
  Timer? _stateTimer;
  String? _currentUserId;
  String? _error;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  CallStatus _status = CallStatus.ringing;
  bool _ready = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _offerSent = false;
  bool _hasRemoteDescription = false;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
    _stateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_syncCall()),
    );
  }

  @override
  void dispose() {
    _stateTimer?.cancel();
    unawaited(_signals?.cancel());
    unawaited(_peer?.close());
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    unawaited(_localRenderer.dispose());
    unawaited(_remoteRenderer.dispose());
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
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
          setState(() {
            _status = CallStatus.accepted;
            _startedAt ??= DateTime.now().toUtc();
          });
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          setState(() {
            _error =
                'Không thể thiết lập WebRTC. Hãy kiểm tra TURN và firewall của server.';
          });
        }
      };
      await Helper.setSpeakerphoneOn(true);
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
        await _sendSignal(CallSignalType.ready, const {});
      }
      await _syncCall();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<List<Map<String, Object?>>> _loadIceServers() async {
    try {
      final response = await ref
          .read(apiTransportProvider)
          .get<Object>('/api/v1/discovery');
      final discovery = envelopeItem(response.data, 'discovery');
      final runtime = jsonMap(field(discovery, const ['runtime']));
      final servers = jsonMapList(
        field(runtime, const ['rtc_ice_servers', 'rtcIceServers']),
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
        if (!widget.incoming) unawaited(_sendOffer());
      case ConversationRealtimeEventType.callOffer:
        if (widget.incoming && event.callSdp.isNotEmpty) {
          unawaited(_receiveOffer(event.callSdp));
        }
      case ConversationRealtimeEventType.callAnswer:
        if (!widget.incoming && event.callSdp.isNotEmpty) {
          unawaited(_receiveAnswer(event.callSdp));
        }
      case ConversationRealtimeEventType.callIceCandidate:
        if (event.callCandidate.isNotEmpty) {
          unawaited(_receiveCandidate(event.callCandidate));
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
    await widget.onLeave?.call();
    await _closeScreen();
  }

  Future<void> _finishLeave() async {
    if (_leaving) return;
    _leaving = true;
    _stateTimer?.cancel();
    final call =
        (await ref
                .read(getCallUseCaseProvider)
                .execute(
                  workspaceId: widget.workspaceId,
                  callId: widget.callId,
                ))
            .valueOrNull;
    if (call != null && !call.isTerminal) {
      await ref
          .read(endCallUseCaseProvider)
          .execute(
            workspaceId: widget.workspaceId,
            callId: widget.callId,
            currentStatus: call.status,
            reason: call.status == CallStatus.ringing
                ? (widget.incoming ? 'declined' : 'cancelled')
                : 'ended',
          );
    }
    await widget.onLeave?.call();
    await _closeScreen();
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
                      _status == CallStatus.accepted
                          ? _duration(_elapsed)
                          : 'Đang kết nối',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _control(
                      _microphoneEnabled ? Icons.mic : Icons.mic_off,
                      _microphoneEnabled ? 'Tắt mic' : 'Bật mic',
                      _toggleMicrophone,
                    ),
                    if (widget.mode == CallMode.video) ...[
                      const SizedBox(width: 16),
                      _control(
                        _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                        _cameraEnabled ? 'Tắt camera' : 'Bật camera',
                        _toggleCamera,
                      ),
                    ],
                    const SizedBox(width: 16),
                    _control(
                      Icons.call_end,
                      'Kết thúc',
                      () => unawaited(_finishLeave()),
                      destructive: true,
                    ),
                  ],
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
    return Stack(
      children: [
        Positioned.fill(
          child: RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
        Positioned(
          right: 16,
          top: 88,
          width: 112,
          height: 168,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: RTCVideoView(
              _localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
      ],
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
    bool destructive = false,
  }) {
    return IconButton.filled(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: destructive
            ? const Color(0xFFDC2626)
            : Colors.white.withValues(alpha: 0.16),
        foregroundColor: Colors.white,
        minimumSize: const Size.square(52),
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
