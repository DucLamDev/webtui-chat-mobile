import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/error/error_mapper.dart';
import '../domain/meeting_models.dart';

enum MeetingConnectionState {
  idle,
  connecting,
  connected,
  reconnecting,
  failed,
  disconnected,
}

/// Tín hiệu từ lớp họp (LiveKit hoặc bản giả khi test).
enum MeetingRoomSignal {
  reconnecting,
  reconnected,

  /// Mất kết nối ngoài ý muốn (mạng, máy chủ đóng phòng).
  disconnected,
  participantsChanged,
}

/// Người trong phòng, đã gọt về dữ liệu cần để vẽ ô lưới.
final class MeetingParticipantView {
  const MeetingParticipantView({
    required this.id,
    required this.name,
    this.isLocal = false,
    this.micOn = false,
    this.cameraOn = false,
    this.speaking = false,
  });

  final String id;
  final String name;
  final bool isLocal;
  final bool micOn;
  final bool cameraOn;
  final bool speaking;
}

/// Người dùng chưa cấp quyền micro / camera của hệ điều hành.
final class MeetingMediaPermissionException implements Exception {
  const MeetingMediaPermissionException(this.device);

  /// `microphone` hoặc `camera`.
  final String device;
}

/// Lớp trừu tượng quanh SDK họp để controller và test không phụ thuộc LiveKit.
abstract interface class MeetingRoomClient {
  Stream<MeetingRoomSignal> get signals;
  List<MeetingParticipantView> get participants;

  Future<void> connect({required String serverUrl, required String token});
  Future<void> setMicrophone(bool enabled);
  Future<void> setCamera(bool enabled);
  Future<void> flipCamera();
  Future<void> setSpeakerphone(bool enabled);
  Future<void> disconnect();
  Future<void> dispose();

  /// Hình video của một người; `null` khi không có hình (hiện chữ cái đầu).
  Widget? videoFor(String participantId);
}

/// Trạng thái màn họp: kết nối, mic, camera, loa và danh sách người.
class MeetingRoomController extends ChangeNotifier {
  MeetingRoomController({
    required MeetingRoomClient client,
    required MeetingJoinInfo join,
    this.startWithVideo = false,
    this.refreshJoin,
  }) : _client = client,
       _join = join {
    _signals = _client.signals.listen(_onSignal);
  }

  final MeetingRoomClient _client;
  final bool startWithVideo;

  /// Lấy token mới khi thử lại (token hết hạn sau ~2 giờ).
  final Future<MeetingJoinInfo> Function()? refreshJoin;
  late final StreamSubscription<MeetingRoomSignal> _signals;
  MeetingJoinInfo _join;
  bool _disposed = false;

  MeetingConnectionState _state = MeetingConnectionState.idle;
  String? _error;
  String? _mediaNotice;
  bool _micOn = false;
  bool _cameraOn = false;
  bool _speakerOn = true;
  bool _busy = false;

  MeetingConnectionState get state => _state;

  /// Lỗi kết nối (câu tiếng Việt) khi [state] là `failed` / `disconnected`.
  String? get error => _error;

  /// Thông báo nhẹ (ví dụ chưa cấp quyền camera), không làm rớt phòng.
  String? get mediaNotice => _mediaNotice;
  bool get micOn => _micOn;
  bool get cameraOn => _cameraOn;
  bool get speakerOn => _speakerOn;
  bool get canToggleMic => _join.canPublishAudio && _isLive;
  bool get canToggleCamera => _join.canPublishVideo && _isLive;
  bool get isLive => _isLive;
  MeetingJoinInfo get join => _join;
  List<MeetingParticipantView> get participants => _client.participants;

  bool get _isLive =>
      _state == MeetingConnectionState.connected ||
      _state == MeetingConnectionState.reconnecting;

  Widget? videoFor(String participantId) => _client.videoFor(participantId);

