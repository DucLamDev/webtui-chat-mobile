import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../../profile/domain/entities/avatar_upload.dart';
import '../../application/use_cases/channel_avatar_use_cases.dart';
import '../../application/use_cases/channel_use_cases.dart';
import '../../application/use_cases/message_attachment_use_cases.dart';
import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';

/// Tăng mỗi khi nhận `ChannelUpdated` cho kênh (theo `channel_id`): màn
/// thông tin kênh đang mở tải lại thông tin kênh mà không hiện màn chờ.
final channelUpdatedTickProvider = StateProvider.family<int, String>(
  (ref, channelId) => 0,
);

final channelDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<ChannelDetailController, ChannelDetailState, ChannelDetailScope>((
      ref,
      scope,
    ) {
      final controller = ChannelDetailController(
        scope: scope,
        loadChannelDetailUseCase: ref.watch(loadChannelDetailUseCaseProvider),
        requestJoinChannelUseCase: ref.watch(requestJoinChannelUseCaseProvider),
        inviteChannelMemberUseCase: ref.watch(
          inviteChannelMemberUseCaseProvider,
        ),
        loadChannelJoinRequestsUseCase: ref.watch(
          loadChannelJoinRequestsUseCaseProvider,
        ),
        approveChannelJoinRequestUseCase: ref.watch(
          approveChannelJoinRequestUseCaseProvider,
        ),
        rejectChannelJoinRequestUseCase: ref.watch(
          rejectChannelJoinRequestUseCaseProvider,
        ),
        listChannelMediaUseCase: ref.watch(listChannelMediaUseCaseProvider),
        changeChannelAvatarUseCase: ref.watch(
          changeChannelAvatarUseCaseProvider,
        ),
      )..load();
      ref.listen<int>(
        channelUpdatedTickProvider(scope.channelId),
        (_, _) => controller.reloadChannelSilently(),
      );
      return controller;
    });

final class ChannelDetailScope {
  const ChannelDetailScope({
    required this.workspaceId,
    required this.channelId,
    required this.initialTitle,
  });

  final String workspaceId;
  final String channelId;
  final String initialTitle;

  @override
  bool operator ==(Object other) {
    return other is ChannelDetailScope &&
        other.workspaceId == workspaceId &&
        other.channelId == channelId &&
        other.initialTitle == initialTitle;
  }

  @override
  int get hashCode => Object.hash(workspaceId, channelId, initialTitle);
}

final class ChannelDetailState {
  const ChannelDetailState({
    required this.scope,
    this.channel,
    this.members = const [],
    this.pinnedMessages = const [],
    this.files = const [],
    this.mediaAttachments = const [],
    this.joinRequests = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.isUpdatingAvatar = false,
    this.avatarErrorMessage,
    this.errorMessage,
    this.noticeMessage,
    this.membersErrorMessage,
    this.pinsErrorMessage,
    this.filesErrorMessage,
    this.mediaErrorMessage,
  });

  final ChannelDetailScope scope;
  final ConversationSummary? channel;
  final List<ChannelMember> members;
  final List<ChatMessage> pinnedMessages;
  final List<ChannelFile> files;
  final List<MessageAttachment> mediaAttachments;
  final List<ChannelMember> joinRequests;
  final bool isLoading;
  final bool isSubmitting;

  /// Đang tải ảnh nhóm mới lên.
  final bool isUpdatingAvatar;

  /// Lỗi đổi ảnh nhóm (hiện riêng, không thay cả màn bằng trạng thái lỗi).
  final String? avatarErrorMessage;
  final String? errorMessage;
  final String? noticeMessage;
  final String? membersErrorMessage;
  final String? pinsErrorMessage;
  final String? filesErrorMessage;
  final String? mediaErrorMessage;

  String get title => channel?.title ?? scope.initialTitle;

  ChannelDetailState copyWith({
    ConversationSummary? channel,
    List<ChannelMember>? members,
    List<ChatMessage>? pinnedMessages,
    List<ChannelFile>? files,
    List<MessageAttachment>? mediaAttachments,
    List<ChannelMember>? joinRequests,
    bool? isLoading,
    bool? isSubmitting,
    bool? isUpdatingAvatar,
    String? avatarErrorMessage,
    String? errorMessage,
    String? noticeMessage,
    String? membersErrorMessage,
    String? pinsErrorMessage,
    String? filesErrorMessage,
    String? mediaErrorMessage,
    bool clearError = false,
    bool clearNotice = false,
    bool clearAvatarError = false,
  }) {
    return ChannelDetailState(
      scope: scope,
      channel: channel ?? this.channel,
      members: members ?? this.members,
      pinnedMessages: pinnedMessages ?? this.pinnedMessages,
      files: files ?? this.files,
      mediaAttachments: mediaAttachments ?? this.mediaAttachments,
      joinRequests: joinRequests ?? this.joinRequests,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isUpdatingAvatar: isUpdatingAvatar ?? this.isUpdatingAvatar,
      avatarErrorMessage: clearAvatarError
          ? null
          : avatarErrorMessage ?? this.avatarErrorMessage,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      noticeMessage: clearNotice ? null : noticeMessage ?? this.noticeMessage,
      membersErrorMessage: membersErrorMessage ?? this.membersErrorMessage,
      pinsErrorMessage: pinsErrorMessage ?? this.pinsErrorMessage,
      filesErrorMessage: filesErrorMessage ?? this.filesErrorMessage,
      mediaErrorMessage: mediaErrorMessage ?? this.mediaErrorMessage,
    );
  }
}

