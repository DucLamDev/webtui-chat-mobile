import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/create_group_use_case.dart';
import '../../domain/entities/conversation_summary.dart';

final createGroupUseCaseProvider = Provider<CreateGroupUseCase>((ref) {
  return CreateGroupUseCase(ref.watch(conversationRepositoryProvider));
});

final channelCreateControllerProvider = StateNotifierProvider.autoDispose
    .family<ChannelCreateController, ChannelCreateState, String>((
      ref,
      workspaceId,
    ) {
      return ChannelCreateController(
        workspaceId: workspaceId,
        createGroupUseCase: ref.watch(createGroupUseCaseProvider),
      );
    });

final class ChannelCreateState {
  const ChannelCreateState({
    required this.workspaceId,
    this.selectedUserIds = const [],
    this.isSubmitting = false,
    this.errorMessage,
  });

  final String workspaceId;

  /// Người đã chọn theo thứ tự chọn.
  final List<String> selectedUserIds;
  final bool isSubmitting;
  final String? errorMessage;

  ChannelCreateState copyWith({
    List<String>? selectedUserIds,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChannelCreateState(
      workspaceId: workspaceId,
      selectedUserIds: selectedUserIds ?? this.selectedUserIds,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Kết quả tạo nhóm cho màn hình: nhóm vừa tạo và số người không thêm được.
final class GroupCreateOutcome {
  const GroupCreateOutcome({required this.channel, this.failedCount = 0});

  final ConversationSummary channel;
  final int failedCount;
}

final class ChannelCreateController extends StateNotifier<ChannelCreateState> {
  ChannelCreateController({
    required String workspaceId,
    required CreateGroupUseCase createGroupUseCase,
  }) : _createGroupUseCase = createGroupUseCase,
       super(ChannelCreateState(workspaceId: workspaceId));

  final CreateGroupUseCase _createGroupUseCase;

  /// Chọn / bỏ chọn một người.
  void toggleMember(String userId) {
    final current = state.selectedUserIds;
    state = state.copyWith(
      selectedUserIds: current.contains(userId)
          ? [
              for (final id in current)
                if (id != userId) id,
            ]
          : [...current, userId],
    );
  }

  Future<GroupCreateOutcome?> submit({
    required String name,
    required String description,
  }) async {
    if (state.isSubmitting) return null;
    state = state.copyWith(isSubmitting: true, clearError: true);
    final result = await _createGroupUseCase.execute(
      workspaceId: state.workspaceId,
      name: name,
      description: description,
      memberIds: state.selectedUserIds,
    );
    switch (result) {
      case Success<CreateGroupResult>(value: final value):
        if (mounted) {
          state = state.copyWith(isSubmitting: false, clearError: true);
        }
        return GroupCreateOutcome(
          channel: value.channel,
          failedCount: value.failedMemberIds.length,
        );
      case FailureResult<CreateGroupResult>(failure: final failure):
        if (mounted) {
          state = state.copyWith(
            isSubmitting: false,
            errorMessage: failure.message,
          );
        }
        return null;
    }
  }
}
