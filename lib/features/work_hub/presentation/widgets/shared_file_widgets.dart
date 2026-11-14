import 'package:flutter/material.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/domain/entities/chat_message.dart';
import '../../../conversations/presentation/widgets/message_media_widgets.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/shared_audio_controller.dart';
import '../controllers/shared_file_logic.dart';
import 'work_common.dart';

/// Màu thương hiệu + chữ của "logo" loại tệp (tự vẽ, không dùng ảnh bản quyền).
({Color color, String letter})? sharedFileBadgeStyle(SharedFileFormat format) {
  return switch (format) {
    SharedFileFormat.pdf => (color: const Color(0xFFE5322D), letter: 'PDF'),
    SharedFileFormat.word => (color: const Color(0xFF185ABD), letter: 'W'),
    SharedFileFormat.excel => (color: const Color(0xFF107C41), letter: 'X'),
    SharedFileFormat.powerpoint => (
      color: const Color(0xFFC43E1C),
      letter: 'P',
    ),
    SharedFileFormat.other => null,
  };
}

/// Ô bo góc màu thương hiệu + chữ trắng cho PDF / Word / Excel / PowerPoint.
class SharedFileTypeBadge extends StatelessWidget {
  const SharedFileTypeBadge({required this.format, this.size = 52, super.key});

