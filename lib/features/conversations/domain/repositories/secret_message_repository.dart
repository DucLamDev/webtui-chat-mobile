import '../../../../core/result/result.dart';

abstract interface class SecretMessageRepository {
  Future<Result<void>> send(
    String workspaceId,
    String channelId,
    String body,
    String clientId,
  );
  Future<Result<String>> reveal(
    String workspaceId,
    String channelId,
    String messageId,
    String token,
  );
}