  Future<void> start() async {
    if (_state == MeetingConnectionState.connecting || _isLive) return;
    _set(MeetingConnectionState.connecting);
    try {
      await _client.connect(serverUrl: _join.serverUrl, token: _join.token);
    } on Object catch (error) {
      if (!_disposed) _fail(error);
      return;
    }
    if (_disposed) {
      // Màn họp đã đóng khi `connect` chưa xong: rời phòng, không để mic mở.
      await _client.disconnect().catchError((_) {});
      return;
    }
    _error = null;
    _set(MeetingConnectionState.connected);
    await _client.setSpeakerphone(_speakerOn).catchError((_) {});
    // Bật mic / camera ban đầu theo quyền máy chủ cấp; lỗi quyền chỉ báo nhẹ.
    if (_join.canPublishAudio) await _applyMic(true);
    if (startWithVideo && _join.canPublishVideo) await _applyCamera(true);
  }

  Future<void> retry() async {
    if (_state == MeetingConnectionState.connecting) return;
    try {
      final refresh = refreshJoin;
      if (refresh != null) _join = await refresh();
    } on Object catch (error) {
      _fail(error);
      return;
    }
    await _client.disconnect().catchError((_) {});
    _micOn = false;
    _cameraOn = false;
    _state = MeetingConnectionState.idle;
    await start();
  }

  Future<void> toggleMic() async {
    if (!canToggleMic || _busy) return;
    await _applyMic(!_micOn);
  }

  Future<void> toggleCamera() async {
    if (!canToggleCamera || _busy) return;
    await _applyCamera(!_cameraOn);
  }

  Future<void> flipCamera() async {
    if (!_cameraOn || _busy) return;
    _busy = true;
    try {
      await _client.flipCamera();
    } on Object {
      _mediaNotice = 'Không đổi được camera.';
      _notify();
    } finally {
      _busy = false;
    }
  }

  Future<void> toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      await _client.setSpeakerphone(next);
      _speakerOn = next;
    } on Object {
      _mediaNotice = 'Không đổi được loa.';
    }
    _notify();
  }

  void dismissNotice() {
    if (_mediaNotice == null) return;
    _mediaNotice = null;
    _notify();
  }

  Future<void> leave() async {
    await _client.disconnect().catchError((_) {});
    if (_disposed) return;
    _micOn = false;
    _cameraOn = false;
    _set(MeetingConnectionState.disconnected, error: null);
  }

  Future<void> _applyMic(bool enabled) async {
    _busy = true;
    try {
      await _client.setMicrophone(enabled);
      _micOn = enabled;
      _mediaNotice = null;
    } on MeetingMediaPermissionException {
      _mediaNotice =
          'Chưa có quyền dùng micro. Hãy cấp quyền trong Cài đặt của máy.';
    } on Object {
      _mediaNotice = 'Không bật được micro.';
    } finally {
      _busy = false;
    }
    _notify();
  }

  Future<void> _applyCamera(bool enabled) async {
    _busy = true;
    try {
      await _client.setCamera(enabled);
      _cameraOn = enabled;
      _mediaNotice = null;
    } on MeetingMediaPermissionException {
      _mediaNotice =
          'Chưa có quyền dùng camera. Hãy cấp quyền trong Cài đặt của máy.';
    } on Object {
      _mediaNotice = 'Không bật được camera.';
    } finally {
      _busy = false;
    }
    _notify();
  }

  void _onSignal(MeetingRoomSignal signal) {
    switch (signal) {
      case MeetingRoomSignal.reconnecting:
        if (_isLive) _set(MeetingConnectionState.reconnecting);
      case MeetingRoomSignal.reconnected:
        if (_isLive) _set(MeetingConnectionState.connected);
      case MeetingRoomSignal.disconnected:
        // Người dùng tự rời thì `leave` đã đặt trạng thái; chỉ báo mất kết nối
        // khi đang ở trong phòng.
        if (_isLive) {
          _micOn = false;
          _cameraOn = false;
          _set(
            MeetingConnectionState.disconnected,
            error: 'Mất kết nối với cuộc họp.',
          );
        }
      case MeetingRoomSignal.participantsChanged:
        _notify();
    }
  }

  void _fail(Object error) {
    if (_disposed) return;
    _set(MeetingConnectionState.failed, error: userFacingErrorMessage(error));
  }

  void _set(MeetingConnectionState state, {String? error}) {
    _state = state;
    _error =
        state == MeetingConnectionState.failed ||
            state == MeetingConnectionState.disconnected
        ? error
        : null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_signals.cancel());
    unawaited(_client.dispose());
    super.dispose();
  }
}
