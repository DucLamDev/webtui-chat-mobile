import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/moderation.dart';

final moderationControllerProvider = StateNotifierProvider.autoDispose
    .family<ModerationController, ModerationState, String>((ref, workspaceId) {
      return ModerationController._(
        workspaceId: workspaceId,
        createReport: ref.watch(createModerationReportUseCaseProvider).execute,
        listBlockedUsers: ref.watch(listBlockedUsersUseCaseProvider).execute,
        blockUser: ref.watch(blockUserUseCaseProvider).execute,
        unblockUser: ref.watch(unblockUserUseCaseProvider).execute,
      )..loadBlockedUsers();
    });

final class ModerationState {
  const ModerationState({
    this.blockedUsers = const [],
    this.isLoadingBlockedUsers = false,
    this.errorMessage,
  });

  final List<BlockedUser> blockedUsers;
  final bool isLoadingBlockedUsers;
  final String? errorMessage;

  Set<String> get blockedUserIds => blockedUsers
      .map((user) => user.blockedUserId.trim())
      .where((userId) => userId.isNotEmpty)
      .toSet();

  bool isBlocked(String userId) => blockedUserIds.contains(userId.trim());

  ModerationState copyWith({
    List<BlockedUser>? blockedUsers,
    bool? isLoadingBlockedUsers,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ModerationState(
      blockedUsers: blockedUsers ?? this.blockedUsers,
      isLoadingBlockedUsers:
          isLoadingBlockedUsers ?? this.isLoadingBlockedUsers,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

typedef _CreateReport =
    Future<Result<ModerationReport>> Function({
      required String workspaceId,
      required ModerationTargetType targetType,
      required String targetId,
      required ModerationReportReason reason,
      String? details,
    });

typedef _ListBlockedUsers =
    Future<Result<List<BlockedUser>>> Function(String workspaceId);

typedef _BlockUser =
    Future<Result<BlockedUser>> Function({
      required String workspaceId,
      required String userId,
      String? reason,
    });

typedef _UnblockUser =
    Future<Result<void>> Function({
      required String workspaceId,
      required String userId,
    });

final class ModerationController extends StateNotifier<ModerationState> {
  @visibleForTesting
  factory ModerationController.forTesting({
    required String workspaceId,
    required ModerationState initialState,
    Future<Result<List<BlockedUser>>> Function(String workspaceId)?
    listBlockedUsers,
  }) {
    Future<Result<ModerationReport>> unsupportedCreate({
      required String workspaceId,
      required ModerationTargetType targetType,
      required String targetId,
      required ModerationReportReason reason,
      String? details,
    }) => Future.error(UnsupportedError('Report is not configured in test.'));

    Future<Result<BlockedUser>> unsupportedBlock({
      required String workspaceId,
      required String userId,
      String? reason,
    }) => Future.error(UnsupportedError('Block is not configured in test.'));

    Future<Result<void>> unsupportedUnblock({
      required String workspaceId,
      required String userId,
    }) => Future.error(UnsupportedError('Unblock is not configured in test.'));

    return ModerationController._(
      workspaceId: workspaceId,
      createReport: unsupportedCreate,
      listBlockedUsers:
          listBlockedUsers ?? (_) async => Success(initialState.blockedUsers),
      blockUser: unsupportedBlock,
      unblockUser: unsupportedUnblock,
      initialState: initialState,
    );
  }

  ModerationController._({
    required String workspaceId,
    required _CreateReport createReport,
    required _ListBlockedUsers listBlockedUsers,
    required _BlockUser blockUser,
    required _UnblockUser unblockUser,
    ModerationState initialState = const ModerationState(),
  }) : _workspaceId = workspaceId.trim(),
       _createReport = createReport,
       _listBlockedUsers = listBlockedUsers,
       _blockUser = blockUser,
       _unblockUser = unblockUser,
       super(initialState);

  final String _workspaceId;
  final _CreateReport _createReport;
  final _ListBlockedUsers _listBlockedUsers;
  final _BlockUser _blockUser;
  final _UnblockUser _unblockUser;

  Future<void> loadBlockedUsers() async {
    if (_workspaceId.isEmpty || state.isLoadingBlockedUsers) {
      return;
    }
    state = state.copyWith(isLoadingBlockedUsers: true, clearError: true);
    final result = await _listBlockedUsers(_workspaceId);
    switch (result) {
      case Success<List<BlockedUser>>(value: final users):
        state = state.copyWith(
          blockedUsers: users,
          isLoadingBlockedUsers: false,
          clearError: true,
        );
      case FailureResult<List<BlockedUser>>(failure: final failure):
        state = state.copyWith(
          isLoadingBlockedUsers: false,
          errorMessage: failure.message,
        );
    }
  }

  Future<Result<ModerationReport>> report({
    required ModerationTargetType targetType,
    required String targetId,
    required ModerationReportReason reason,
    String? details,
  }) {
    return _createReport(
      workspaceId: _workspaceId,
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      details: details,
    );
  }

  Future<Result<BlockedUser>> block({
    required String userId,
    String? reason,
  }) async {
    final result = await _blockUser(
      workspaceId: _workspaceId,
      userId: userId,
      reason: reason,
    );
    if (result case Success<BlockedUser>(value: final blockedUser)) {
      state = state.copyWith(
        blockedUsers: [
          ...state.blockedUsers.where(
            (item) => item.blockedUserId != blockedUser.blockedUserId,
          ),
          blockedUser,
        ],
        clearError: true,
      );
    }
    return result;
  }

  Future<Result<void>> unblock(String userId) async {
    final result = await _unblockUser(
      workspaceId: _workspaceId,
      userId: userId,
    );
    if (result case Success<void>()) {
      state = state.copyWith(
        blockedUsers: state.blockedUsers
            .where((item) => item.blockedUserId != userId.trim())
            .toList(growable: false),
        clearError: true,
      );
    }
    return result;
  }
}
