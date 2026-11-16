import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/channel_exit_use_cases.dart';
import 'package:webtui_chat/features/conversations/domain/entities/channel_exit.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/channel_exit_repository.dart';

ConversationSummary _group({
  ConversationKind kind = ConversationKind.channel,
  ChannelVisibility visibility = ChannelVisibility.private,
  bool canLeave = true,
  bool canDelete = true,
  bool privateSessionMode = false,
  bool noticeBot = false,
  bool isAutomation = false,
}) {
  return ConversationSummary(
    id: 'ch-1',
    workspaceId: 'ws',
    channelId: 'ch-1',
    kind: kind,
    title: 'Nhóm A',
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 16),
    channelVisibility: visibility,
    membershipStatus: MembershipStatus.active,
    canLeave: canLeave,
    canDelete: canDelete,
    privateSessionMode: privateSessionMode,
    noticeBot: noticeBot,
    isAutomation: isAutomation,
  );
}

void main() {
  group('canLeaveGroup / canDeleteGroup', () {
    test('nhóm thường: theo cờ máy chủ', () {
      expect(canLeaveGroup(_group()), isTrue);
      expect(canDeleteGroup(_group()), isTrue);
      expect(canLeaveGroup(_group(canLeave: false)), isFalse);
      expect(canDeleteGroup(_group(canDelete: false)), isFalse);
      expect(canLeaveGroup(null), isFalse);
      expect(canDeleteGroup(null), isFalse);
    });

    test('máy chủ cũ (không có cờ) → ẩn cả hai', () {
      final old = ConversationSummary(
        id: 'x',
        workspaceId: 'ws',
        channelId: 'x',
        kind: ConversationKind.channel,
        title: 'Nhóm',
        preview: '',
        updatedAt: DateTime.utc(2026, 11, 16),
        channelVisibility: ChannelVisibility.private,
        membershipStatus: MembershipStatus.active,
        canManage: true,
      );
      expect(canLeaveGroup(old), isFalse);
      expect(canDeleteGroup(old), isFalse);
    });

    test('chat 1-1, phiên bot riêng, bot thông báo, automation: không nút', () {
      for (final channel in [
        _group(
          kind: ConversationKind.direct,
          visibility: ChannelVisibility.direct,
        ),
        _group(privateSessionMode: true),
        _group(noticeBot: true),
        _group(isAutomation: true),
      ]) {
        expect(canLeaveGroup(channel), isFalse);
        expect(canDeleteGroup(channel), isFalse);
      }
    });

    test('kênh công khai: không rời (chỉ nhóm), quản trị vẫn xoá được', () {
      final public = _group(visibility: ChannelVisibility.public);
      expect(canLeaveGroup(public), isFalse);
      expect(canDeleteGroup(public), isTrue);
    });
  });

  group('LeaveGroupUseCase', () {
    test('gọi rời đúng kênh, trả kết quả của máy chủ', () async {
      final repo = _FakeRepository(
        leaveResult: const Success(
          ChannelLeaveResult(channelId: 'ch-1', archived: true),
        ),
      );
      final result = await LeaveGroupUseCase(
        repo,
      ).execute(workspaceId: 'ws', channel: _group());

      expect(repo.calls, ['leave ws/ch-1']);
      expect(result.valueOrNull?.archived, isTrue);
    });

    test('không có quyền rời thì không gọi máy chủ', () async {
      final repo = _FakeRepository();
      final result = await LeaveGroupUseCase(
        repo,
      ).execute(workspaceId: 'ws', channel: _group(canLeave: false));

      expect(repo.calls, isEmpty);
      expect(result.failureOrNull?.kind, FailureKind.forbidden);
      expect(result.failureOrNull?.message, 'Bạn không rời được nhóm này.');
    });

    test('lỗi máy chủ có mã: giữ câu của máy chủ', () async {
      final repo = _FakeRepository(
        leaveResult: const FailureResult(
          Failure(
            kind: FailureKind.conflict,
            message: 'Bạn đã rời nhóm này rồi.',
            code: 'CHANNEL_MEMBER_NOT_ACTIVE',
          ),
        ),
      );
      final result = await LeaveGroupUseCase(
        repo,
      ).execute(workspaceId: 'ws', channel: _group());

      expect(result.failureOrNull?.message, 'Bạn đã rời nhóm này rồi.');
    });

    test('lỗi không có mã (proxy): câu dễ hiểu theo loại lỗi', () async {
      final repo = _FakeRepository(
        leaveResult: const FailureResult(
          Failure(kind: FailureKind.notFound, message: 'Not Found'),
        ),
      );
      final result = await LeaveGroupUseCase(
        repo,
      ).execute(workspaceId: 'ws', channel: _group());

      expect(
        result.failureOrNull?.message,
        'Nhóm không còn tồn tại hoặc bạn không còn trong nhóm.',
      );
    });
  });

  group('DeleteGroupUseCase', () {
    test('gọi xoá đúng kênh', () async {
      final repo = _FakeRepository();
      final result = await DeleteGroupUseCase(
        repo,
      ).execute(workspaceId: 'ws', channel: _group());

      expect(repo.calls, ['delete ws/ch-1']);
      expect(result, isA<Success<void>>());
    });

    test('không có quyền xoá thì không gọi máy chủ', () async {
      final repo = _FakeRepository();
      final result = await DeleteGroupUseCase(
        repo,
      ).execute(workspaceId: 'ws', channel: _group(canDelete: false));

      expect(repo.calls, isEmpty);
      expect(result.failureOrNull?.message, 'Bạn không có quyền xoá nhóm này.');
    });

    test('403 không mã: báo không có quyền xoá', () async {
      final repo = _FakeRepository(
        deleteResult: const FailureResult(
          Failure(kind: FailureKind.forbidden, message: 'Forbidden'),
        ),
      );
      final result = await DeleteGroupUseCase(
        repo,
      ).execute(workspaceId: 'ws', channel: _group());

      expect(result.failureOrNull?.message, 'Bạn không có quyền xoá nhóm này.');
    });

    test('lỗi máy chủ 500 không mã: mời thử lại', () async {
      final repo = _FakeRepository(
        deleteResult: const FailureResult(
          Failure(kind: FailureKind.server, message: 'Máy chủ đang gặp lỗi.'),
        ),
      );
      final result = await DeleteGroupUseCase(
        repo,
      ).execute(workspaceId: 'ws', channel: _group());

      expect(
        result.failureOrNull?.message,
        'Không xoá được nhóm. Vui lòng thử lại.',
      );
    });
  });

  test('ForgetGroupLocallyUseCase: bỏ nhóm khỏi bộ nhớ đệm', () async {
    final repo = _FakeRepository();
    await ForgetGroupLocallyUseCase(
      repo,
    ).execute(workspaceId: 'ws', channelId: 'ch-9');
    expect(repo.calls, ['forget ws/ch-9']);
  });
}

final class _FakeRepository implements ChannelExitRepository {
  _FakeRepository({
    this.leaveResult = const Success(
      ChannelLeaveResult(channelId: 'ch-1', archived: false),
    ),
    this.deleteResult = const Success<void>(null),
  });

  final Result<ChannelLeaveResult> leaveResult;
  final Result<void> deleteResult;
  final calls = <String>[];

  @override
  Future<Result<ChannelLeaveResult>> leave({
    required String workspaceId,
    required String channelId,
  }) async {
    calls.add('leave $workspaceId/$channelId');
    return leaveResult;
  }

  @override
  Future<Result<void>> delete({
    required String workspaceId,
    required String channelId,
  }) async {
    calls.add('delete $workspaceId/$channelId');
    return deleteResult;
  }

  @override
  Future<void> forgetLocally({
    required String workspaceId,
    required String channelId,
  }) async {
    calls.add('forget $workspaceId/$channelId');
  }
}
