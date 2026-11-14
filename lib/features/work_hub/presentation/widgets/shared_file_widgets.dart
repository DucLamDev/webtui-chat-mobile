import 'package:flutter/material.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/domain/entities/chat_message.dart';
import '../../../conversations/presentation/widgets/message_media_widgets.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/shared_audio_controller.dart';
import '../controllers/shared_file_display.dart';
import '../controllers/shared_file_logic.dart';
import 'work_common.dart';

export '../controllers/shared_file_display.dart' show sharedFileSizeText;

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

/// Ô bo góc màu thương hiệu + chữ trắng cho PDF / Word / Excel / PowerPoint;
/// tệp khác: ô xanh nhạt + biểu tượng tệp.
class SharedFileTypeBadge extends StatelessWidget {
  const SharedFileTypeBadge({required this.format, this.size = 46, super.key});

  final SharedFileFormat format;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = sharedFileBadgeStyle(format);
    final radius = BorderRadius.circular(size * 0.26);
    if (style == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: WebTuiColors.primarySoft,
          borderRadius: radius,
        ),
        child: Icon(
          WebTuiIcons.file,
          size: size * 0.46,
          color: WebTuiColors.primary,
        ),
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
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(style.color, Colors.white, 0.12)!, style.color],
          ),
        ),
        child: Text(
          style.letter,
          style: TextStyle(
            fontFamily: WebTuiTypography.fontFamily,
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: isPdf ? size * 0.27 : size * 0.44,
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

/// Video chưa có ảnh bìa (gửi từ bản cũ): khung tối có dấu phát, KHÔNG gọi tải
/// (tránh ô xám lỗi như trước).
bool sharedVideoHasCover(SharedFile file) =>
    file.kind != SharedFileKind.video || file.thumbnailUrl != null;

/// Ô thay ảnh bìa cho video chưa có ảnh bìa: nền tối, biểu tượng máy quay mờ
/// ([iconSize] null: không biểu tượng, khi ô đã có dấu phát ở giữa).
class _VideoCoverFallback extends StatelessWidget {
  const _VideoCoverFallback({required this.iconSize});

  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('file_video_fallback'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF334A6B), Color(0xFF1C2A40)],
        ),
      ),
      child: iconSize == null
          ? const SizedBox.expand()
          : Center(
              child: Icon(
                WebTuiIcons.video,
                size: iconSize,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
    );
  }
}

