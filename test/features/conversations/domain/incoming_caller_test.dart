import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/entities/incoming_caller.dart';

ContactSummary _person(
  String id,
  String name, {
  String? avatar,
  String? gender,
}) => ContactSummary(
  userId: id,
  displayName: name,
  username: id,
  email: '$id@example.com',
  status: 'active',
  avatarUrl: avatar,
  gender: gender,
);

ConversationSummary _direct(
  String channelId,
  String title, {
  String? peer,
  String? avatar,
  ConversationKind kind = ConversationKind.direct,
}) => ConversationSummary(
  id: channelId,
  workspaceId: 'ws',
  channelId: channelId,
  kind: kind,
  title: title,
  preview: '',
  updatedAt: DateTime.utc(2026, 11, 17),
  peerUserId: peer,
  avatarUrl: avatar,
);

ChannelMember _member(String userId, String name, {String? avatar}) =>
    ChannelMember(
      channelId: 'dm-1',
      userId: userId,
      email: '$userId@example.com',
      username: userId,
      displayName: name,
      status: 'active',
      joinedAt: DateTime.utc(2026, 11, 1),
      avatarUrl: avatar,
    );

void main() {
  test(
    'tìm trong danh bạ / thành viên theo mã người gọi (tên, ảnh, giới tính)',
    () {
      final caller = findIncomingCaller(
        initiatorUserId: 'u-ha',
        channelId: 'dm-1',
        people: [
          _person('u-nam', 'Nam'),
          _person('u-ha', 'Trần Thu Hà', avatar: '/a/ha.jpg', gender: 'female'),
        ],
      );
      expect(caller?.name, 'Trần Thu Hà');
      expect(caller?.avatarUrl, '/a/ha.jpg');
      expect(caller?.gender, 'female');
      expect(caller?.userId, 'u-ha');
    },
  );

  test('chưa có trong danh bạ: lấy tên từ trò chuyện 1-1 của cuộc gọi', () {
    final caller = findIncomingCaller(
      initiatorUserId: 'u-ha',
      channelId: 'dm-1',
      conversations: [
        _direct('group-1', 'Nhóm dự án', kind: ConversationKind.channel),
        _direct('dm-1', 'Trần Thu Hà', peer: 'u-ha', avatar: '/a/ha.jpg'),
      ],
    );
    expect(caller?.name, 'Trần Thu Hà');
    expect(caller?.avatarUrl, '/a/ha.jpg');
  });

  test(
    'trò chuyện 1-1 cùng kênh nhưng người kia khác người gọi thì bỏ qua',
    () {
      expect(
        findIncomingCaller(
          initiatorUserId: 'u-ha',
          channelId: 'dm-1',
          conversations: [_direct('dm-1', 'Nam', peer: 'u-nam')],
        ),
        isNull,
      );
    },
  );

  test(
    'không có trên máy: lấy từ thành viên cuộc trò chuyện tải từ máy chủ',
    () {
      final caller = findIncomingCaller(
        initiatorUserId: 'u-ha',
        channelId: 'dm-1',
        people: [_person('u-nam', 'Nam')],
        members: [
          _member('u-me', 'Tôi'),
          _member('u-ha', 'Thu Hà', avatar: '/a.jpg'),
        ],
      );
      expect(caller?.name, 'Thu Hà');
      expect(caller?.avatarUrl, '/a.jpg');
    },
  );

  test('tên rỗng không được dùng; không tìm được thì trả null', () {
    expect(
      findIncomingCaller(
        initiatorUserId: 'u-ha',
        channelId: 'dm-1',
        people: [_person('u-ha', '   ')],
        members: [_member('u-ha', '')],
      )?.name,
      'u-ha',
      reason: 'thành viên không có tên hiển thị thì dùng tên đăng nhập',
    );
    expect(
      findIncomingCaller(initiatorUserId: 'u-ha', channelId: 'dm-1'),
      isNull,
    );
  });

  test('ghép thêm ảnh / giới tính từ nguồn khác, giữ tên', () {
    const pushed = IncomingCaller(name: 'Hà (push)');
    final merged = pushed.mergedWith(
      const IncomingCaller(
        name: 'Thu Hà',
        avatarUrl: '/a.jpg',
        gender: 'female',
      ),
    );
    expect(merged.name, 'Hà (push)');
    expect(merged.avatarUrl, '/a.jpg');
    expect(merged.gender, 'female');
    expect(pushed.mergedWith(null), same(pushed));
  });
}