  final SharedFileFormat format;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = sharedFileBadgeStyle(format);
    if (style == null) {
      return WorkIconBox(
        icon: WebTuiIcons.file,
        size: size,
        radius: 12,
        background: WebTuiColors.primarySoft,
        foreground: WebTuiColors.primary,
      );
    }
    final isPdf = format == SharedFileFormat.pdf;
    return Semantics(
      label: 'Tệp ${style.letter}',
      excludeSemantics: true,
      child: Container(
        key: Key('file_badge_${format.name}'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: style.color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          style.letter,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: isPdf ? size * 0.28 : size * 0.46,
            letterSpacing: isPdf ? 0.3 : 0,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Đường dẫn ảnh nhỏ / tải xuống của tệp trong workspace.
String sharedFileDownloadPath(String workspaceId, String fileId) =>
    '/api/v1/workspaces/${Uri.encodeComponent(workspaceId)}'
    '/files/${Uri.encodeComponent(fileId)}/download';

String sharedFileThumbnailPath(String workspaceId, String fileId) =>
    '/api/v1/workspaces/${Uri.encodeComponent(workspaceId)}'
    '/files/${Uri.encodeComponent(fileId)}/thumbnail';

/// Tệp ảnh / video dưới dạng tệp đính kèm của phòng chat, để dùng lại khung
/// tải ảnh có xác thực. Ảnh: ảnh nhỏ rồi ảnh gốc; video: chỉ ảnh bìa.
MessageAttachment sharedFileAttachment(
  String workspaceId,
  SharedFile file, {
  required bool coverOnly,
}) {
  return MessageAttachment(
    id: file.id,
    workspaceId: workspaceId,
    messageId: '',
    fileId: file.id,
    createdAt: file.createdAt,
    file: UploadedMessageFile(
      id: file.id,
      name: file.name,
      mimeType: coverOnly ? 'image/jpeg' : file.mimeType,
      byteSize: file.byteSize,
      createdAt: file.createdAt,
      downloadPath: coverOnly
          ? ''
          : sharedFileDownloadPath(workspaceId, file.id),
      thumbnailUrl: sharedFileThumbnailPath(workspaceId, file.id),
    ),
  );
}

/// Ảnh thu nhỏ vuông cho ảnh / video (video có dấu phát nhỏ).
class SharedFileThumbnail extends StatelessWidget {
  const SharedFileThumbnail({
    required this.workspaceId,
    required this.file,
    required this.apiBaseUri,
    this.size = 52,
    super.key,
  });

  final String workspaceId;
  final SharedFile file;
  final Uri apiBaseUri;
  final double size;

  @override
  Widget build(BuildContext context) {
    final video = file.kind == SharedFileKind.video;
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: WebTuiColors.backgroundMuted,
              child: MessageImageAttachmentView(
                attachment: sharedFileAttachment(
                  workspaceId,
                  file,
                  coverOnly: video,
                ),
                apiBaseUri: apiBaseUri,
                fit: BoxFit.cover,
                height: size,
                maxWidth: size,
                maxHeight: size,
              ),
            ),
            if (video)
              Center(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    WebTuiIcons.play,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ảnh bìa video kích thước tuỳ ý (dùng khung tải ảnh có xác thực).
class SharedFileCoverImage extends StatelessWidget {
  const SharedFileCoverImage({
    required this.workspaceId,
    required this.file,
    required this.apiBaseUri,
    required this.width,
    required this.height,
    super.key,
  });

  final String workspaceId;
  final SharedFile file;
  final Uri apiBaseUri;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return MessageImageAttachmentView(
      attachment: sharedFileAttachment(workspaceId, file, coverOnly: true),
      apiBaseUri: apiBaseUri,
      fit: BoxFit.cover,
      height: height,
      maxWidth: width,
      maxHeight: height,
    );
  }
}

String _clock(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Dòng tệp: hình đầu dòng theo loại, tên gọn, dòng phụ, ghi âm có tiến độ.
class SharedFileRow extends StatefulWidget {
  const SharedFileRow({
    required this.workspaceId,
    required this.file,
    required this.apiBaseUri,
    required this.audio,
    required this.onTap,
    super.key,
  });

  final String workspaceId;
  final SharedFile file;
  final Uri apiBaseUri;
  final SharedAudioController audio;
  final VoidCallback onTap;

  @override
  State<SharedFileRow> createState() => _SharedFileRowState();
}

class _SharedFileRowState extends State<SharedFileRow>
    with AutomaticKeepAliveClientMixin {
  // Giữ dòng ảnh / video khi cuộn để không tải lại ảnh nhỏ.
  @override
  bool get wantKeepAlive =>
      widget.file.kind == SharedFileKind.image ||
      widget.file.kind == SharedFileKind.video;

  Widget _leading(bool playing, bool loading) {
    final file = widget.file;
    switch (file.kind) {
      case SharedFileKind.image:
      case SharedFileKind.video:
        return SharedFileThumbnail(
          workspaceId: widget.workspaceId,
          file: file,
          apiBaseUri: widget.apiBaseUri,
        );
      case SharedFileKind.audio:
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1E3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Color(0xFFE8760A),
                  ),
                )
              : Icon(
                  playing ? WebTuiIcons.pause : WebTuiIcons.play,
                  color: const Color(0xFFE8760A),
                  size: 26,
                ),
        );
      case SharedFileKind.document:
        return SharedFileTypeBadge(format: sharedFileFormat(file));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final file = widget.file;
    final date = file.createdAt.toLocal();
    final subtitle =
        '${sharedFileSizeText(file.byteSize)} · '
        '${workShortDate(date)}/${date.year}';
    return InkWell(
      key: Key('file_${file.id}'),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: ListenableBuilder(
          listenable: widget.audio,
          builder: (context, _) {
            final audio = widget.audio;
            final active =
                file.kind == SharedFileKind.audio && audio.isActive(file.id);
            final loading = active && audio.loading;
            final playing = active && !audio.loading;
            return Row(
              children: [
                _leading(playing, loading),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shortenFileName(file.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: WebTuiColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: WebTuiTypography.bodySmall.copyWith(
                          color: WebTuiColors.textMuted,
                        ),
                      ),
                      if (playing) ...[
                        const SizedBox(height: 6),
                        Row(
                          key: Key('file_audio_progress_${file.id}'),
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: audio.progress,
                                  minHeight: 4,
                                  backgroundColor: WebTuiColors.border,
                                  color: const Color(0xFFE8760A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_clock(audio.position)} / '
                              '${_clock(audio.duration)}',
                              style: WebTuiTypography.bodySmall.copyWith(
                                color: WebTuiColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Kích thước tệp dạng "1,2 MB".
String sharedFileSizeText(int bytes) {
  String format(double value, String unit) {
    final text = value.toStringAsFixed(value < 10 ? 1 : 0);
    return '${text.replaceAll('.', ',')} $unit';
  }

  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return format(kb, 'KB');
  final mb = kb / 1024;
  if (mb < 1024) return format(mb, 'MB');
  return format(mb / 1024, 'GB');
}
