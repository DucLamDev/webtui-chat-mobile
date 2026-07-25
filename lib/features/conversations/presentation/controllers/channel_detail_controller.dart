import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/channel_use_cases.dart';
import '../../application/use_cases/message_attachment_use_cases.dart';
import '../../domain/entities/channel_file.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';

final channelDetailControllerProvider = StateNotifierProvider.autoDispose
    .family<ChannelDetailController, ChannelDetailState, ChannelDetailScope>((
      ref,
      scope,
    ) {
      return ChannelDetailController(
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
      )..load();
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
    String? errorMessage,
    String? noticeMessage,
    String? membersErrorMessage,
    String? pinsErrorMessage,
    String? filesErrorMessage,
    String? mediaErrorMessage,
    bool clearError = false,
    bool clearNotice = false,
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
  }) : _loadChannelDetailUseCase = loadChannelDetailUseCase,
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
        state = state.copyWith(noticeMessage: 'Đã gửi yêu cầu tham gia kênh.');
      case FailureResult<ChannelMember>(failure: final failure):
        state = state.copyWith(
          isSubmitting: false,
          errorMessage: failure.message,
        );
    }
  }

  Future<void> inviteMember(String userId) async {
    if (userId.trim().isEmpty) {
      state = state.copyWith(errorMessage: 'Vui lòng nhập mã người dùng.');
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
          noticeMessage: 'Đã mời thành viên vào kênh.',
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
          noticeMessage: 'Đã duyệt yêu cầu tham gia.',
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
          noticeMessage: 'Đã từ chối yêu cầu tham gia.',
        );
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }
}
