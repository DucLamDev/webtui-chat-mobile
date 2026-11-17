import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/api_response.dart';
import '../../../../core/notifications/call_tone_player.dart';
import '../../../../core/notifications/native_incoming_call_service.dart';
import '../../../../core/security/active_call_tracker.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../auth/presentation/controllers/legal_acceptance_controller.dart';
import '../../application/call_end_cue.dart';
import '../../application/use_cases/call_use_cases.dart';
import '../../domain/entities/call_busy_policy.dart';
import '../../domain/entities/call_device_routing.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/entities/call_video_upgrade_policy.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import '../../domain/entities/incoming_call_policy.dart';

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
  // Chuông chờ phía người gọi, dừng khi bên kia nhận máy hoặc cuộc gọi kết thúc.
  final CallTonePlayer _ringback = CallTonePlayer.ringback();
  Map<String, dynamic>? _pendingOffer;
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  StreamSubscription<ConversationRealtimeEvent>? _signals;
  Timer? _stateTimer;
  Timer? _disconnectTimer;
  Timer? _connectTimer;
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
  bool _remoteReadyReceived = false;
  bool _hasRemoteDescription = false;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _speakerEnabled = false;
  bool _usingFrontCamera = true;
  bool _reconnecting = false;
  bool _connected = false;
  bool _iceRestartAttempted = false;

  /// Luồng camera bật giữa cuộc gọi thoại (nút "Video") và sender của nó.
  MediaStream? _upgradeVideoStream;
  RTCRtpSender? _upgradeVideoSender;

  /// Máy này đang gửi video (cuộc gọi video từ đầu hoặc đã bật nút "Video").
  late bool _hasLocalVideo;

  /// Đã nhận video từ bên kia.
  bool _hasRemoteVideo = false;
  bool _startingLocalVideo = false;

  /// Thương lượng lại SDP: đang chạy / còn chờ chạy khi signaling `stable`.
  bool _renegotiating = false;
  bool _renegotiationQueued = false;

  /// Người nhận đã xin offer mới vì bật camera: chờ offer tối đa 8 giây.
  DateTime? _videoOfferRequestedAt;
  DateTime? _lastOfferAt;
  Timer? _videoOfferTimer;

  /// Thông báo ngắn trên màn gọi (vd. máy kia chưa hỗ trợ video giữa cuộc).
  String? _notice;
  Timer? _noticeTimer;

  /// Câu hiện trước khi màn tự đóng (vd. người nhận đang bận).
  String? _closingMessage;

  bool get _videoActive => callUsesVideoLayout(
    startedAsVideo: widget.mode == CallMode.video,
    hasLocalVideo: _hasLocalVideo,
    hasRemoteVideo: _hasRemoteVideo,
  );

  bool get _canStartLocalVideo => canStartLocalVideo(
    connected: _connected && _status == CallStatus.accepted,
    hasLocalVideo: _hasLocalVideo,
    upgrading: _startingLocalVideo,
    leaving: _leaving || _fatalErrorHandled,
  );

  List<MediaStreamTrack> get _localVideoTracks => [
    ...?_localStream?.getVideoTracks(),
    ...?_upgradeVideoStream?.getVideoTracks(),
  ];

  /// Máy này đã nhận cuộc gọi đến (accept thành công): chỉ khi đó mới trả lời
  /// offer.
  bool _acceptedHere = false;

  /// Mã thiết bị đã đăng ký push, để bỏ tín hiệu WebRTC gửi cho máy khác.
  String? _localDeviceId;
  Offset? _localPreviewPosition;
  late final InstanceScope _instanceScope;
  // Lõi 3.1: báo khoá ứng dụng không khoá khi màn gọi đang mở.
  late final ActiveCallTracker _activeCalls;

  @override
  void initState() {
    super.initState();
    _instanceScope = ref.read(activeInstanceScopeProvider);
    _activeCalls = ref.read(activeCallTrackerProvider.notifier)
      ..begin(widget.callId);
    if (!widget.incoming) {
      // Màn gọi đi đang mở: máy này không bao giờ hiện "Cuộc gọi đến" cho
      // chính cuộc này (máy chủ phát `CallInvited` cả tới người gọi).
      ref.read(outgoingCallRegistryProvider).rememberCall(widget.callId);
    }
    _speakerEnabled = widget.mode == CallMode.video;
    _hasLocalVideo = widget.mode == CallMode.video;
    unawaited(_initialize());
    _stateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_syncCall()),
    );
  }

  @override
  void dispose() {
    _activeCalls.end(widget.callId);
    unawaited(_ringback.stop());
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    _connectTimer?.cancel();
    _videoOfferTimer?.cancel();
    _noticeTimer?.cancel();
    unawaited(_signals?.cancel());
    unawaited(_peer?.close());
    for (final track in [
      ...?_localStream?.getTracks(),
      ...?_upgradeVideoStream?.getTracks(),
    ]) {
      track.stop();
    }
    unawaited(NativeIncomingCallService.endCall(widget.callId));
    unawaited(_localRenderer.dispose());
    unawaited(_remoteRenderer.dispose());
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      if (!ref.read(legalAcceptanceControllerProvider).canCreateUserContent) {
        throw StateError(
          tr(
            'Cần đồng ý Điều khoản và Chính sách quyền riêng tư trước khi bắt đầu hoặc nhận cuộc gọi.',
            'You need to accept the Terms and Privacy Policy before starting or answering a call.',
          ),
        );
      }
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
      _localDeviceId = await ref
          .read(resolveCallDeviceIdUseCaseProvider)
          .execute();
      _signals = ref
          .read(conversationRealtimeRepositoryProvider)
          .subscribeToChannel(
            workspaceId: widget.workspaceId,
            channelId: widget.channelId,
          )
          .listen(_handleSignal);
      if (widget.incoming) {
        if (!await _acceptIncomingCall()) {
          // Đã nhận ở máy khác (hoặc vừa kết thúc): báo rõ rồi đóng màn gọi
          // đến, không gác máy hộ máy kia.
          await _leaveWithMessage(callGoneMessage);
          return;
        }
        _acceptedHere = true;
        _startConnectTimer();
      }

      final peer = await createPeerConnection({
        'iceServers': await _loadIceServers(),
        'sdpSemantics': 'unified-plan',
      });
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': const {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': widget.mode == CallMode.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });
      // getUserMedia is the visible, contextual runtime permission boundary.
      // Keep the stream reachable so any native lifecycle failure below is
      // cleaned up when the screen closes.
      _localStream = stream;
      final audioTracks = stream.getAudioTracks();
      if (audioTracks.isEmpty) {
        throw StateError('Không tìm thấy luồng microphone trên thiết bị.');
      }
      if (!widget.incoming) {
        await NativeIncomingCallService.startOutgoingCall(
          instanceScope: _instanceScope,
          callId: widget.callId,
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
          title: widget.title,
          isVideo: widget.mode == CallMode.video,
        );
      }
      for (final track in audioTracks) {
        track.enabled = _microphoneEnabled;
      }
      for (final track in stream.getVideoTracks()) {
        track.enabled = _cameraEnabled;
      }
      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
      }
      peer.onTrack = (event) {
        if (event.streams.isEmpty || !mounted) return;
        if (event.track.kind == 'video') {
          unawaited(_showRemoteVideo(event.streams.first, event.track));
          return;
        }
        setState(() => _remoteRenderer.srcObject = event.streams.first);
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
          unawaited(_ringback.stop());
          _disconnectTimer?.cancel();
          _connectTimer?.cancel();
          _connected = true;
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
      _maybeSendOffer();
      _maybeReceivePendingOffer();
      if (!widget.incoming && _status == CallStatus.ringing) {
        unawaited(_ringback.start());
      }
      if (widget.incoming) {
        await NativeIncomingCallService.activateMediaCapture(
          instanceScope: _instanceScope,
          callId: widget.callId,
          workspaceId: widget.workspaceId,
          channelId: widget.channelId,
          title: widget.title,
          isVideo: widget.mode == CallMode.video,
        );
        await widget.onConnected?.call();
        await _sendSignal(CallSignalType.ready, const {});
      }
      await _syncCall();
    } on Object catch (error) {
      if (widget.incoming && !_acceptedHere) {
        // Lỗi trước khi nhận được cuộc gọi (mạng, máy chủ): báo rõ rồi đóng,
        // không gửi từ chối thay người được gọi.
        await _leaveWithMessage(_friendlyError(error));
        return;
      }
      await _abortCall(error, reason: 'media_setup_failed');
    }
  }

  /// `true`: máy này đã nhận cuộc gọi. `false`: cuộc gọi đã được nhận ở máy
  /// khác (máy chủ trả 409 `CALL_INVALID_TRANSITION` hoặc mã máy đã nhận khác
  /// máy này).
  Future<bool> _acceptIncomingCall() async {
    final current =
        (await ref
                .read(getCallUseCaseProvider)
                .execute(
                  workspaceId: widget.workspaceId,
                  callId: widget.callId,
                ))
            .valueOrNull;
    if (current == null || current.isTerminal) {
      throw StateError(
        tr('Cuộc gọi không còn khả dụng.', 'This call is no longer available.'),
      );
    }
    if (current.status == CallStatus.ringing) {
      final accepted = await ref
          .read(acceptCallUseCaseProvider)
          .execute(workspaceId: widget.workspaceId, callId: widget.callId);
      if (accepted.isFailure) {
        if (isCallAlreadyHandledFailure(accepted.failureOrNull)) {
          return false;
        }
        throw StateError(
          accepted.failureOrNull?.message ??
              tr('Không thể nhận cuộc gọi.', 'Couldn\'t answer the call.'),
        );
      }
      return !callAnsweredOnAnotherDevice(
        answeredDeviceId: accepted.valueOrNull?.answeredDeviceId,
        localDeviceId: _localDeviceId,
      );
    }
    // Đã nhận từ trước: chỉ tiếp tục khi chính máy này đã nhận (máy chủ cũ
    // không trả mã máy thì giữ hành vi cũ).
    return !callAnsweredOnAnotherDevice(
      answeredDeviceId: current.answeredDeviceId,
      localDeviceId: _localDeviceId,
    );
  }

  bool _answeredOnAnotherDevice(CallSession call) {
    return widget.incoming &&
        call.status == CallStatus.accepted &&
        callAnsweredOnAnotherDevice(
          answeredDeviceId: call.answeredDeviceId,
          localDeviceId: _localDeviceId,
        );
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
    } on Object catch (error) {
      // Use the instance STUN endpoint as a conservative fallback; ghi log vì
      // thiếu TURN thường làm cuộc gọi kết nối nhưng không có tiếng qua NAT / 4G.
      debugPrint('Không lấy được ICE servers, chỉ dùng STUN: $error');
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
    if (isCallSignalForAnotherDevice(event, localDeviceId: _localDeviceId)) {
      // Tín hiệu dành cho máy khác của cùng người dùng: không trả lời offer,
      // không thêm ICE.
      return;
    }
    switch (event.type) {
      case ConversationRealtimeEventType.callAccepted:
        unawaited(_ringback.stop());
      case ConversationRealtimeEventType.callReady:
        if (!widget.incoming) {
          _remoteReadyReceived = true;
          _maybeSendOffer();
        }
      case ConversationRealtimeEventType.callOffer:
        if (widget.incoming && event.callSdp.isNotEmpty) {
          // Có offer mới: máy kia hỗ trợ thương lượng lại, bỏ hẹn giờ 8 giây.
          _lastOfferAt = DateTime.now();
          _videoOfferTimer?.cancel();
          if (!_acceptedHere) {
            // Chưa nhận xong trên máy này: giữ offer, chỉ trả lời sau khi
            // accept thành công.
            _pendingOffer = Map<String, dynamic>.from(event.callSdp);
            return;
          }
          _runSignaling(_receiveOffer(event.callSdp));
        }
      case ConversationRealtimeEventType.callRenegotiate:
        // Chỉ người khởi tạo gửi offer: bên nhận xin offer mới (vừa bật camera).
        if (!widget.incoming) _requestRenegotiation();
      case ConversationRealtimeEventType.callAnswer:
        if (!widget.incoming && event.callSdp.isNotEmpty) {
          _runSignaling(_receiveAnswer(event.callSdp));
        }
      case ConversationRealtimeEventType.callIceCandidate:
        if (event.callCandidate.isNotEmpty) {
          _runSignaling(_receiveCandidate(event.callCandidate));
        }
      case ConversationRealtimeEventType.callRejected:
        if (!widget.incoming && event.reason == callBusyRejectReason) {
          unawaited(
            _leaveFromRemote(CallStatus.rejected, callTargetBusyMessage),
          );
        } else {
          unawaited(_leaveFromRemote(CallStatus.rejected));
        }
      case ConversationRealtimeEventType.callCancelled:
        unawaited(_leaveFromRemote(CallStatus.cancelled));
      case ConversationRealtimeEventType.callEnded:
        unawaited(_leaveFromRemote(CallStatus.ended));
      case ConversationRealtimeEventType.callMissed:
        unawaited(_leaveFromRemote(CallStatus.missed));
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

  void _maybeSendOffer() {
    if (widget.incoming ||
        !_remoteReadyReceived ||
        _peer == null ||
        !_ready ||
        _offerSent ||
        _leaving ||
        _fatalErrorHandled) {
      return;
    }
    _runSignaling(_sendOffer());
  }

  void _maybeReceivePendingOffer() {
    final pendingOffer = _pendingOffer;
    if (!widget.incoming ||
        !_acceptedHere ||
        pendingOffer == null ||
        _peer == null ||
        !_ready ||
        _leaving ||
        _fatalErrorHandled) {
      return;
    }
    _pendingOffer = null;
    _runSignaling(_receiveOffer(pendingOffer));
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
    if (peer == null || !_ready) {
      _pendingOffer = Map<String, dynamic>.from(value);
      return;
    }
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
    // Lượt thương lượng xong: chạy yêu cầu đã ghi nhớ (bật camera giữa chừng).
    unawaited(_drainRenegotiation());
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
    unawaited(_drainRenegotiation());
  }

  /// Cần thương lượng lại SDP (thêm / nhận video giữa cuộc gọi). Signaling
  /// chưa `stable` thì ghi nhớ, chạy sau khi lượt đang chạy xong.
  void _requestRenegotiation() {
    if (_leaving || _fatalErrorHandled) return;
    _renegotiationQueued = true;
    unawaited(_drainRenegotiation());
  }

  Future<void> _drainRenegotiation() async {
    final peer = _peer;
    if (_renegotiating ||
        !_renegotiationQueued ||
        peer == null ||
        !_ready ||
        _leaving ||
        _fatalErrorHandled) {
      return;
    }
    _renegotiating = true;
    try {
      final signaling = await peer.getSignalingState();
      final step = callRenegotiationStep(
        incoming: widget.incoming,
        signalingStable:
            signaling == null ||
            signaling == RTCSignalingState.RTCSignalingStateStable,
      );
      switch (step) {
        case CallRenegotiationStep.waitForStable:
          return;
        case CallRenegotiationStep.sendOffer:
          _renegotiationQueued = false;
          await _sendRenegotiationOffer(peer);
        case CallRenegotiationStep.requestOffer:
          _renegotiationQueued = false;
          await _sendSignal(CallSignalType.renegotiate, const {
            'reason': callRenegotiateVideoReason,
          });
      }
    } on Object catch (error) {
      // Thương lượng lại hỏng không cắt cuộc gọi thoại đang chạy.
      debugPrint('Không thương lượng lại được cuộc gọi: $error');
    } finally {
      _renegotiating = false;
    }
  }

  /// Người khởi tạo: bảo đảm có m-line video (chưa có thì thêm transceiver
  /// chỉ nhận) để bên kia gắn camera vừa bật, rồi gửi offer mới.
  Future<void> _sendRenegotiationOffer(RTCPeerConnection peer) async {
    final transceivers = await peer.getTransceivers();
    final hasVideo = transceivers.any(
      (item) =>
          item.sender.track?.kind == 'video' ||
          item.receiver.track?.kind == 'video',
    );
    if (!hasVideo) {
      await peer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
    }
    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    await _sendSignal(CallSignalType.offer, {
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  /// Nút "Video" / "Bật camera": xin camera, thêm track vào kết nối đang có,
  /// đổi sang bố cục video, bật loa ngoài rồi thương lượng lại.
  Future<void> _startLocalVideo() async {
    final peer = _peer;
    final stream = _localStream;
    if (peer == null || stream == null || !_canStartLocalVideo) return;
    setState(() => _startingLocalVideo = true);
    MediaStream? camera;
    try {
      camera = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      final tracks = camera.getVideoTracks();
      if (tracks.isEmpty) {
        throw StateError(
          tr(
            'Không mở được camera trên thiết bị.',
            'Couldn\'t open the camera on this device.',
          ),
        );
      }
      if (!mounted || _leaving || _fatalErrorHandled) {
        for (final track in camera.getTracks()) {
          track.stop();
        }
        return;
      }
      // Gắn vào luồng chung với micro để bên kia nhận cùng một MediaStream.
      final sender = await peer.addTrack(tracks.first, stream);
      _upgradeVideoStream = camera;
      _upgradeVideoSender = sender;
      await Helper.setSpeakerphoneOn(true);
      if (!mounted) return;
      setState(() {
        _hasLocalVideo = true;
        _cameraEnabled = true;
        _usingFrontCamera = true;
        _speakerEnabled = true;
        _localRenderer.srcObject = camera;
      });
      if (widget.incoming) _armVideoOfferTimeout();
      _requestRenegotiation();
    } on Object catch (error) {
      for (final track in camera?.getTracks() ?? <MediaStreamTrack>[]) {
        track.stop();
      }
      _showNotice(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _startingLocalVideo = false);
    }
  }

  /// Người nhận vừa xin offer mới: 8 giây không có offer (máy kia bản cũ) thì
  /// tắt camera lại và báo.
  void _armVideoOfferTimeout() {
    final requestedAt = DateTime.now();
    _videoOfferRequestedAt = requestedAt;
    _videoOfferTimer?.cancel();
    _videoOfferTimer = Timer(callVideoUpgradeOfferTimeout, () {
      if (!mounted || _leaving || _videoOfferRequestedAt != requestedAt) {
        return;
      }
      if (!shouldRevertLocalVideoUpgrade(
        requestedAt: requestedAt,
        now: DateTime.now(),
        lastOfferAt: _lastOfferAt,
      )) {
        return;
      }
      unawaited(_stopUpgradeVideo());
      _showNotice(callVideoUpgradeUnsupportedMessage);
    });
  }

  /// Gỡ camera đã bật giữa cuộc gọi (bên kia không thương lượng lại được).
  Future<void> _stopUpgradeVideo() async {
    final sender = _upgradeVideoSender;
    final camera = _upgradeVideoStream;
    _upgradeVideoSender = null;
    _upgradeVideoStream = null;
    _videoOfferRequestedAt = null;
    _renegotiationQueued = false;
    if (sender != null) {
      try {
        await _peer?.removeTrack(sender);
      } on Object {
        // Kết nối đã đóng: chỉ cần tắt camera.
      }
    }
    for (final track in camera?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    if (!mounted) return;
    setState(() {
      _hasLocalVideo = false;
      _cameraEnabled = false;
      _localRenderer.srcObject = _localStream;
    });
  }

  /// Nhận video từ bên kia: gắn đúng track video, cuộc gọi thoại tự đổi sang
  /// bố cục video (bật loa ngoài như cuộc gọi video).
  Future<void> _showRemoteVideo(
    MediaStream stream,
    MediaStreamTrack track,
  ) async {
    try {
      await _remoteRenderer.setSrcObject(stream: stream, trackId: track.id);
    } on Object {
      _remoteRenderer.srcObject = stream;
    }
    if (!mounted) return;
    final switchesLayout = !_videoActive;
    setState(() => _hasRemoteVideo = true);
    if (switchesLayout && !_speakerEnabled) {
      await Helper.setSpeakerphoneOn(true);
      if (mounted) setState(() => _speakerEnabled = true);
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _notice = null);
    });
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
        tr(
          'Không thể gửi tín hiệu WebRTC: ${result.failureOrNull?.message}',
          'Couldn\'t send WebRTC signal: ${result.failureOrNull?.message}',
        ),
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
      final busy =
          !widget.incoming &&
          call.metadata['end_reason']?.toString() == callBusyRejectReason;
      await _leaveFromRemote(call.status, busy ? callTargetBusyMessage : null);
      return;
    }
    if (_answeredOnAnotherDevice(call)) {
      await _leaveAnsweredElsewhere();
      return;
    }
    final startedAt = call.status == CallStatus.accepted
        ? call.startedAt ?? _startedAt ?? DateTime.now().toUtc()
        : null;
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().toUtc().difference(startedAt);
    if (call.status != CallStatus.ringing) {
      unawaited(_ringback.stop());
    }
    // Chiều gọi đi: bên kia đã nhận thì bắt đầu đếm thời hạn có media.
    if (call.status == CallStatus.accepted) _startConnectTimer();
    setState(() {
      _status = call.status;
      _startedAt = startedAt;
      _elapsed = elapsed.isNegative ? Duration.zero : elapsed;
    });
  }

  /// [status]: trạng thái cuối máy chủ báo (null = lỗi kỹ thuật) để chọn âm
  /// báo khi đóng màn (xem callEndCue). [message]: câu hiện ~2 giây trước khi
  /// đóng (vd. người nhận đang bận).
  Future<void> _leaveFromRemote([CallStatus? status, String? message]) async {
    if (_leaving) return;
    _leaving = true;
    unawaited(_ringback.stop());
    _playEndCue(callEndCue(incoming: widget.incoming, status: status));
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    _videoOfferTimer?.cancel();
    if (message != null) {
      _connectTimer?.cancel();
      if (mounted) setState(() => _closingMessage = message);
      await Future<void>.delayed(callErrorDisplayDuration);
    }
    await _notifyLeave();
    await _closeScreen();
  }

  /// Cuộc gọi đến đã được nhận ở máy khác: tắt giao diện gốc và đóng màn hình,
  /// không gửi reject / hangup.
  Future<void> _leaveAnsweredElsewhere() async {
    if (_leaving) return;
    _leaving = true;
    unawaited(_ringback.stop());
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    await NativeIncomingCallService.endCall(widget.callId, remoteEnded: true);
    await _notifyLeave();
    await _closeScreen();
  }

  /// Bắt đầu đếm thời hạn kết nối (chỉ một lần). Quá hạn mà WebRTC chưa
  /// "connected" thì báo lỗi và kết thúc gọn thay vì kẹt "Đang kết nối".
  void _startConnectTimer() {
    if (_connected || _connectTimer != null || _leaving) return;
    _connectTimer = Timer(callConnectTimeout, () {
      if (_connected || _leaving || _fatalErrorHandled) return;
      unawaited(
        _abortCall(
          StateError(callConnectTimeoutMessage),
          reason: 'connect_timeout',
        ),
      );
    });
  }

  /// Hiện thông báo lỗi ~2 giây rồi đóng màn, không báo gì lên máy chủ.
  Future<void> _leaveWithMessage(String message) async {
    if (_leaving) return;
    _leaving = true;
    unawaited(_ringback.stop());
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    _connectTimer?.cancel();
    if (mounted) setState(() => _error = message);
    await NativeIncomingCallService.endCall(widget.callId, remoteEnded: true);
    await Future<void>.delayed(callErrorDisplayDuration);
    await _notifyLeave();
    await _closeScreen();
  }

  Future<void> _finishLeave() async {
    if (_leaving) return;
    _leaving = true;
    unawaited(_ringback.stop());
    _playEndCue(
      callEndCue(incoming: widget.incoming, status: null, localHangup: true),
    );
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    await NativeIncomingCallService.endCall(widget.callId);
    try {
      await _terminateServerCall(
        reason: 'user_ended',
      ).timeout(const Duration(seconds: 4));
    } on Object {
      // The visible call surface must close even if the network/server request
      // is slow. Realtime catch-up will reconcile the call history afterwards.
    }
    await _notifyLeave();
    await _closeScreen();
  }

  void _playEndCue(CallCue? cue) {
    if (cue != null) unawaited(CallTonePlayer.playCue(cue));
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
    // Đã nhận ở máy khác: không bao giờ gác máy hộ máy kia.
    if (call != null && !call.isTerminal && !_answeredOnAnotherDevice(call)) {
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
    unawaited(_ringback.stop());
    _stateTimer?.cancel();
    _disconnectTimer?.cancel();
    if (mounted) {
      setState(() => _error = _friendlyError(error));
    }
    _connectTimer?.cancel();
    await _terminateServerCall(reason: reason);
    await Future<void>.delayed(callErrorDisplayDuration);
    await _leaveFromRemote();
  }

  Future<void> _notifyLeave() async {
    if (_leaveCallbackCalled) return;
    _leaveCallbackCalled = true;
    await NativeIncomingCallService.endCall(widget.callId);
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
    final tracks = _localVideoTracks;
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
    final tracks = _localVideoTracks;
    if (tracks.isEmpty) return;
    await Helper.switchCamera(tracks.first);
    if (mounted) {
      setState(() => _usingFrontCamera = !_usingFrontCamera);
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
            StateError(
              tr(
                'Kết nối cuộc gọi đã bị gián đoạn.',
                'The call connection was interrupted.',
              ),
            ),
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
                tr(
                  'Không thể khôi phục đường truyền WebRTC. Hãy kiểm tra TURN và firewall của server.',
                  'Couldn\'t restore the WebRTC connection. Check the server\'s TURN and firewall settings.',
                ),
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
                            ? tr('Đang khôi phục kết nối…', 'Reconnecting…')
                            : _status == CallStatus.accepted
                            ? _duration(_elapsed)
                            : tr('Đang kết nối', 'Connecting'),
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
                            tr(
                              'Cuộc họp đã kéo dài ${_elapsed.inMinutes} phút',
                              'Meeting has lasted ${_elapsed.inMinutes} min',
                            ),
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
              if (_notice != null)
                Positioned(
                  left: 28,
                  right: 28,
                  top: 102,
                  child: Semantics(
                    liveRegion: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF07111F).withValues(alpha: 0.86),
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WebTuiSpacing.md,
                          vertical: WebTuiSpacing.sm,
                        ),
                        child: Text(
                          _notice!,
                          textAlign: TextAlign.center,
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                        _microphoneEnabled ? 'Mic' : tr('Bật mic', 'Unmute'),
                        _toggleMicrophone,
                        active: !_microphoneEnabled,
                      ),
                      _control(
                        _speakerEnabled
                            ? Icons.volume_up
                            : Icons.hearing_outlined,
                        _speakerEnabled
                            ? tr('Loa ngoài', 'Speaker')
                            : tr('Tai nghe', 'Earpiece'),
                        () => unawaited(_toggleSpeaker()),
                        active: _speakerEnabled,
                      ),
                      if (_canStartLocalVideo)
                        _control(
                          WebTuiIcons.video,
                          _videoActive
                              ? tr('Bật camera', 'Camera on')
                              : 'Video',
                          () => unawaited(_startLocalVideo()),
                        ),
                      if (_hasLocalVideo) ...[
                        _control(
                          _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                          _cameraEnabled
                              ? 'Camera'
                              : tr('Bật cam', 'Camera on'),
                          _toggleCamera,
                          active: !_cameraEnabled,
                        ),
                        _control(
                          Icons.cameraswitch_outlined,
                          tr('Đổi cam', 'Flip camera'),
                          () => unawaited(_switchCamera()),
                        ),
                      ],
                      _control(
                        Icons.call_end,
                        tr('Kết thúc', 'End'),
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
    if (_closingMessage != null) {
      return _state(
        Icons.phone_disabled_outlined,
        widget.title,
        _closingMessage!,
      );
    }
    if (_error != null) {
      return _state(
        Icons.videocam_off_outlined,
        tr('Không thể kết nối', 'Couldn\'t connect'),
        _error!,
      );
    }
    if (!_ready) {
      return _state(
        Icons.sync,
        tr('Đang chuẩn bị cuộc gọi', 'Preparing call'),
        tr('Đang kết nối media...', 'Connecting media...'),
        loading: true,
      );
    }
    if (!_videoActive) {
      return _state(
        Icons.person,
        widget.title,
        _status == CallStatus.accepted
            ? tr('Đã kết nối', 'Connected')
            : tr('Đang đổ chuông...', 'Ringing...'),
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
            if (!_hasRemoteVideo && widget.mode == CallMode.audio)
              // Mình vừa bật camera, bên kia chưa có video: giữ ô người gọi.
              Positioned.fill(
                child: _state(
                  Icons.person,
                  widget.title,
                  tr('Đã kết nối', 'Connected'),
                ),
              )
            else
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
            if (_hasLocalVideo)
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
                        mirror: _usingFrontCamera,
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
  final message = error.toString().replaceFirst(
    RegExp(r'^(Exception|Bad state):\s*'),
    '',
  );
  if (message.contains('NotAllowed') || message.contains('Permission')) {
    return tr(
      'Cần cấp quyền camera và microphone để thực hiện cuộc gọi.',
      'Camera and microphone access is needed to make calls.',
    );
  }
  return message.trim().isEmpty
      ? tr('Không thể bắt đầu cuộc gọi.', 'Couldn\'t start the call.')
      : message;
}

/// Tín hiệu WebRTC (offer / answer / ICE / ready) có `target_device_id` khác máy
/// này: bỏ qua.
bool isCallSignalForAnotherDevice(
  ConversationRealtimeEvent event, {
  required String? localDeviceId,
}) {
  return switch (event.type) {
    ConversationRealtimeEventType.callOffer ||
    ConversationRealtimeEventType.callAnswer ||
    ConversationRealtimeEventType.callIceCandidate ||
    ConversationRealtimeEventType.callRenegotiate ||
    ConversationRealtimeEventType.callReady => callSignalTargetsAnotherDevice(
      targetDeviceId: event.targetDeviceId,
      localDeviceId: localDeviceId,
    ),
    _ => false,
  };
}
