import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/call_session.dart';

final class CallRemoteDataSource {
  const CallRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<CallSession> createCall({
    required String workspaceId,
    required String channelId,
    required String targetUserId,
    required CallMode mode,
    required String clientCallId,
    Map<String, Object?> metadata = const {},
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/calls',
      data: compactMap({
        'channel_id': channelId,
        'target_user_id': targetUserId,
        'client_call_id': clientCallId,
        'mode': _modeToApi(mode),
        'metadata': metadata,
      }),
    );
    return _callFromMap(envelopeItem(response.data, 'call'));
  }

  Future<CallSession> getCall({
    required String workspaceId,
    required String callId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/calls/${_e(callId)}',
    );
    return _callFromMap(envelopeItem(response.data, 'call'));
  }

  Future<CallSession> changeStatus({
    required String workspaceId,
    required String callId,
    required String action,
    String? reason,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/calls/${_e(callId)}/$action',
      data: compactMap({'reason': reason}),
    );
    return _callFromMap(envelopeItem(response.data, 'call'));
  }

  Future<CallSignal> sendSignal({
    required String workspaceId,
    required String callId,
    required CallSignalType signalType,
    required Map<String, Object?> payload,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/calls/${_e(callId)}/signals',
      data: {'signal_type': _signalToApi(signalType), 'payload': payload},
    );
    return _signalFromMap(envelopeItem(response.data, 'signal'));
  }
}

CallSession _callFromMap(JsonMap map) {
  return CallSession(
    id: stringField(map, const ['id', 'call_id', 'callId']),
    workspaceId: stringField(map, const ['workspace_id', 'workspaceId']),
    channelId: stringField(map, const ['channel_id', 'channelId']),
    initiatorUserId: stringField(map, const [
      'initiator_user_id',
      'initiatorUserId',
    ]),
    targetUserId: stringField(map, const ['target_user_id', 'targetUserId']),
    clientCallId: nullableStringField(map, const [
      'client_call_id',
      'clientCallId',
    ]),
    mode: _modeFromApi(stringField(map, const ['mode'], fallback: 'audio')),
    status: _statusFromApi(
      stringField(map, const ['status'], fallback: 'ringing'),
    ),
    startedAt: nullableDateTimeField(map, const ['started_at', 'startedAt']),
    endedAt: nullableDateTimeField(map, const ['ended_at', 'endedAt']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
    updatedAt: dateTimeField(map, const ['updated_at', 'updatedAt']),
    metadata: jsonMap(field(map, const ['metadata'])),
  );
}

CallSignal _signalFromMap(JsonMap map) {
  return CallSignal(
    id: stringField(map, const ['id', 'signal_id', 'signalId']),
    workspaceId: stringField(map, const ['workspace_id', 'workspaceId']),
    callId: stringField(map, const ['call_id', 'callId']),
    senderUserId: stringField(map, const ['sender_user_id', 'senderUserId']),
    signalType: _signalFromApi(
      stringField(map, const ['signal_type', 'signalType']),
    ),
    payload: jsonMap(field(map, const ['payload'])),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

CallMode _modeFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'video' => CallMode.video,
    _ => CallMode.audio,
  };
}

String _modeToApi(CallMode mode) {
  return switch (mode) {
    CallMode.audio => 'audio',
    CallMode.video => 'video',
  };
}

CallStatus _statusFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'accepted' => CallStatus.accepted,
    'rejected' => CallStatus.rejected,
    'cancelled' || 'canceled' => CallStatus.cancelled,
    'ended' => CallStatus.ended,
    'missed' => CallStatus.missed,
    _ => CallStatus.ringing,
  };
}

CallSignalType _signalFromApi(String value) {
  return switch (value.trim().toLowerCase()) {
    'answer' => CallSignalType.answer,
    'ice_candidate' || 'icecandidate' => CallSignalType.iceCandidate,
    'ready' => CallSignalType.ready,
    'ringing' => CallSignalType.ringing,
    'accepted' => CallSignalType.accepted,
    'rejected' => CallSignalType.rejected,
    'cancelled' || 'canceled' => CallSignalType.cancelled,
    'ended' => CallSignalType.ended,
    'missed' => CallSignalType.missed,
    _ => CallSignalType.offer,
  };
}

String _signalToApi(CallSignalType signalType) {
  return switch (signalType) {
    CallSignalType.offer => 'offer',
    CallSignalType.answer => 'answer',
    CallSignalType.iceCandidate => 'ice_candidate',
    CallSignalType.ready => 'ready',
    CallSignalType.ringing => 'ringing',
    CallSignalType.accepted => 'accepted',
    CallSignalType.rejected => 'rejected',
    CallSignalType.cancelled => 'cancelled',
    CallSignalType.ended => 'ended',
    CallSignalType.missed => 'missed',
  };
}

String _e(String value) => Uri.encodeComponent(value);