/// Ảnh thu nhỏ bo góc cho ảnh / video (video: dấu phát giữa ô).
class SharedFileThumbnail extends StatelessWidget {
  const SharedFileThumbnail({
    required this.workspaceId,
    required this.file,
    required this.apiBaseUri,
    this.size = 46,
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
        borderRadius: BorderRadius.circular(size * 0.26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (sharedVideoHasCover(file))
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
              )
            else
              const _VideoCoverFallback(iconSize: null),
            if (video)
              Center(
                child: Container(
                  width: size * 0.46,
                  height: size * 0.46,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    WebTuiIcons.play,
                    size: size * 0.24,
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
    if (!sharedVideoHasCover(file)) {
      return SizedBox(
        width: width,
        height: height,
        child: _VideoCoverFallback(iconSize: height * 0.28),
      );
    }
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

/// Ô vuông trong lưới Ảnh / Video: ảnh phủ kín, video có dải tối dưới cùng với
/// dấu phát + thời lượng.
class SharedMediaGridTile extends StatefulWidget {
  const SharedMediaGridTile({
    required this.workspaceId,
    required this.file,
    required this.apiBaseUri,
    required this.onTap,
    super.key,
  });

  final String workspaceId;
  final SharedFile file;
  final Uri apiBaseUri;
  final VoidCallback onTap;

  @override
  State<SharedMediaGridTile> createState() => _SharedMediaGridTileState();
}

class _SharedMediaGridTileState extends State<SharedMediaGridTile>
    with AutomaticKeepAliveClientMixin {
  // Giữ ô khi cuộn để không tải lại ảnh nhỏ.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final file = widget.file;
    final video = file.kind == SharedFileKind.video;
    return Semantics(
      button: true,
      label: '${sharedFileTitle(file)} ${sharedFileSizeText(file.byteSize)}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth;
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Material(
              color: WebTuiColors.backgroundMuted,
              child: InkWell(
                key: Key('file_${file.id}'),
                onTap: widget.onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (sharedVideoHasCover(file))
                      MessageImageAttachmentView(
                        attachment: sharedFileAttachment(
                          widget.workspaceId,
                          file,
                          coverOnly: video,
                        ),
                        apiBaseUri: widget.apiBaseUri,
                        fit: BoxFit.cover,
                        height: side,
                        maxWidth: side,
                        maxHeight: side,
                      )
                    else
                      _VideoCoverFallback(iconSize: side * 0.3),
                    if (video)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0),
                                Colors.black.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                            child: Row(
                              children: [
                                const Icon(
                                  WebTuiIcons.play,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const Spacer(),
                                if (file.durationMs case final duration?)
                                  Text(
                                    sharedFileDurationText(duration),
                                    style: const TextStyle(
                                      fontFamily: WebTuiTypography.fontFamily,
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _clock(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Dòng tệp trong khối bo tròn: hình đầu dòng theo loại (ảnh nhỏ, logo tài
/// liệu, nút nghe tròn cho ghi âm), tên gọn, dòng phụ; ghi âm đang phát có
/// thanh tiến độ.
class SharedFileRow extends StatefulWidget {
  const SharedFileRow({
    required this.workspaceId,
    required this.file,
    required this.apiBaseUri,
    required this.audio,
    required this.onTap,
    required this.subtitle,
    super.key,
  });

  final String workspaceId;
  final SharedFile file;
  final Uri apiBaseUri;
  final SharedAudioController audio;
  final VoidCallback onTap;

  /// Dòng phụ đã định dạng theo nhóm (giờ hoặc ngày).
  final String subtitle;

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
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: playing || loading
                ? WebTuiColors.primary
                : WebTuiColors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  playing ? WebTuiIcons.pause : WebTuiIcons.play,
                  color: playing ? Colors.white : WebTuiColors.primary,
                  size: 20,
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
    return InkWell(
      key: Key('file_${file.id}'),
      onTap: widget.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          sharedFileTitle(file),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: WebTuiColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (playing)
                          Row(
                            key: Key('file_audio_progress_${file.id}'),
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: audio.progress,
                                    minHeight: 4,
                                    backgroundColor: WebTuiColors.primarySoft,
                                    color: WebTuiColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_clock(audio.position)} / '
                                '${_clock(audio.duration)}',
                                style: WebTuiTypography.bodySmall.copyWith(
                                  color: WebTuiColors.textSecondary,
                                  fontSize: 12,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WebTuiTypography.bodySmall.copyWith(
                              fontSize: 13,
                              color: WebTuiColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Tiêu đề nhóm ("Hôm nay", "Tháng 10/2026") kèm số tệp.
class SharedFilesSectionHeader extends StatelessWidget {
  const SharedFilesSectionHeader({
    required this.title,
    required this.count,
    super.key,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: WebTuiTypography.bodyMedium.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: WebTuiColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: WebTuiTypography.bodySmall.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WebTuiColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Khối trắng bo 18 chứa các dòng tệp, đường kẻ mảnh thụt vào sau hình đầu dòng.
class SharedFilesSectionCard extends StatelessWidget {
  const SharedFilesSectionCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E3A64).withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 72,
                      color: WebTuiColors.border.withValues(alpha: 0.7),
                    ),
                  children[index],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hàng bộ lọc dạng viên kèm số tệp: chọn = nền xanh chữ trắng, chưa chọn =
/// nền trắng viền xám; thiếu chỗ thì cuộn ngang, vùng bấm cao 48.
class SharedFilesFilterBar extends StatelessWidget {
  const SharedFilesFilterBar({
    required this.filters,
    required this.selected,
    required this.counts,
    required this.total,
    required this.onSelected,
    super.key,
  });

  final List<(SharedFileKind?, String)> filters;
  final SharedFileKind? selected;
  final Map<SharedFileKind, int> counts;
  final int total;
  final ValueChanged<SharedFileKind?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (kind, label) in filters) ...[
            _FilterPill(
              key: Key('files_filter_${kind?.name ?? 'all'}'),
              label: label,
              count: kind == null ? total : counts[kind] ?? 0,
              selected: selected == kind,
              onTap: () => onSelected(kind),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? WebTuiColors.textOnPrimary
        : WebTuiColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label $count',
      excludeSemantics: true,
      child: SizedBox(
        height: 48,
        child: Center(
          child: Material(
            color: selected ? WebTuiColors.primary : WebTuiColors.surface,
            shape: StadiumBorder(
              side: BorderSide(
                color: selected
                    ? WebTuiColors.primary
                    : const Color(0xFFC3D0E0),
                width: 1.2,
              ),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: WebTuiTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontFamily: WebTuiTypography.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? WebTuiColors.textOnPrimary
                              : WebTuiColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Khung xương lúc đang tải: hai khối bo tròn với các dòng giả.
class SharedFilesSkeleton extends StatelessWidget {
  const SharedFilesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkSkeleton(height: 14, width: 90, radius: 6),
          SizedBox(height: 12),
          WorkSkeleton(height: 68, radius: 18),
          SizedBox(height: 10),
          WorkSkeleton(height: 68, radius: 18),
          SizedBox(height: 22),
          WorkSkeleton(height: 14, width: 120, radius: 6),
          SizedBox(height: 12),
          WorkSkeleton(height: 68, radius: 18),
        ],
      ),
    );
  }
}
