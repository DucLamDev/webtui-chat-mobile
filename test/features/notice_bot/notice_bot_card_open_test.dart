import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/router/notification_locations.dart';
import 'package:webtui_chat/features/conversations/data/dto/conversation_dto.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_card.dart';

const _ws = '11111111-1111-4111-8111-111111111111';
const _ch = '22222222-2222-4222-8222-222222222222';
const _id = '33333333-3333-4333-8333-333333333333';
const _user = '44444444-4444-4444-8444-444444444444';

MessageCardOpenAction? _open(Map<String, Object?> target) {
  final card = parseMessageCard({
    'version': 2,
    'title': 'Thẻ',
    'actions': [
      {'type': 'open', 'label': 'Mở', 'tone': 'primary', 'target': target},
    ],
  });
  final actions = card?.actions ?? const [];
  return actions.isEmpty ? null : actions.single as MessageCardOpenAction;
}

String? _where(Map<String, Object?> target) {
  final action = _open(target);
  return action == null
      ? null
      : locationForCardOpenTarget(action.target, fallbackWorkspaceId: _ws);
}

void main() {
  group('nút open: đọc thẻ', () {
    test('đích hợp lệ được giữ', () {
      final action = _open({
        'target_type': 'task',
        'workspace_id': _ws,
        'channel_id': _ch,
        'task_id': _id,
        'deep_link': 'webtui://chat/conversations/$_ch',
      })!;
      expect(action.label, 'Mở');
      expect(action.tone, MessageCardActionTone.primary);
      expect(action.target.type, MessageCardOpenTargetType.task);
      expect(action.target.taskId, _id);
    });

    test('target_type lạ làm nút bị ẩn', () {
      expect(_open({'target_type': 'hologram', 'channel_id': _ch}), isNull);
    });

    test('deep_link không bắt đầu webtui:// bị bỏ', () {
      expect(
        _open({
          'target_type': 'contacts',
          'deep_link': 'https://evil.example/x',
        }),
        isNull,
      );
    });

    test('id không phải UUID hoặc thiếu trường bắt buộc bị bỏ', () {
      expect(
        _open({'target_type': 'task', 'channel_id': 'x', 'task_id': _id}),
        isNull,
      );
      expect(_open({'target_type': 'task', 'channel_id': _ch}), isNull);
      expect(_open({'target_type': 'call_back', 'channel_id': _ch}), isNull);
    });

    test('thiếu target thì không có nút', () {
      final card = parseMessageCard({
        'version': 2,
        'title': 'Thẻ',
        'actions': [
          {'type': 'open', 'label': 'Mở'},
        ],
      });
      expect(card!.actions, isEmpty);
    });
  });

  group('nút open: đích sang đường dẫn', () {
    test('conversation', () {
      expect(
        _where({
          'target_type': 'conversation',
          'channel_id': _ch,
          'message_id': _id,
        }),
        '/conversations/$_ch?workspaceId=$_ws&title=H%E1%BB%99i+tho%E1%BA%A1i&messageId=$_id',
      );
    });
    test('task', () {
      final uri = Uri.parse(
        _where({'target_type': 'task', 'channel_id': _ch, 'task_id': _id})!,
      );
      expect(uri.path, '/conversations/$_ch');
      expect(uri.queryParameters['tool'], 'tasks');
      expect(uri.queryParameters['taskId'], _id);
      expect(uri.queryParameters['workspaceId'], _ws);
    });
    test('contacts', () {
      expect(
        _where({'target_type': 'contacts'}),
        '/?tab=contacts&workspaceId=$_ws',
      );
    });
    test('approval', () {
      expect(
        _where({'target_type': 'approval', 'approval_id': _id}),
        '/approvals/$_id?workspaceId=$_ws',
      );
    });
    test('inbox_conversation', () {
      expect(
        _where({'target_type': 'inbox_conversation', 'conversation_id': _id}),
        '/inbox/$_id?workspaceId=$_ws',
      );
    });
    test('device_approval', () {
      expect(
        _where({'target_type': 'device_approval', 'session_id': _id}),
        '/device-approvals/$_id',
      );
    });
    test('call_back mở chat 1-1 và hẹn gọi đúng chế độ', () {
      for (final mode in ['audio', 'video']) {
        final uri = Uri.parse(
          _where({
            'target_type': 'call_back',
            'channel_id': _ch,
            'user_id': _user,
            'call_mode': mode,
          })!,
        );
        expect(uri.path, '/conversations/$_ch');
        expect(uri.queryParameters['startCall'], mode);
        expect(uri.queryParameters['peerUserId'], _user);
      }
    });
    test('workspace trong đích ưu tiên hơn workspace của tin', () {
      const other = '55555555-5555-4555-8555-555555555555';
      expect(
        _where({'target_type': 'contacts', 'workspace_id': other}),
        '/?tab=contacts&workspaceId=$other',
      );
    });
  });

  group('kênh bot trong dữ liệu kênh', () {
    test('ChannelDto đọc notice_bot', () {
      Map<String, dynamic> json(bool? bot) => {
        'id': 'c',
        'workspace_id': 'w',
        'name': 'Bot',
        'type': 'direct',
        'notice_bot': ?bot,
      };
      expect(ChannelDto.fromJson(json(true)).toDomain().noticeBot, isTrue);
      expect(ChannelDto.fromJson(json(false)).toDomain().noticeBot, isFalse);
      expect(ChannelDto.fromJson(json(null)).toDomain().noticeBot, isFalse);
    });
  });
}
