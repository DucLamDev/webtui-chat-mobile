import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/repositories/conversation_local_cache.dart';
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
        FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: tr(
              'Vui lòng nhập tên và slug của nhóm.',
              'Enter the group name and slug.',
            ),
            code: 'CHANNEL_INPUT_REQUIRED',
          ),
        ),
      );
    }
    if (!RegExp(
      r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$',
    ).hasMatch(normalizedSlug)) {
      return Future.value(
        FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: tr(
              'Slug chỉ gồm chữ thường, số và dấu gạch ngang.',
              'The slug can only contain lowercase letters, numbers and hyphens.',
            ),
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

/// Thành viên phòng (kể cả người đã rời) để hiện tên / ảnh người gửi tin.
final class ListChannelMembersUseCase {
  const ListChannelMembersUseCase(this._repository);

  final ConversationRepository _repository;

  Future<Result<List<ChannelMember>>> execute({
    required String workspaceId,
    required String channelId,
  }) {
    return _repository.listMembers(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  }
}

final class LoadChannelDetailUseCase {
  const LoadChannelDetailUseCase(
    this._repository, {
    ChannelMemberCache? memberCache,
    ConversationListCacheReader? listCache,
  }) : _memberCache = memberCache,
       _listCache = listCache;

  final ConversationRepository _repository;
  final ChannelMemberCache? _memberCache;
  final ConversationListCacheReader? _listCache;

  /// Thông tin nhóm + thành viên đã lưu trên máy để hiện ngay khi mở màn
  /// (trước khi gọi máy chủ). `null` khi chưa lưu nhóm này.
  Future<ChannelDetailData?> readCached({
    required String workspaceId,
    required String channelId,
  }) async {
    final listCache = _listCache;
    if (listCache == null) return null;
    ConversationSummary? channel;
    try {
      final lists = await Future.wait([
        listCache.readCachedChannels(workspaceId: workspaceId),
        listCache.readCachedDirectConversations(workspaceId: workspaceId),
      ]);
      for (final item in [...?lists[0], ...?lists[1]]) {
        if (item.channelId == channelId || item.id == channelId) {
          channel = item;
          break;
        }
      }
    } on Object {
      return null;
    }
    if (channel == null) return null;
    final members = await _readMembersSafely(
      _memberCache,
      workspaceId,
      channelId,
    );
    return ChannelDetailData(
      channel: channel,
      members: members ?? const [],
      pinnedMessages: const [],
      files: const [],
    );
  }

  Future<Result<ChannelDetailData>> execute({
    required String workspaceId,
    required String channelId,
  }) async {
    final channelResult = await _repository.getChannel(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    if (channelResult case FailureResult<ConversationSummary>(
      failure: final failure,
    )) {
      // Không còn quyền / nhóm đã xoá: bỏ thành viên đã lưu của nhóm.
      if (failure.kind == FailureKind.forbidden ||
          failure.kind == FailureKind.notFound) {
        await _removeMembersSafely(_memberCache, workspaceId, channelId);
      }
      return FailureResult(failure);
    }

    var membersResult = await _repository.listMembers(
      workspaceId: workspaceId,
      channelId: channelId,
    );
    switch (membersResult) {
      case Success<List<ChannelMember>>(value: final members):
        await _saveMembersSafely(_memberCache, workspaceId, channelId, members);
      case FailureResult<List<ChannelMember>>(failure: final failure):
        // Mất mạng giữa chừng: dùng thành viên đã lưu thay vì báo lỗi.
        if (failure.kind == FailureKind.network ||
            failure.kind == FailureKind.timeout) {
          final cached = await _readMembersSafely(
            _memberCache,
            workspaceId,
            channelId,
          );
          if (cached != null) membersResult = Success(cached);
        }
    }
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
  const InviteChannelMemberUseCase(
    this._repository, {
    ChannelMemberCache? memberCache,
  }) : _memberCache = memberCache;

  final ConversationRepository _repository;
  final ChannelMemberCache? _memberCache;

  /// Mời thành viên; thành công thì thêm vào danh sách đã lưu trên máy.
  Future<Result<ChannelMember>> execute({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    final result = await _repository.addMember(
      workspaceId: workspaceId,
      channelId: channelId,
      userId: userId,
    );
    if (result case Success<ChannelMember>(value: final member)) {
      await _upsertMemberSafely(_memberCache, workspaceId, channelId, member);
    }
    return result;
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
  const ApproveChannelJoinRequestUseCase(
    this._repository, {
    ChannelMemberCache? memberCache,
  }) : _memberCache = memberCache;

  final ConversationRepository _repository;
  final ChannelMemberCache? _memberCache;

  /// Duyệt yêu cầu; thành công thì thêm người đó vào danh sách đã lưu.
  Future<Result<ChannelMember>> execute({
    required String workspaceId,
    required String channelId,
    required String userId,
  }) async {
    final result = await _repository.approveJoinRequest(
      workspaceId: workspaceId,
      channelId: channelId,
      userId: userId,
    );
    if (result case Success<ChannelMember>(value: final member)) {
      await _upsertMemberSafely(_memberCache, workspaceId, channelId, member);
    }
    return result;
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

// Bộ đệm thành viên chỉ là bản sao: lỗi đọc / ghi trên máy không được làm
// hỏng kết quả máy chủ trả về.

Future<List<ChannelMember>?> _readMembersSafely(
  ChannelMemberCache? cache,
  String workspaceId,
  String channelId,
) async {
  if (cache == null) return null;
  try {
    return await cache.readMembers(
      workspaceId: workspaceId,
      channelId: channelId,
    );
  } on Object {
    return null;
  }
}

Future<void> _saveMembersSafely(
  ChannelMemberCache? cache,
  String workspaceId,
  String channelId,
  List<ChannelMember> members,
) async {
  if (cache == null) return;
  try {
    await cache.saveMembers(
      workspaceId: workspaceId,
      channelId: channelId,
      members: members,
    );
  } on Object {
    return;
  }
}

Future<void> _upsertMemberSafely(
  ChannelMemberCache? cache,
  String workspaceId,
  String channelId,
  ChannelMember member,
) async {
  if (cache == null) return;
  try {
    await cache.upsertMember(
      workspaceId: workspaceId,
      channelId: channelId,
      member: member,
    );
  } on Object {
    return;
  }
}

Future<void> _removeMembersSafely(
  ChannelMemberCache? cache,
  String workspaceId,
  String channelId,
) async {
  if (cache == null) return;
  try {
    await cache.removeMembers(workspaceId: workspaceId, channelId: channelId);
  } on Object {
    return;
  }
}
