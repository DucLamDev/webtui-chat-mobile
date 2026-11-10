import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/chat_message.dart';
import '../controllers/voice_transcript_controller.dart';

/// Nút "Xem lời" dưới trình phát tin thoại. Chỉ hiện khi máy chủ báo
/// `capabilities.transcription`; tin còn đang gửi (chưa có trên máy chủ) thì ẩn.
class VoiceTranscriptView extends ConsumerWidget {
  const VoiceTranscriptView({required this.attachment, super.key});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      activeServerDiscoveryProvider.select(
        (discovery) => discovery?.capabilities.transcription ?? false,
      ),
    );
    if (!enabled ||
        attachment.fileId.isEmpty ||
        attachment.messageId.startsWith('local-')) {
      return const SizedBox.shrink();
    }
    final scope = VoiceTranscriptScope(
      workspaceId: attachment.workspaceId,
      fileId: attachment.fileId,
    );
    final state = ref.watch(voiceTranscriptControllerProvider(scope));
    final controller = ref.read(
      voiceTranscriptControllerProvider(scope).notifier,
    );
    final width = (MediaQuery.sizeOf(context).width * 0.62).clamp(204.0, 254.0);
    return SizedBox(
      width: width,
      child: switch (state.phase) {
        VoiceTranscriptPhase.idle => Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 36),
              padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.xs),
            ),
            onPressed: () => unawaited(controller.load()),
            icon: const Icon(Icons.subtitles_outlined, size: 18),
            label: const Text('Xem lời'),
          ),
        ),
        VoiceTranscriptPhase.loading ||
        VoiceTranscriptPhase.pending => _StatusLine(
          loading: true,
          text: state.phase == VoiceTranscriptPhase.pending
              ? 'Đang chép lời…'
              : 'Đang tải lời…',
        ),
        VoiceTranscriptPhase.ready => _TranscriptBox(
          text: state.text,
          onHide: controller.hide,
        ),
        VoiceTranscriptPhase.unavailable => _StatusLine(
          text: 'Chưa có lời cho tin này',
          onRetry: () => unawaited(controller.load()),
        ),
        VoiceTranscriptPhase.error => _StatusLine(
          text: state.errorMessage ?? 'Chưa tải được lời.',
          error: true,
          onRetry: () => unawaited(controller.load()),
        ),
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.text,
    this.loading = false,
    this.error = false,
    this.onRetry,
  });

  final String text;
  final bool loading;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      child: Row(
        children: [
          if (loading) ...[
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: WebTuiSpacing.sm),
          ],
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                text,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: error
                      ? WebTuiColors.danger
                      : WebTuiColors.textSecondary,
                ),
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(44, 36)),
              onPressed: onRetry,
              child: const Text('Thử lại'),
            ),
        ],
      ),
    );
  }
}

class _TranscriptBox extends StatelessWidget {
  const _TranscriptBox({required this.text, required this.onHide});

  final String text;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surface,
          border: Border.all(color: WebTuiColors.border),
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.md,
            WebTuiSpacing.sm,
            WebTuiSpacing.xs,
            WebTuiSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textPrimary,
                  height: 1.4,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(44, 32)),
                  onPressed: onHide,
                  child: const Text('Ẩn lời'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
