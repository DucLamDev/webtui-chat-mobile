import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/chat_room_controller.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/message_sender_directory.dart';

void main() {
  group('MessageSenderDirectory', () {
    test('tên hiển thị trước, rồi tên đăng nhập, rồi phần đầu email', () {
      final directory = MessageSenderDirectory.fromMembers([
        _member('u-1', displayName: 'Nguyễn Lâm', avatarUrl: ' /a/1.png '),
        _member('u-2', displayName: '  ', username: 'ha.tran'),
        _member(
          'u-3',
          displayName: '',
          username: '',
          email: 'tien@vpsttt.test',
        ),
      ]);

      expect(directory.nameOf('u-1'), 'Nguyễn Lâm');
      expect(directory['u-1']?.avatarUrl, '/a/1.png');
      expect(directory.nameOf('u-2'), 'ha.tran');
      expect(directory['u-2']?.avatarUrl, isNull);
      expect(directory.nameOf(' u-3 '), 'tien');
    });

    test('người gửi không có trong phòng hiện "Người dùng"', () {
      final directory = MessageSenderDirectory.fromMembers([_member('u-1')]);

      expect(directory.nameOf('u-404'), 'Người dùng');
      expect(directory.nameOf(null), 'Người dùng');
      expect(const MessageSenderDirectory.empty().length, 0);
    });
  });

  group('messageSenderDirectoryProvider', () {
    const scope = ChatRoomScope(
      workspaceId: 'ws-1',
      channelId: 'ch-1',
      title: 'Chung',
    );

    test('tải thành viên phòng để tra tên người gửi', () async {
      final repository = _FakeConversationRepository(
        Success([_member('u-1', displayName: 'Hà')]),
      );
      final container = ProviderContainer(
        overrides: [
          listChannelMembersUseCaseProvider.overrideWithValue(
            ListChannelMembersUseCase(repository),
          ),
        ],
      );
      addTearDown(container.dispose);

      final directory = await container.read(
        messageSenderDirectoryProvider(scope).future,
      );

      expect(directory.nameOf('u-1'), 'Hà');
      expect(repository.requested, ['ws-1/ch-1']);
    });

    test('lỗi mạng trả danh bạ rỗng, không chặn màn chat', () async {
      final container = ProviderContainer(
        overrides: [
          listChannelMembersUseCaseProvider.overrideWithValue(
            ListChannelMembersUseCase(
              _FakeConversationRepository(
                const FailureResult(
                  Failure(kind: FailureKind.network, message: 'Mất mạng.'),
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final directory = await container.read(
        messageSenderDirectoryProvider(scope).future,
      );

      expect(directory.length, 0);
    });
  });
}

ChannelMember _member(
  String userId, {
  String displayName = 'Thành viên',
  String username = 'member',
  String email = 'member@vpsttt.test',
  String? avatarUrl,
}) {
  return ChannelMember(
    channelId: 'ch-1',
    userId: userId,
    email: email,
    username: username,
    displayName: displayName,
    status: 'active',
    joinedAt: DateTime.utc(2026, 11, 2),
    avatarUrl: avatarUrl,
  );
}

/// Chỉ cài `listMembers`; gọi hàm khác của repository là lỗi test.
final class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository(this.result);

  final Result<List<ChannelMember>> result;
  final requested = <String>[];

  @override
  Future<Result<List<ChannelMember>>> listMembers({
    required String workspaceId,
    required String channelId,
  }) async {
    requested.add('$workspaceId/$channelId');
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
