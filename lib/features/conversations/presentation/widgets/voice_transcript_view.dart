import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_voice.dart';
import '../../domain/entities/rich_message.dart';
import '../controllers/voice_playback_link.dart';
import '../controllers/voice_transcript_controller.dart';
import 'message_media_widgets.dart';

/// Nút "Xem lời" dưới trình phát tin thoại. Chỉ hiện khi máy chủ báo
/// `capabilities.transcription`; tin còn đang gửi (chưa có trên máy chủ) thì ẩn.
class VoiceTranscriptView extends ConsumerWidget {
  const VoiceTranscriptView({
    required this.attachment,
    this.playbackLink,
    super.key,
  });

  final MessageAttachment attachment;

  /// Nối với trình phát cùng tin: có thì tô đoạn đang nghe và bấm đoạn để tua.
  final VoicePlaybackLink? playbackLink;

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
          segments: state.segments,
          playbackLink: playbackLink,
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
  const _TranscriptBox({
    required this.text,
    required this.segments,
    required this.playbackLink,
    required this.onHide,
  });

  final String text;
  final List<FileTranscriptSegment> segments;
  final VoicePlaybackLink? playbackLink;
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
              if (segments.isNotEmpty)
                _SegmentList(segments: segments, playbackLink: playbackLink)
              else
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

/// Các đoạn lời kèm giờ. Có [playbackLink] thì đoạn đang nghe được tô sáng, khung
/// tự cuộn tới đoạn đó (chỉ cuộn trong khung, không kéo cả danh sách tin), và
/// chạm một đoạn thì tua tới đầu đoạn và phát.
class _SegmentList extends StatefulWidget {
  const _SegmentList({required this.segments, required this.playbackLink});

  final List<FileTranscriptSegment> segments;
  final VoicePlaybackLink? playbackLink;

  @override
  State<_SegmentList> createState() => _SegmentListState();
}

class _SegmentListState extends State<_SegmentList> {
  static const _maxHeight = 220.0;

  final ScrollController _scroll = ScrollController();
  List<GlobalKey> _keys = const [];
  int _shownActive = -1;

  @override
  void initState() {
    super.initState();
    _syncKeys();
  }

  @override
  void didUpdateWidget(covariant _SegmentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments.length != widget.segments.length) _syncKeys();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _syncKeys() {
    _keys = List.generate(widget.segments.length, (_) => GlobalKey());
  }

  /// Cuộn khung lời (không dùng `Scrollable.ensureVisible` vì hàm đó cuộn cả
  /// danh sách tin bên ngoài).
  void _revealActive(int active) {
    if (active == _shownActive) return;
    _shownActive = active;
    if (active < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || active >= _keys.length) return;
      final item = _keys[active].currentContext?.findRenderObject();
      if (item == null || !item.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(item);
      if (viewport == null) return;
      final position = _scroll.position;
      final top = viewport.getOffsetToReveal(item, 0).offset;
      final bottom = viewport.getOffsetToReveal(item, 1).offset;
      if (position.pixels <= top && position.pixels >= bottom) return;
      final target = viewport
          .getOffsetToReveal(item, 0.5)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      unawaited(
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.playbackLink;
    if (link == null) return _buildList(-1, canSeek: false);
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final positionMs = link.positionMs;
        // Vị trí 0 = chưa phát / đã hết bài: không tô đoạn nào.
        final active = positionMs > 0
            ? activeTranscriptSegmentIndex(widget.segments, positionMs)
            : -1;
        _revealActive(active);
        return _buildList(active, canSeek: link.canSeek);
      },
    );
  }

  Widget _buildList(int active, {required bool canSeek}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < widget.segments.length; index++)
              _SegmentRow(
                key: _keys[index],
                segment: widget.segments[index],
                active: index == active,
                onTap: canSeek
                    ? () => unawaited(
                        widget.playbackLink!.seekAndPlay(
                          widget.segments[index].startMs,
                        ),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.segment,
    required this.active,
    required this.onTap,
    super.key,
  });

  final FileTranscriptSegment segment;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final time = formatTranscriptTime(segment.startMs);
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.xs,
        vertical: 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              time,
              style: WebTuiTypography.labelSmall.copyWith(
                color: active
                    ? WebTuiColors.textPrimary
                    : WebTuiColors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              segment.text,
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textPrimary,
                fontWeight: active ? FontWeight.w600 : null,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      selected: active,
      button: onTap != null,
      label: onTap != null ? 'Nghe từ $time' : null,
      child: Container(
        constraints: BoxConstraints(minHeight: onTap != null ? 44 : 0),
        decoration: BoxDecoration(
          color: active ? WebTuiColors.primarySoft : null,
          border: active
              ? const Border(
                  left: BorderSide(color: WebTuiColors.primary, width: 3),
                )
              : null,
          borderRadius: BorderRadius.circular(WebTuiRadii.xs),
        ),
        child: onTap == null
            ? row
            : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(WebTuiRadii.xs),
                  onTap: onTap,
                  child: row,
                ),
              ),
      ),
    );
  }
}

/// Tin thoại trong bong bóng chat: trình phát + "Xem lời", nối với nhau để lời
/// chạy theo tiếng và chạm đoạn lời thì tua.
class VoiceAttachmentWithTranscript extends StatefulWidget {
  const VoiceAttachmentWithTranscript({
    required this.attachment,
    required this.outgoing,
    this.apiBaseUri,
    this.voice,
    super.key,
  });

  final MessageAttachment attachment;
  final bool outgoing;
  final Uri? apiBaseUri;
  final MessageVoiceMetadata? voice;

  @override
  State<VoiceAttachmentWithTranscript> createState() =>
      _VoiceAttachmentWithTranscriptState();
}

class _VoiceAttachmentWithTranscriptState
    extends State<VoiceAttachmentWithTranscript> {
  final VoicePlaybackLink _link = VoicePlaybackLink();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: widget.outgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MessageVoiceAttachmentView(
          attachment: widget.attachment,
          apiBaseUri: widget.apiBaseUri,
          voice: widget.voice,
          playbackLink: _link,
        ),
        VoiceTranscriptView(attachment: widget.attachment, playbackLink: _link),
      ],
    );
  }
}
