import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/invite_use_cases.dart';
import '../../domain/entities/workspace_invite.dart';

enum InvitePhase { loading, ready, unavailable, error, accepting, accepted }

final class InviteState {
  const InviteState({
    this.phase = InvitePhase.loading,
    this.preview,
    this.errorMessage,
    this.result,
  });

  final InvitePhase phase;
  final WorkspaceInvitePreview? preview;
  final String? errorMessage;
  final InviteAcceptResult? result;

  InviteState copyWith({
    InvitePhase? phase,
    WorkspaceInvitePreview? preview,
    String? errorMessage,
    bool clearError = false,
    InviteAcceptResult? result,
  }) {
    return InviteState(
      phase: phase ?? this.phase,
      preview: preview ?? this.preview,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      result: result ?? this.result,
    );
  }
}

final class InviteController extends StateNotifier<InviteState> {
  InviteController({
    required this.token,
    required Future<Result<WorkspaceInvitePreview>> Function(String token)
    preview,
    required Future<Result<InviteAcceptResult>> Function(String token) accept,
  }) : _preview = preview,
       _accept = accept,
       super(const InviteState());

  final String token;
  final Future<Result<WorkspaceInvitePreview>> Function(String token) _preview;
  final Future<Result<InviteAcceptResult>> Function(String token) _accept;

  Future<void> load() async {
    state = const InviteState();
    final result = await _preview(token);
    if (!mounted) return;
    switch (result) {
      case Success<WorkspaceInvitePreview>(value: final preview)
          when preview.isActive:
        state = state.copyWith(phase: InvitePhase.ready, preview: preview);
      case Success<WorkspaceInvitePreview>(value: final preview):
        state = state.copyWith(
          phase: InvitePhase.unavailable,
          preview: preview,
          errorMessage: inviteStatusMessage(preview.status),
        );
      case FailureResult<WorkspaceInvitePreview>(:final failure):
        final unavailable = const [
          InviteErrorCode.notFound,
          InviteErrorCode.expired,
          InviteErrorCode.revoked,
          InviteErrorCode.usedUp,
          'INVITE_SERVER_MISMATCH',
          'INVITE_TOKEN_INVALID',
        ].any(failure.hasCode);
        state = state.copyWith(
          phase: unavailable ? InvitePhase.unavailable : InvitePhase.error,
          errorMessage: inviteFailureMessage(failure),
        );
    }
  }

  Future<void> accept() async {
    if (state.phase != InvitePhase.ready) return;
    state = state.copyWith(phase: InvitePhase.accepting, clearError: true);
    final result = await _accept(token);
    if (!mounted) return;
    switch (result) {
      case Success<InviteAcceptResult>(:final value):
        state = state.copyWith(phase: InvitePhase.accepted, result: value);
      case FailureResult<InviteAcceptResult>(:final failure):
        final unavailable = const [
          InviteErrorCode.notFound,
          InviteErrorCode.expired,
          InviteErrorCode.revoked,
          InviteErrorCode.usedUp,
        ].any(failure.hasCode);
        state = state.copyWith(
          phase: unavailable ? InvitePhase.unavailable : InvitePhase.ready,
          errorMessage: inviteFailureMessage(failure),
        );
    }
  }
}

final inviteControllerProvider = StateNotifierProvider.autoDispose
    .family<InviteController, InviteState, String>((ref, token) {
      final controller = InviteController(
        token: token,
        preview: (value) =>
            ref.read(previewInviteUseCaseProvider).execute(value),
        accept: (value) => ref.read(acceptInviteUseCaseProvider).execute(value),
      );
      unawaited(controller.load());
      return controller;
    });
