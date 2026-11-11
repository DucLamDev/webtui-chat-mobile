import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/rich_message_use_cases.dart';
import '../../domain/entities/rich_message.dart';

@immutable
final class VoiceTranscriptScope {
  const VoiceTranscriptScope({required this.workspaceId, required this.fileId});

  final String workspaceId;
  final String fileId;

  @override
  bool operator ==(Object other) =>
      other is VoiceTranscriptScope &&
      other.workspaceId == workspaceId &&
      other.fileId == fileId;

  @override
  int get hashCode => Object.hash(workspaceId, fileId);
}

enum VoiceTranscriptPhase { idle, loading, pending, ready, unavailable, error }

@immutable
final class VoiceTranscriptState {
  const VoiceTranscriptState({
    this.phase = VoiceTranscriptPhase.idle,
    this.text = '',
    this.segments = const [],
    this.errorMessage,
  });

  final VoiceTranscriptPhase phase;
  final String text;

  /// Các đoạn lời kèm giờ (có thì hiện chép lời đồng bộ); rỗng thì chỉ có [text].
  final List<FileTranscriptSegment> segments;
  final String? errorMessage;
}

final voiceTranscriptControllerProvider = StateNotifierProvider.autoDispose
    .family<
      VoiceTranscriptController,
      VoiceTranscriptState,
      VoiceTranscriptScope
    >((ref, scope) {
      return VoiceTranscriptController(
        scope: scope,
        loadTranscript: ref.watch(loadFileTranscriptUseCaseProvider),
      );
    });

/// "Xem lời" của tin thoại: `ready` hiện chữ; `queued` / `processing` hỏi lại
/// mỗi 5 giây, tối đa 2 phút; `failed` / `skipped` / `none` báo chưa có lời.
final class VoiceTranscriptController
    extends StateNotifier<VoiceTranscriptState> {
  VoiceTranscriptController({
    required this.scope,
    required LoadFileTranscriptUseCase loadTranscript,
    this.pollInterval = const Duration(seconds: 5),
    this.maxWait = const Duration(minutes: 2),
  }) : _loadTranscript = loadTranscript,
       super(const VoiceTranscriptState());

  final VoiceTranscriptScope scope;
  final LoadFileTranscriptUseCase _loadTranscript;
  final Duration pollInterval;
  final Duration maxWait;
  Timer? _timer;
  int _polls = 0;

  int get _maxPolls => pollInterval.inMilliseconds <= 0
      ? 1
      : maxWait.inMilliseconds ~/ pollInterval.inMilliseconds;

  /// Bấm "Xem lời" (hoặc thử lại).
  Future<void> load() async {
    if (state.phase == VoiceTranscriptPhase.loading ||
        state.phase == VoiceTranscriptPhase.pending) {
      return;
    }
    _timer?.cancel();
    _polls = 0;
    state = const VoiceTranscriptState(phase: VoiceTranscriptPhase.loading);
    await _fetch();
  }

  void hide() {
    _timer?.cancel();
    state = const VoiceTranscriptState();
  }

  Future<void> _fetch() async {
    final result = await _loadTranscript.execute(
      workspaceId: scope.workspaceId,
      fileId: scope.fileId,
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        final segments = [
          for (final segment in value.segments)
            if (segment.text.isNotEmpty) segment,
        ];
        if (value.status == FileTranscriptStatus.ready &&
            (value.text.isNotEmpty || segments.isNotEmpty)) {
          state = VoiceTranscriptState(
            phase: VoiceTranscriptPhase.ready,
            text: value.text,
            segments: List.unmodifiable(segments),
          );
        } else if (value.status.isPending && _polls < _maxPolls) {
          _polls += 1;
          state = const VoiceTranscriptState(
            phase: VoiceTranscriptPhase.pending,
          );
          _timer = Timer(pollInterval, () => unawaited(_fetch()));
        } else {
          state = const VoiceTranscriptState(
            phase: VoiceTranscriptPhase.unavailable,
          );
        }
      case FailureResult(:final failure):
        state = VoiceTranscriptState(
          phase: VoiceTranscriptPhase.error,
          errorMessage: failure.message,
        );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
