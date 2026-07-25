import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/conversation_repository.dart';

void main() {
  test(
    'preserves Vietnamese accents and emoji when sending a message',
    () async {
      const body = 'Xin chào Đức ơi, tối nay cà phê nhé 😊';
      final repository = _CapturingConversationRepository();
      final useCase = SendMessageUseCase(repository);

      final result = await useCase.execute(
        workspaceId: 'workspace-1',
        channelId: 'channel-1',
        body: '  $body  ',
        clientMessageId: 'client-1',
      );

      expect(result.valueOrNull?.body, body);
      expect(repository.sentBody, body);
    },
  );
}

final class _CapturingConversationRepository implements ConversationRepository {
  String? sentBody;

  @override
  Future<Result<ChatMessage>> sendMessage({
    required String workspaceId,
    required String channelId,
    required String body,
    String? clientMessageId,
    String? parentId,
  }) async {
    sentBody = body;
    return Success(
      ChatMessage(
        id: 'message-1',
        workspaceId: workspaceId,
        channelId: channelId,
        kind: 'text',
        body: body,
        senderId: 'user-1',
        createdAt: DateTime.utc(2026, 7, 17, 9),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
