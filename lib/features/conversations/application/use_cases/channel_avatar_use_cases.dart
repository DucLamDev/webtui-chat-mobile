import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../profile/domain/entities/avatar_upload.dart';
import '../../../profile/domain/repositories/avatar_repository.dart';
import '../../domain/entities/channel_avatar_policy.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/channel_avatar_repository.dart';

/// Chọn ảnh (máy ảnh / thư viện, cắt vuông như ảnh đại diện cá nhân) rồi tải
/// lên làm ảnh nhóm. Người dùng huỷ chọn ảnh → `Success(null)`.
final class ChangeChannelAvatarUseCase {
  const ChangeChannelAvatarUseCase({
    required AvatarPickerRepository pickerRepository,
    required ChannelAvatarRepository channelAvatarRepository,
  }) : _pickerRepository = pickerRepository,
       _channelAvatarRepository = channelAvatarRepository;

  final AvatarPickerRepository _pickerRepository;
  final ChannelAvatarRepository _channelAvatarRepository;

  Future<Result<ConversationSummary?>> execute({
    required String workspaceId,
    required ConversationSummary channel,
    required AvatarPickerSource source,
  }) async {
    if (!canChangeChannelAvatar(channel)) {
      return const FailureResult(
        Failure(
          kind: FailureKind.forbidden,
          message: 'Bạn không có quyền đổi ảnh của nhóm này.',
          code: 'FORBIDDEN',
        ),
      );
    }
    final picked = await _pickerRepository.pick(source);
    switch (picked) {
      case FailureResult<PickedAvatar?>(failure: final failure):
        return FailureResult(
          Failure(
            kind: failure.kind,
            message: 'Không chọn được ảnh. Vui lòng thử ảnh khác.',
            code: failure.code,
            cause: failure.cause,
          ),
        );
      case Success<PickedAvatar?>(value: final avatar):
        if (avatar == null) return const Success(null);
        final uploaded = await _channelAvatarRepository.upload(
          workspaceId: workspaceId,
          channelId: channel.channelId,
          avatar: avatar,
        );
        return switch (uploaded) {
          Success<ConversationSummary>(value: final updated) => Success(
            updated,
          ),
          FailureResult<ConversationSummary>(failure: final failure) =>
            FailureResult(
              Failure(
                kind: failure.kind,
                message: channelAvatarFailureMessage(failure),
                code: failure.code,
                requestId: failure.requestId,
                cause: failure.cause,
              ),
            ),
        };
    }
  }
}

/// Lời báo lỗi dễ hiểu khi đổi ảnh nhóm. Máy chủ đã trả lời bằng tiếng Việt
/// thì giữ nguyên; lỗi từ proxy / mạng (không có mã) thì dịch theo mã HTTP.
String channelAvatarFailureMessage(Failure failure) {
  final status = switch (failure.cause) {
    DioException(:final response) => response?.statusCode,
    _ => null,
  };
  final code = failure.code?.trim() ?? '';
  if (code.isEmpty) {
    if (status == 413) return 'Ảnh quá lớn. Vui lòng chọn ảnh dưới 8 MB.';
    if (status == 415) return 'Chỉ hỗ trợ ảnh PNG, JPEG hoặc WebP.';
  }
  if (failure.kind == FailureKind.forbidden && code.isEmpty) {
    return 'Bạn không có quyền đổi ảnh của nhóm này.';
  }
  final message = failure.message.trim();
  return message.isEmpty
      ? 'Không đổi được ảnh nhóm. Vui lòng thử lại.'
      : message;
}
