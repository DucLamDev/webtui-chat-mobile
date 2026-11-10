import '../../../../core/result/result.dart';
import '../../domain/repositories/secret_message_repository.dart';

final class SecretMessageUseCases {
  const SecretMessageUseCases(this._repository);
  final SecretMessageRepository _repository;
  Future<Result<void>> send(
    String workspaceId,
    String channelId,
    String body,
    String clientId,
  ) => _repository.send(workspaceId, channelId, body, clientId);
  Future<Result<String>> reveal(
    String workspaceId,
    String channelId,
    String messageId,
    String token,
  ) => _repository.reveal(workspaceId, channelId, messageId, token);
}
