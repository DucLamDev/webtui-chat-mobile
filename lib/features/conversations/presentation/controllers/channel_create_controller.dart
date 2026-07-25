import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/channel_use_cases.dart';
import '../../domain/entities/conversation_summary.dart';

final channelCreateControllerProvider = StateNotifierProvider.autoDispose
    .family<ChannelCreateController, ChannelCreateState, String>((
      ref,
      workspaceId,
    ) {
      return ChannelCreateController(
        workspaceId: workspaceId,
        createChannelUseCase: ref.watch(createChannelUseCaseProvider),
      );
    });

final class ChannelCreateState {
  const ChannelCreateState({
    required this.workspaceId,
    this.visibility = ChannelVisibility.public,
    this.isSubmitting = false,
    this.errorMessage,
  });

  final String workspaceId;
  final ChannelVisibility visibility;
  final bool isSubmitting;
  final String? errorMessage;

  ChannelCreateState copyWith({
    ChannelVisibility? visibility,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ChannelCreateState(
      workspaceId: workspaceId,
      visibility: visibility ?? this.visibility,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final class ChannelCreateController extends StateNotifier<ChannelCreateState> {
  ChannelCreateController({
    required String workspaceId,
    required CreateChannelUseCase createChannelUseCase,
  }) : _createChannelUseCase = createChannelUseCase,
       super(ChannelCreateState(workspaceId: workspaceId));

  final CreateChannelUseCase _createChannelUseCase;

  void setVisibility(ChannelVisibility visibility) {
    state = state.copyWith(visibility: visibility);
  }

  Future<ConversationSummary?> submit({
    required String name,
    required String slug,
    required String description,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    final result = await _createChannelUseCase.execute(
      workspaceId: state.workspaceId,
      slug: slug,
      name: name,
      description: description,
      visibility: state.visibility,
    );
    switch (result) {
      case Success<ConversationSummary>(value: final channel):
        state = state.copyWith(isSubmitting: false, clearError: true);
        return channel;
      case FailureResult<ConversationSummary>(failure: final failure):
        state = state.copyWith(
          isSubmitting: false,
          errorMessage: failure.message,
        );
        return null;
    }
  }
}