final class ChannelDetailController extends StateNotifier<ChannelDetailState> {
  ChannelDetailController({
    required ChannelDetailScope scope,
    required LoadChannelDetailUseCase loadChannelDetailUseCase,
    required RequestJoinChannelUseCase requestJoinChannelUseCase,
    required InviteChannelMemberUseCase inviteChannelMemberUseCase,
    required LoadChannelJoinRequestsUseCase loadChannelJoinRequestsUseCase,
    required ApproveChannelJoinRequestUseCase approveChannelJoinRequestUseCase,
    required RejectChannelJoinRequestUseCase rejectChannelJoinRequestUseCase,
    required ListChannelMediaUseCase listChannelMediaUseCase,
    ChangeChannelAvatarUseCase? changeChannelAvatarUseCase,
  }) : _changeChannelAvatarUseCase = changeChannelAvatarUseCase,
       _loadChannelDetailUseCase = loadChannelDetailUseCase,
       _requestJoinChannelUseCase = requestJoinChannelUseCase,
       _inviteChannelMemberUseCase = inviteChannelMemberUseCase,
       _loadChannelJoinRequestsUseCase = loadChannelJoinRequestsUseCase,
       _approveChannelJoinRequestUseCase = approveChannelJoinRequestUseCase,
       _rejectChannelJoinRequestUseCase = rejectChannelJoinRequestUseCase,
       _listChannelMediaUseCase = listChannelMediaUseCase,
       super(ChannelDetailState(scope: scope));

  final LoadChannelDetailUseCase _loadChannelDetailUseCase;
  final RequestJoinChannelUseCase _requestJoinChannelUseCase;
  final InviteChannelMemberUseCase _inviteChannelMemberUseCase;
  final LoadChannelJoinRequestsUseCase _loadChannelJoinRequestsUseCase;
  final ApproveChannelJoinRequestUseCase _approveChannelJoinRequestUseCase;
  final RejectChannelJoinRequestUseCase _rejectChannelJoinRequestUseCase;
  final ListChannelMediaUseCase _listChannelMediaUseCase;
  final ChangeChannelAvatarUseCase? _changeChannelAvatarUseCase;

  /// Tải lại thông tin kênh và thành viên (sau `ChannelUpdated` /
  /// `ChannelMemberLeft`) mà không hiện màn chờ;
  /// đang tải ảnh lên / đang tải lần đầu thì bỏ qua (kết quả đó mới hơn).
  Future<void> reloadChannelSilently() async {
    if (state.isLoading || state.isUpdatingAvatar) return;
    final result = await _loadChannelDetailUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    if (!mounted || state.isUpdatingAvatar) return;
    if (result case Success<ChannelDetailData>(value: final data)) {
      // Danh sách thành viên cũng làm mới (có người vừa rời nhóm); tải lỗi thì
      // giữ danh sách đang hiện.
      state = state.copyWith(
        channel: data.channel,
        members: data.membersErrorMessage == null ? data.members : null,
      );
    }
  }

  /// Chọn ảnh rồi đổi ảnh nhóm. Trả `true` khi đã đổi xong (để màn làm mới
  /// danh sách hội thoại).
  Future<bool> changeAvatar(AvatarPickerSource source) async {
    final channel = state.channel;
    final useCase = _changeChannelAvatarUseCase;
    if (channel == null || useCase == null || state.isUpdatingAvatar) {
      return false;
    }
    state = state.copyWith(
      isUpdatingAvatar: true,
      clearAvatarError: true,
      clearNotice: true,
    );
    final result = await useCase.execute(
      workspaceId: state.scope.workspaceId,
      channel: channel,
      source: source,
    );
    if (!mounted) return false;
    switch (result) {
      case Success<ConversationSummary?>(value: final updated):
        if (updated == null) {
          state = state.copyWith(isUpdatingAvatar: false);
          return false;
        }
        state = state.copyWith(
          channel: _mergeChannel(channel, updated),
          isUpdatingAvatar: false,
          noticeMessage: tr('Đã đổi ảnh nhóm.', 'Group photo updated.'),
        );
        return true;
      case FailureResult<ConversationSummary?>(failure: final failure):
        state = state.copyWith(
          isUpdatingAvatar: false,
          avatarErrorMessage: failure.message,
        );
        return false;
    }
  }

