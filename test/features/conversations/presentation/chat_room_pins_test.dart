import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/legal_acceptance_access_policy.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_media_uploader.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_outbox_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_realtime_event.dart';
import 'package:webtui_chat/features/conversations/domain/entities/message_outbox_item.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/call_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/message_attachment_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/message_outbox_repository.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/rich_message_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/chat_room_controller.dart';
import 'package:webtui_chat/features/profile/domain/entities/user_profile.dart';
import 'package:webtui_chat/features/profile/domain/repositories/profile_repository.dart';

const _scope = ChatRoomScope(
  workspaceId: 'ws-1',
  channelId: 'ch-1',
  title: 'Nhóm thử',
);

ChatMessage _message(String id, {String body = 'nội dung'}) => ChatMessage(
  id: id,
  workspaceId: 'ws-1',
  channelId: 'ch-1',
  kind: 'text',
  body: body,
  createdAt: DateTime.utc(2026, 11, 19, 10),
  senderId: 'u-2',
);

void main() {
  Future<ProviderContainer> open(_Repo repo) async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUri: Uri.parse('http://localhost:8080'),
            wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
          ),
        ),
        legalAcceptanceAccessPolicyProvider.overrideWithValue(
          LegalAcceptanceAccessPolicy()..markComplete(),
        ),
        conversationRepositoryProvider.overrideWithValue(repo),
        conversationRealtimeRepositoryProvider.overrideWithValue(_Realtime()),
        conversationDraftRepositoryProvider.overrideWithValue(_Drafts()),
        messageOutboxRepositoryProvider.overrideWithValue(_Outbox()),
        enqueueMessageOutboxUseCaseProvider.overrideWithValue(
          EnqueueMessageOutboxUseCase(
            repository: _Outbox(),
            instanceScopeId: 'test',
          ),
        ),
        messageMediaUploaderProvider.overrideWithValue(_Uploader()),
        messageAttachmentRepositoryProvider.overrideWithValue(_Attachments()),
        messageAttachmentPickerRepositoryProvider.overrideWithValue(_Picker()),
        messageVoiceRecorderRepositoryProvider.overrideWithValue(_Recorder()),
        callRepositoryProvider.overrideWithValue(_Calls()),
        richMessageRepositoryProvider.overrideWithValue(_Rich()),
        authTokenRepositoryProvider.overrideWithValue(_Tokens()),
        profileRepositoryProvider.overrideWithValue(_Profile()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(chatRoomControllerProvider(_scope), (_, _) {});
    // Chờ lượt tải đầu tiên xong.
    await container.read(chatRoomControllerProvider(_scope).notifier).load();
    return container;
  }

  ChatRoomState read(ProviderContainer c) =>
      c.read(chatRoomControllerProvider(_scope));

  test('tin ghim từ listPins hiện dù không nằm trong trang tin', () async {
    final repo = _Repo(
      messages: [_message('m-1')],
      pins: [_message('m-old', body: 'ghim cũ')],
    );
    final container = await open(repo);
    final state = read(container);
    expect(state.messages.map((m) => m.id), ['m-1']);
    expect(state.pinnedMessages.map((m) => m.id), ['m-old']);
    expect(state.pinnedMessages.single.isPinned, isTrue);
  });

  test(
    'tin trong trang trùng tin ghim được đánh cờ để menu hiện Bỏ ghim',
    () async {
      final repo = _Repo(messages: [_message('m-1')], pins: [_message('m-1')]);
      final container = await open(repo);
      expect(read(container).messages.single.isPinned, isTrue);
    },
  );

  test('ghim rồi bỏ ghim trên máy cập nhật danh sách ngay', () async {
    final repo = _Repo(messages: [_message('m-1')], pins: const []);
    final container = await open(repo);
    final controller = container.read(
      chatRoomControllerProvider(_scope).notifier,
    );
    expect(read(container).pinnedMessages, isEmpty);

    await controller.togglePin(read(container).messages.single);
    expect(read(container).pinnedMessages.map((m) => m.id), ['m-1']);

    await controller.togglePin(read(container).messages.single);
    expect(read(container).pinnedMessages, isEmpty);
    expect(read(container).messages.single.isPinned, isFalse);
  });

  test('tin ghim đã xoá thì không hiện', () async {
    final deleted = ChatMessage(
      id: 'm-9',
      workspaceId: 'ws-1',
      channelId: 'ch-1',
      kind: 'text',
      body: '',
      createdAt: DateTime.utc(2026, 11, 19, 10),
      deletedAt: DateTime.utc(2026, 11, 19, 11),
    );
    final container = await open(_Repo(messages: const [], pins: [deleted]));
    expect(read(container).pinnedMessages, isEmpty);
  });

  test('listPins lỗi không làm lỗi phòng', () async {
    final repo = _Repo(
      messages: [_message('m-1')],
      pins: const [],
      pinsFail: true,
    );
    final container = await open(repo);
    final state = read(container);
    expect(state.errorMessage, isNull);
    expect(state.messages, hasLength(1));
    expect(state.pinnedMessages, isEmpty);
  });

  test('listPins ném ngoại lệ cũng không làm lỗi phòng', () async {
    final repo = _Repo(
      messages: [_message('m-1')],
      pins: const [],
      pinsThrow: true,
    );
    final container = await open(repo);
    expect(read(container).errorMessage, isNull);
    expect(read(container).messages, hasLength(1));
  });
}

