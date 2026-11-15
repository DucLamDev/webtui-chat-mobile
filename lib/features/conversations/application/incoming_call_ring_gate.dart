import 'dart:async';
import 'dart:collection';

import '../domain/entities/call_session.dart';
import '../domain/entities/incoming_call_policy.dart';

/// Ghi nhớ các cuộc gọi ĐI do chính máy này tạo (theo `call_id` và
/// `client_call_id`), để không bao giờ hiện hộp "Cuộc gọi đến" cho chúng.
///
/// `client_call_id` được ghi TRƯỚC khi gửi yêu cầu tạo cuộc gọi: máy chủ phát
/// `CallInvited` (cả tới người gọi) trước khi trả kết quả tạo cuộc gọi, nên lúc
/// sự kiện tới máy có thể chưa biết `call_id`.
final class OutgoingCallRegistry {
  OutgoingCallRegistry({this.limit = 64});

  final int limit;
  final LinkedHashSet<String> _callIds = LinkedHashSet<String>();
  final LinkedHashSet<String> _clientCallIds = LinkedHashSet<String>();
  final StreamController<String> _registered =
      StreamController<String>.broadcast(sync: true);

  /// Phát `call_id` mỗi khi biết thêm một cuộc gọi đi của máy này.
  Stream<String> get registered => _registered.stream;

  void rememberClientCallId(String clientCallId) {
    final id = clientCallId.trim();
    if (id.isEmpty) return;
    _add(_clientCallIds, id);
  }

  void rememberCall(String callId, {String? clientCallId}) {
    final id = callId.trim();
    if (clientCallId != null) rememberClientCallId(clientCallId);
    if (id.isEmpty) return;
    final isNew = !_callIds.contains(id);
    _add(_callIds, id);
    if (isNew && !_registered.isClosed) _registered.add(id);
  }

  bool isOutgoing({String? callId, String? clientCallId}) {
    final id = callId?.trim() ?? '';
    if (id.isNotEmpty && _callIds.contains(id)) return true;
    final clientId = clientCallId?.trim() ?? '';
    return clientId.isNotEmpty && _clientCallIds.contains(clientId);
  }

  void _add(LinkedHashSet<String> set, String value) {
    set
      ..remove(value)
      ..add(value);
    while (set.length > limit) {
      set.remove(set.first);
    }
  }

  Future<void> dispose() => _registered.close();
}

/// Quyết định có đổ chuông / hiện hộp "Cuộc gọi đến" cho [CallSession] trên
/// máy này. Mọi nguồn (realtime, thông báo đẩy, CallKit, polling) đi qua đây.
final class IncomingCallRingGate {
  const IncomingCallRingGate({
    required OutgoingCallRegistry outgoingCalls,
    required Future<String?> Function() resolveCurrentUserId,
    required Future<String?> Function() resolveLocalDeviceId,
  }) : _outgoingCalls = outgoingCalls,
       _resolveCurrentUserId = resolveCurrentUserId,
       _resolveLocalDeviceId = resolveLocalDeviceId;

  final OutgoingCallRegistry _outgoingCalls;
  final Future<String?> Function() _resolveCurrentUserId;
  final Future<String?> Function() _resolveLocalDeviceId;

  /// Kiểm nhanh không cần mạng, dùng trước khi tải chi tiết cuộc gọi.
  bool isOwnOutgoingCall(String callId) =>
      _outgoingCalls.isOutgoing(callId: callId);

  Future<bool> shouldRing(CallSession call) async {
    if (_outgoingCalls.isOutgoing(
      callId: call.id,
      clientCallId: call.clientCallId,
    )) {
      return false;
    }
    final localDeviceId = await _safe(_resolveLocalDeviceId);
    final currentUserId = await _safe(_resolveCurrentUserId);
    return shouldRingForIncomingCall(
      currentUserId: currentUserId,
      initiatorUserId: call.initiatorUserId,
      targetUserId: call.targetUserId,
      initiatorDeviceId: call.initiatorDeviceId,
      localDeviceId: localDeviceId,
      // Trong lúc chờ id người dùng, màn gọi đi có thể vừa nhận `call_id`.
      placedByThisDevice: _outgoingCalls.isOutgoing(callId: call.id),
    );
  }

  static Future<String?> _safe(Future<String?> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }
}