  /// Máy chủ trả DTO kênh đầy đủ; nếu thiếu trạng thái thành viên (máy chủ cũ)
  /// thì giữ thông tin đang có, chỉ thay ảnh.
  static ConversationSummary _mergeChannel(
    ConversationSummary current,
    ConversationSummary updated,
  ) {
    if (updated.membershipStatus != MembershipStatus.none) return updated;
    return ConversationSummary(
      id: current.id,
      workspaceId: current.workspaceId,
      channelId: current.channelId,
      kind: current.kind,
      title: current.title,
      preview: current.preview,
      updatedAt: current.updatedAt,
      avatarLabel: current.avatarLabel,
      avatarUrl: updated.avatarUrl,
      peerUserId: current.peerUserId,
      unreadCount: current.unreadCount,
      favorite: current.favorite,
      muted: current.muted,
      memberCount: current.memberCount,
      participantIds: current.participantIds,
      channelVisibility: current.channelVisibility,
      membershipStatus: current.membershipStatus,
      canManage: current.canManage,
      canLeave: current.canLeave,
      canDelete: current.canDelete,
      privateSessionMode: current.privateSessionMode,
      isAutomation: current.isAutomation,
      noticeBot: current.noticeBot,
      slug: current.slug,
      lastMessageAt: current.lastMessageAt,
    );
  }

  Future<void> load() async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearNotice: true,
    );
    final result = await _loadChannelDetailUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    switch (result) {
      case Success<ChannelDetailData>(value: final data):
        final mediaResult = await _listChannelMediaUseCase.execute(
          workspaceId: state.scope.workspaceId,
          channelId: state.scope.channelId,
        );
        state = state.copyWith(
          channel: data.channel,
          members: data.members,
          pinnedMessages: data.pinnedMessages,
          files: data.files,
          membersErrorMessage: data.membersErrorMessage,
          pinsErrorMessage: data.pinsErrorMessage,
          filesErrorMessage: data.filesErrorMessage,
          mediaAttachments: mediaResult.valueOrNull ?? const [],
          mediaErrorMessage: mediaResult.failureOrNull?.message,
          isLoading: false,
          clearError: true,
        );
        await loadJoinRequests();
      case FailureResult<ChannelDetailData>(failure: final failure):
        state = state.copyWith(isLoading: false, errorMessage: failure.message);
    }
  }

  Future<void> requestJoin() async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    final result = await _requestJoinChannelUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    switch (result) {
      case Success<ChannelMember>():
        state = state.copyWith(isSubmitting: false);
        await load();
        state = state.copyWith(
          noticeMessage: tr(
            'Đã gửi yêu cầu tham gia kênh.',
            'Join request sent.',
          ),
        );
      case FailureResult<ChannelMember>(failure: final failure):
        state = state.copyWith(
          isSubmitting: false,
          errorMessage: failure.message,
        );
    }
  }

  Future<void> inviteMember(String userId) async {
    if (userId.trim().isEmpty) {
      state = state.copyWith(
        errorMessage: tr(
          'Vui lòng nhập mã người dùng.',
          'Please enter a user ID.',
        ),
      );
      return;
    }
    state = state.copyWith(isSubmitting: true, clearError: true);
    final result = await _inviteChannelMemberUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      userId: userId.trim(),
    );
    switch (result) {
      case Success<ChannelMember>(value: final member):
        state = state.copyWith(
          isSubmitting: false,
          members: [...state.members, member],
          noticeMessage: tr('Đã mời thành viên vào kênh.', 'Member invited.'),
        );
      case FailureResult<ChannelMember>(failure: final failure):
        state = state.copyWith(
          isSubmitting: false,
          errorMessage: failure.message,
        );
    }
  }

  Future<void> loadJoinRequests() async {
    final result = await _loadChannelJoinRequestsUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
    );
    if (result case Success<List<ChannelMember>>(value: final requests)) {
      state = state.copyWith(joinRequests: requests);
    }
  }

  Future<void> approveJoinRequest(String userId) async {
    final result = await _approveChannelJoinRequestUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      userId: userId,
    );
    switch (result) {
      case Success<ChannelMember>(value: final member):
        state = state.copyWith(
          members: [...state.members, member],
          joinRequests: state.joinRequests
              .where((request) => request.userId != userId)
              .toList(growable: false),
          noticeMessage: tr(
            'Đã duyệt yêu cầu tham gia.',
            'Join request approved.',
          ),
        );
      case FailureResult<ChannelMember>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> rejectJoinRequest(String userId) async {
    final result = await _rejectChannelJoinRequestUseCase.execute(
      workspaceId: state.scope.workspaceId,
      channelId: state.scope.channelId,
      userId: userId,
    );
    switch (result) {
      case Success<void>():
        state = state.copyWith(
          joinRequests: state.joinRequests
              .where((request) => request.userId != userId)
              .toList(growable: false),
          noticeMessage: tr(
            'Đã từ chối yêu cầu tham gia.',
            'Join request declined.',
          ),
        );
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }
}