final class _Repo implements ConversationRepository {
  _Repo({
    required this.messages,
    required this.pins,
    this.pinsFail = false,
    this.pinsThrow = false,
  });

  final List<ChatMessage> messages;
  final List<ChatMessage> pins;
  final bool pinsFail;
  final bool pinsThrow;

  @override
  Future<Result<MessagePage>> listMessagePage({
    required String workspaceId,
    required String channelId,
    int limit = 50,
    String? beforeId,
  }) async => Success(MessagePage(messages: messages));

  @override
  Future<Result<List<ChatMessage>>> listPins({
    required String workspaceId,
    required String channelId,
  }) async {
    if (pinsThrow) throw StateError('mạng lỗi');
    if (pinsFail) {
      return const FailureResult(
        Failure(kind: FailureKind.network, message: 'Không tải được ghim'),
      );
    }
    return Success(pins);
  }

  @override
  Future<Result<ChatMessage>> pinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async => Success(messages.firstWhere((m) => m.id == messageId));

  @override
  Future<Result<void>> unpinMessage({
    required String workspaceId,
    required String channelId,
    required String messageId,
  }) async => const Success(null);

  @override
  Future<Result<void>> markRead({
    required String workspaceId,
    required String channelId,
    required String lastReadMessageId,
  }) async => const Success(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('chưa giả lập: ${invocation.memberName}');
}

final class _Realtime implements ConversationRealtimeRepository {
  @override
  Stream<ConversationRealtimeEvent> subscribeToChannel({
    required String workspaceId,
    required String channelId,
  }) => const Stream.empty();

  @override
  Future<void> sendTyping({
    required String workspaceId,
    required String channelId,
    required bool isTyping,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Drafts implements ConversationDraftRepository {
  @override
  Future<String> readDraft({
    required String workspaceId,
    required String channelId,
  }) async => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Outbox implements MessageOutboxRepository {
  @override
  Future<List<MessageOutboxItem>> list({
    required String workspaceId,
    required String channelId,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Tokens implements AuthTokenRepository {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Profile implements ProfileRepository {
  @override
  Future<Result<UserProfile>> me() async => const FailureResult(
    Failure(kind: FailureKind.network, message: 'không có hồ sơ'),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Uploader implements MessageMediaUploader {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Attachments implements MessageAttachmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Picker implements MessageAttachmentPickerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Recorder implements MessageVoiceRecorderRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Calls implements CallRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Rich implements RichMessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
