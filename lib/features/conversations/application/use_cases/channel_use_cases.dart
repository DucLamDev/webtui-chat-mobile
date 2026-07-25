import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/conversation_repository.dart';

final class CreateChannelUseCase {
  const CreateChannelUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ConversationSummary>> execute({
    required String workspaceId,
    required String slug,
    required String name,
    required String description,
    required ChannelVisibility visibility,
  }) {
    final normalizedName = name.trim();
    final normalizedSlug = slug.trim().toLowerCase();
    if (normalizedName.isEmpty || normalizedSlug.isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Vui lòng nhập tên và slug của kênh.',
            code: 'CHANNEL_INPUT_REQUIRED',
          ),
        ),
      );
    }
    if (!RegExp(
      r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$',
    ).hasMatch(normalizedSlug)) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Slug chỉ gồm chữ thường, số và dấu gạch ngang.',
            code: 'CHANNEL_SLUG_INVALID',
          ),
        ),
      );
    }
    return _repository.createChannel(
      workspaceId: workspaceId,
      slug: normalizedSlug,
      name: normalizedName,
      description: description.trim(),
      visibility: visibility,
    );
  }
}

final class RequestJoinChannelUseCase {
  const RequestJoinChannelUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ChannelMember>> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.requestJoinChannel(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

final class OpenPrivateChannelSessionUseCase {
  const OpenPrivateChannelSessionUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ConversationSummary>> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.openPrivateSession(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

final class LoadChannelDetailUseCase {
  const LoadChannelDetailUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ChannelDetailData>> execute({
    required String workspaceId,
    required String channelId,
  }) async {
    final channelResult = await _repository.getChannel(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    if (channelResult case FailureResult<ConversationSummary>()) {
      return FailureResult(channelResult.failure);
    }

    final membersResult = await _repository.listMembers(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    final pinsResult = await _repository.listPins(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    final filesResult = await _repository.listFiles(workspaceId: workspaceId);

    return Success(
      ChannelDetailData(
        channel: channelResult.valueOrNull!,
        members: membersResult.valueOrNull ?? const [],
        pinnedMessages: pinsResult.valueOrNull ?? const [],
        files: filesResult.valueOrNull ?? const [],
        membersErrorMessage: membersResult.failureOrNull?.message,
        pinsErrorMessage: pinsResult.failureOrNull?.message,
        filesErrorMessage: filesResult.failureOrNull?.message,
      ),
    );
  }
}

final class InviteChannelMemberUseCase {
  const InviteChannelMemberUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ChannelMember>> execute({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) {
    return _repository.addMember(
      workspaceId: workspaceId,
      channelId: channelId,
      userId: userId,
    );
  }
}

final class LoadChannelJoinRequestsUseCase {
  const LoadChannelJoinRequestsUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<List<ChannelMember>>> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.listJoinRequests(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

final class ApproveChannelJoinRequestUseCase {
  const ApproveChannelJoinRequestUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<ChannelMember>> execute({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) {
    return _repository.approveJoinRequest(
      workspaceId: workspaceId,
      channelId: channelId,
      userId: userId,
    );
  }
}

final class RejectChannelJoinRequestUseCase {
  const RejectChannelJoinRequestUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) {
    return _repository.rejectJoinRequest(
      workspaceId: workspaceId,
      channelId: channelId,
      userId: userId,
    );
  }
}

final class ChannelDetailData {
  const ChannelDetailData({
    required this.channel,
    required this.members,
    required this.pinnedMessages,
    required this.files,
    this.membersErrorMessage,
    this.pinsErrorMessage,
    this.filesErrorMessage,
  });

  final ConversationSummary channel;
  final List<ChannelMember> members;
  final List<ChatMessage> pinnedMessages;
  final List<ChannelFile> files;
  final String? membersErrorMessage;
  final String? pinsErrorMessage;
  final String? filesErrorMessage;
}
