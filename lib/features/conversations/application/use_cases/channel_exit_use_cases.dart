import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/channel_exit.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/channel_exit_repository.dart';

/// Rời nhóm. Chỉ gọi máy chủ khi máy chủ đã cho rời ([canLeaveGroup]).
final class LeaveGroupUseCase {
  const LeaveGroupUseCase(this._repository);

  final ChannelExitRepository _repository;

  Future<Result<ChannelLeaveResult>> execute({
    required String workspaceId,
    required ConversationSummary channel,
  }) async {
    if (!canLeaveGroup(channel)) {
      return FailureResult(
        Failure(
          kind: FailureKind.forbidden,
          message: tr(
            'Bạn không rời được nhóm này.',
            'You can\'t leave this group.',
          ),
          code: 'FORBIDDEN',
        ),
      );
    }
    final result = await _repository.leave(
      workspaceId: workspaceId,
      channelId: channel.channelId,
    );
    return switch (result) {
      Success<ChannelLeaveResult>() => result,
      FailureResult<ChannelLeaveResult>(failure: final failure) =>
        FailureResult(
          failure.copyWith(
            message: channelExitFailureMessage(failure, leaving: true),
          ),
        ),
    };
  }
}

/// Xoá nhóm cho mọi thành viên (máy chủ lưu trữ). Chỉ gọi khi máy chủ đã cho
/// xoá ([canDeleteGroup]).
final class DeleteGroupUseCase {
  const DeleteGroupUseCase(this._repository);

  final ChannelExitRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required ConversationSummary channel,
  }) async {
    if (!canDeleteGroup(channel)) {
      return FailureResult(
        Failure(
          kind: FailureKind.forbidden,
          message: tr(
            'Bạn không có quyền xoá nhóm này.',
            'You don\'t have permission to delete this group.',
          ),
          code: 'FORBIDDEN',
        ),
      );
    }
    final result = await _repository.delete(
      workspaceId: workspaceId,
      channelId: channel.channelId,
    );
    return switch (result) {
      Success<void>() => result,
      FailureResult<void>(failure: final failure) => FailureResult(
        failure.copyWith(
          message: channelExitFailureMessage(failure, leaving: false),
        ),
      ),
    };
  }
}

/// Bỏ nhóm khỏi bộ nhớ đệm khi nhận sự kiện nhóm bị xoá / mình đã rời ở máy
/// khác.
final class ForgetGroupLocallyUseCase {
  const ForgetGroupLocallyUseCase(this._repository);

  final ChannelExitRepository _repository;

  Future<void> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.forgetLocally(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

/// Lời báo lỗi dễ hiểu khi rời / xoá nhóm. Máy chủ đã trả câu kèm mã lỗi thì
/// giữ nguyên; lỗi không có mã (proxy, mạng) thì nói theo loại lỗi.
String channelExitFailureMessage(Failure failure, {required bool leaving}) {
  final code = failure.code?.trim() ?? '';
  final message = failure.message.trim();
  if (code.isNotEmpty && message.isNotEmpty) return message;
  switch (failure.kind) {
    case FailureKind.forbidden:
      return leaving
          ? tr('Bạn không rời được nhóm này.', 'You can\'t leave this group.')
          : tr(
              'Bạn không có quyền xoá nhóm này.',
              'You don\'t have permission to delete this group.',
            );
    case FailureKind.notFound:
      return tr(
        'Nhóm không còn tồn tại hoặc bạn không còn trong nhóm.',
        'This group no longer exists or you\'re no longer in it.',
      );
    case FailureKind.conflict:
      return tr(
        'Nhóm vừa thay đổi. Vui lòng tải lại rồi thử lại.',
        'The group just changed. Reload and try again.',
      );
    case FailureKind.network:
    case FailureKind.timeout:
      return message.isNotEmpty
          ? message
          : tr(
              'Không kết nối được máy chủ. Vui lòng thử lại.',
              'Couldn\'t reach the server. Please try again.',
            );
    default:
      return leaving
          ? tr(
              'Không rời được nhóm. Vui lòng thử lại.',
              'Couldn\'t leave the group. Please try again.',
            )
          : tr(
              'Không xoá được nhóm. Vui lòng thử lại.',
              'Couldn\'t delete the group. Please try again.',
            );
  }
}
