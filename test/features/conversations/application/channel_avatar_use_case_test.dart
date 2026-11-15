import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_avatar_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/channel_avatar_repository.dart';
import 'package:webtui_chat/features/profile/domain/entities/avatar_upload.dart';
import 'package:webtui_chat/features/profile/domain/repositories/avatar_repository.dart';

ConversationSummary _group({
  ChannelVisibility visibility = ChannelVisibility.private,
  String? avatarUrl,
}) {
  return ConversationSummary(
    id: 'ch-1',
    workspaceId: 'ws',
    channelId: 'ch-1',
    kind: ConversationKind.channel,
    title: 'Nhóm A',
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 15),
    channelVisibility: visibility,
    membershipStatus: MembershipStatus.active,
    avatarUrl: avatarUrl,
  );
}

const _picked = PickedAvatar(
  path: '/tmp/x.png',
  fileName: 'x.png',
  mimeType: 'image/png',
);

void main() {
  test('thành viên nhóm: chọn ảnh rồi tải lên đúng kênh', () async {
    final repo = _FakeChannelAvatarRepository(
      Success(_group(avatarUrl: '/api/v1/channels/avatars/z/ch-1/a.jpg')),
    );
    final useCase = ChangeChannelAvatarUseCase(
      pickerRepository: _FakePicker(const Success(_picked)),
      channelAvatarRepository: repo,
    );

    final result = await useCase.execute(
      workspaceId: 'ws',
      channel: _group(),
      source: AvatarPickerSource.gallery,
    );

    expect(
      result.valueOrNull?.avatarUrl,
      '/api/v1/channels/avatars/z/ch-1/a.jpg',
    );
    expect(repo.uploadedChannelId, 'ch-1');
    expect(repo.uploadedWorkspaceId, 'ws');
    expect(repo.uploadedAvatar?.path, '/tmp/x.png');
  });

  test('huỷ chọn ảnh: không tải lên', () async {
    final repo = _FakeChannelAvatarRepository(Success(_group()));
    final useCase = ChangeChannelAvatarUseCase(
      pickerRepository: _FakePicker(const Success(null)),
      channelAvatarRepository: repo,
    );

    final result = await useCase.execute(
      workspaceId: 'ws',
      channel: _group(),
      source: AvatarPickerSource.camera,
    );

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, isNull);
    expect(repo.uploadedChannelId, isNull);
  });

  test(
    'kênh công khai không quản lý: báo không có quyền, không mở bộ chọn',
    () async {
      final picker = _FakePicker(const Success(_picked));
      final useCase = ChangeChannelAvatarUseCase(
        pickerRepository: picker,
        channelAvatarRepository: _FakeChannelAvatarRepository(
          Success(_group()),
        ),
      );

      final result = await useCase.execute(
        workspaceId: 'ws',
        channel: _group(visibility: ChannelVisibility.public),
        source: AvatarPickerSource.gallery,
      );

      expect(result.failureOrNull?.kind, FailureKind.forbidden);
      expect(picker.calls, 0);
    },
  );

  test('máy chủ trả lỗi có mã: giữ lời báo tiếng Việt của máy chủ', () async {
    final useCase = ChangeChannelAvatarUseCase(
      pickerRepository: _FakePicker(const Success(_picked)),
      channelAvatarRepository: _FakeChannelAvatarRepository(
        const FailureResult(
          Failure(
            kind: FailureKind.unknown,
            message: 'Ảnh tối đa 8 MB.',
            code: 'AVATAR_TOO_LARGE',
          ),
        ),
      ),
    );

    final result = await useCase.execute(
      workspaceId: 'ws',
      channel: _group(),
      source: AvatarPickerSource.gallery,
    );

    expect(result.failureOrNull?.message, 'Ảnh tối đa 8 MB.');
  });

  test('413 từ proxy (không có mã): báo ảnh quá lớn', () {
    final requestOptions = RequestOptions(path: '/x');
    final message = channelAvatarFailureMessage(
      Failure(
        kind: FailureKind.unknown,
        message: 'Yêu cầu không thành công.',
        cause: DioException(
          requestOptions: requestOptions,
          response: Response<void>(
            requestOptions: requestOptions,
            statusCode: 413,
          ),
        ),
      ),
    );
    expect(message, contains('8 MB'));
  });
}

final class _FakePicker implements AvatarPickerRepository {
  _FakePicker(this.result);

  final Result<PickedAvatar?> result;
  int calls = 0;

  @override
  Future<Result<PickedAvatar?>> pick(AvatarPickerSource source) async {
    calls++;
    return result;
  }
}

final class _FakeChannelAvatarRepository implements ChannelAvatarRepository {
  _FakeChannelAvatarRepository(this.result);

  final Result<ConversationSummary> result;
  String? uploadedWorkspaceId;
  String? uploadedChannelId;
  PickedAvatar? uploadedAvatar;

  @override
  Future<Result<ConversationSummary>> upload({
    required String workspaceId,
    required String channelId,
    required PickedAvatar avatar,
  }) async {
    uploadedWorkspaceId = workspaceId;
    uploadedChannelId = channelId;
    uploadedAvatar = avatar;
    return result;
  }
}
