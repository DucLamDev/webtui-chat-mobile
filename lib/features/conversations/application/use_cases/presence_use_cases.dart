import '../../../../core/result/result.dart';
import '../../../auth/domain/repositories/device_identity_repository.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/conversation_repository.dart';

final class UpdatePresenceUseCase {
  const UpdatePresenceUseCase({
    required ConversationRepository conversationRepository,
    required DeviceIdentityRepository deviceIdentityRepository,
  }) : _conversationRepository = conversationRepository,
       _deviceIdentityRepository = deviceIdentityRepository;

  final ConversationRepository _conversationRepository;
  final DeviceIdentityRepository _deviceIdentityRepository;

  Future<Result<void>> execute({
    required String workspaceId,
    required ConversationPresence status,
  }) async {
    final device = await _deviceIdentityRepository.currentDevice();
    return _conversationRepository.updatePresence(
      workspaceId: workspaceId,
      deviceId: device.id,
      status: status,
      platform: device.platform,
    );
  }
}
