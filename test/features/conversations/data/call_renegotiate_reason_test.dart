import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/data/repositories/web_socket_conversation_realtime_repository.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';

ConversationRealtimeEvent? _event(Map<String, Object?> payload, String type) {
  return ConversationRealtimeEventMapper.fromSocketData(
    jsonEncode({
      'type': type,
      'workspace_id': 'ws-1',
      'channel_id': 'ch-1',
      'user_id': 'callee',
      'payload': payload,
    }),
    fallbackWorkspaceId: 'ws-1',
    fallbackChannelId: 'ch-1',
  );
}

void main() {
  // Rà soát 18/11/2026: máy chủ chuyển nguyên dữ liệu tín hiệu vào `payload.signal`; app chỉ đọc `payload.reason`
  // nên lý do của renegotiate (bên nhận xin khôi phục `ice_restart` / bật camera `video`) luôn rỗng.
  test('lý do của tín hiệu renegotiate nằm trong payload.signal', () {
    final event = _event({
      'call_id': 'call-1',
      'signal': {'reason': 'ice_restart'},
    }, 'CallRenegotiate');
    expect(event?.type, ConversationRealtimeEventType.callRenegotiate);
    expect(event?.reason, 'ice_restart');
  });

  test('lý do ở payload (từ chối / kết thúc) vẫn được ưu tiên', () {
    final event = _event({
      'call_id': 'call-1',
      'reason': 'busy',
      'signal': {'reason': 'video'},
    }, 'CallRejected');
    expect(event?.reason, 'busy');
  });
}
