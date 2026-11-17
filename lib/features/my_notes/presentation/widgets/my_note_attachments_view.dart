import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_avatar.dart';
import '../../../../design_system/components/webtui_dialogs.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../l10n/app_strings.dart';
import '../../../conversations/domain/entities/chat_message.dart';
import '../../../conversations/presentation/widgets/message_media_widgets.dart';
import '../../domain/entities/my_note.dart';

/// Gỡ một tệp khỏi ghi chú (tệp vẫn còn trong kho tệp của workspace).
typedef MyNoteAttachmentRemover =
    FutureOr<void> Function(MyNoteAttachment attachment);

/// Ảnh / tệp đính kèm hiện dưới phần chữ của ghi chú (như app Ghi chú iPhone):
/// ảnh xếp lưới 2 cột (một ảnh thì một ảnh rộng), tệp khác là dòng tệp.
///
/// Ảnh tải có đăng nhập qua widget ảnh của chat (ưu tiên ảnh nhỏ máy chủ làm
/// sẵn, giải mã theo cỡ ô). Bấm ảnh mở màn xem toàn màn hình; nhấn giữ (khi
/// không [readOnly]) hiện "Gỡ khỏi ghi chú".
class MyNoteAttachmentsView extends StatelessWidget {
  const MyNoteAttachmentsView({
    required this.workspaceId,
    required this.attachments,
    this.uploadingCount = 0,
    this.readOnly = false,
    this.onRemove,
    super.key,
  });

  final String workspaceId;
  final List<MyNoteAttachment> attachments;

  /// Số tệp đang tải lên: mỗi tệp một ô mờ có vòng tiến độ trong lưới.
  final int uploadingCount;
  final bool readOnly;
  final MyNoteAttachmentRemover? onRemove;

  static const double gap = 6;
  static const double radius = 10;

  bool get _canRemove => !readOnly && onRemove != null;

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((item) => item.isImage).toList();
    final files = attachments.where((item) => !item.isImage).toList();
    final pending = uploadingCount < 0 ? 0 : uploadingCount;
    if (images.isEmpty && files.isEmpty && pending == 0) {
      return const SizedBox.shrink();
    }
    final apiBaseUri = WebTuiAvatarNetworkScope.maybeOf(context)?.apiBaseUri;
    return Column(
      key: const Key('my_note_attachments_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty || pending > 0)
          LayoutBuilder(
            builder: (context, constraints) => _buildGrid(
              context,
              width: constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width,
              images: images,
              pending: pending,
              apiBaseUri: apiBaseUri,
            ),
          ),
        for (final file in files) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          _FileRow(
            key: ValueKey('my_note_attachment_file_${file.fileId}'),
            attachment: _asMessageAttachment(workspaceId, file),
            apiBaseUri: apiBaseUri,
            onLongPress: _canRemove
                ? () => _confirmRemove(context, file, onRemove!)
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildGrid(
    BuildContext context, {
    required double width,
    required List<MyNoteAttachment> images,
    required int pending,
    required Uri? apiBaseUri,
  }) {
    final total = images.length + pending;
    final single = total == 1;
    final cellWidth = single ? width : (width - gap) / 2;
    final cellHeight = single ? (width * 0.75).clamp(120.0, 360.0) : cellWidth;
    final cells = <Widget>[
      for (var index = 0; index < images.length; index++)
        _ImageCell(
          key: ValueKey('my_note_attachment_image_${images[index].fileId}'),
          attachment: _asMessageAttachment(workspaceId, images[index]),
          apiBaseUri: apiBaseUri,
          width: cellWidth,
          height: cellHeight,
          onTap: () => openMyNoteImageViewer(
            context,
            workspaceId: workspaceId,
            images: images,
            initialIndex: index,
            readOnly: readOnly,
            onRemove: onRemove,
            apiBaseUri: apiBaseUri,
          ),
          onLongPress: _canRemove
              ? () => _confirmRemove(context, images[index], onRemove!)
              : null,
        ),
      for (var index = 0; index < pending; index++)
        _UploadingCell(
          key: ValueKey('my_note_attachment_uploading_$index'),
          width: cellWidth,
          height: cellHeight,
        ),
    ];
    return Wrap(spacing: gap, runSpacing: gap, children: cells);
  }
}

/// Mở màn xem ảnh toàn màn hình (vuốt ngang giữa các ảnh, chụm để phóng to).
Future<void> openMyNoteImageViewer(
  BuildContext context, {
  required String workspaceId,
  required List<MyNoteAttachment> images,
  required int initialIndex,
  bool readOnly = false,
  MyNoteAttachmentRemover? onRemove,
  Uri? apiBaseUri,
}) {
  if (images.isEmpty) return Future.value();
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => MyNoteImageViewerScreen(
        workspaceId: workspaceId,
        images: images,
        initialIndex: initialIndex.clamp(0, images.length - 1),
        readOnly: readOnly,
        onRemove: onRemove,
        apiBaseUri:
            apiBaseUri ?? WebTuiAvatarNetworkScope.maybeOf(context)?.apiBaseUri,
      ),
    ),
  );
}

class MyNoteImageViewerScreen extends StatefulWidget {
  const MyNoteImageViewerScreen({
    required this.workspaceId,
    required this.images,
    required this.initialIndex,
    this.readOnly = false,
    this.onRemove,
    this.apiBaseUri,
    super.key,
  });

  final String workspaceId;
  final List<MyNoteAttachment> images;
  final int initialIndex;
  final bool readOnly;
  final MyNoteAttachmentRemover? onRemove;
  final Uri? apiBaseUri;

  @override
  State<MyNoteImageViewerScreen> createState() =>
      _MyNoteImageViewerScreenState();
}

class _MyNoteImageViewerScreenState extends State<MyNoteImageViewerScreen> {
  static const _background = Color(0xFF101318);

  late final PageController _controller;
  late int _index;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    final remover = widget.onRemove;
    if (remover == null || _removing) return;
    final attachment = widget.images[_index];
    final removed = await _confirmRemove(context, attachment, (item) async {
      setState(() => _removing = true);
      try {
        await remover(item);
      } finally {
        if (mounted) setState(() => _removing = false);
      }
    });
    if (removed && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final canRemove = !widget.readOnly && widget.onRemove != null;
    final current = widget.images[_index];
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('my_note_image_viewer_close'),
          tooltip: tr('Đóng', 'Close'),
          icon: const Icon(WebTuiIcons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current.originalName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
            if (widget.images.length > 1)
              Text(
                '${_index + 1}/${widget.images.length}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (value) => setState(() => _index = value),
        itemBuilder: (context, index) {
          final image = widget.images[index];
          return InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: MessageImageAttachmentView(
                key: ValueKey('my_note_image_viewer_${image.fileId}'),
                attachment: _asMessageAttachment(widget.workspaceId, image),
                apiBaseUri: widget.apiBaseUri,
                fit: BoxFit.contain,
                maxHeight: size.height - 160,
                maxWidth: size.width,
                // Ảnh gốc quá lớn để xem trước thì dùng ảnh nhỏ máy chủ làm sẵn.
                preferThumbnail: image.byteSize > maxImagePreviewBytes,
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: canRemove
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.lg,
                  vertical: WebTuiSpacing.sm,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('my_note_image_viewer_remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _removing ? null : _remove,
                    icon: _removing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(WebTuiIcons.delete),
                    label: Text(tr('Gỡ khỏi ghi chú', 'Remove from note')),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _ImageCell extends StatelessWidget {
  const _ImageCell({
    required this.attachment,
    required this.apiBaseUri,
    required this.width,
    required this.height,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final MessageAttachment attachment;
  final Uri? apiBaseUri;
  final double width;
  final double height;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(MyNoteAttachmentsView.radius),
          child: MessageImageAttachmentView(
            attachment: attachment,
            apiBaseUri: apiBaseUri,
            fit: BoxFit.cover,
            height: height,
            maxWidth: width,
            maxHeight: height,
            onPressed: onTap,
          ),
        ),
      ),
    );
  }
}

class _UploadingCell extends StatelessWidget {
  const _UploadingCell({required this.width, required this.height, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Đang tải tệp lên', 'Uploading file'),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: WebTuiColors.primarySoft.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(MyNoteAttachmentsView.radius),
        ),
        alignment: Alignment.center,
        child: SizedBox.square(
          dimension: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: WebTuiColors.primary,
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.attachment,
    required this.apiBaseUri,
    this.onLongPress,
    super.key,
  });

  final MessageAttachment attachment;
  final Uri? apiBaseUri;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    // Dòng tệp của chat: icon + tên + dung lượng, bấm thì tải về rồi mở.
    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: Alignment.centerLeft,
        child: MessageFileAttachmentView(
          attachment: attachment,
          outgoing: false,
          apiBaseUri: apiBaseUri,
        ),
      ),
    );
  }
}

/// Hỏi xác nhận rồi gọi [remover]; trả `true` khi đã gỡ xong.
Future<bool> _confirmRemove(
  BuildContext context,
  MyNoteAttachment attachment,
  MyNoteAttachmentRemover remover,
) async {
  final confirmed = await showWebTuiConfirmDialog(
    context,
    title: tr('Gỡ khỏi ghi chú?', 'Remove from note?'),
    message: tr(
      '"${attachment.originalName}" sẽ không còn hiện trong ghi chú này.',
      '"${attachment.originalName}" will no longer appear in this note.',
    ),
    confirmLabel: tr('Gỡ khỏi ghi chú', 'Remove from note'),
    destructive: true,
    icon: WebTuiIcons.delete,
  );
  if (!confirmed) return false;
  await remover(attachment);
  return true;
}

/// Dựng bản ghi đính kèm kiểu chat để dùng lại widget ảnh / tệp (tải có
/// đăng nhập, giới hạn dung lượng, mở bằng ứng dụng ngoài).
MessageAttachment _asMessageAttachment(
  String workspaceId,
  MyNoteAttachment attachment,
) {
  final base =
      '/api/v1/workspaces/${Uri.encodeComponent(workspaceId.trim())}'
      '/files/${Uri.encodeComponent(attachment.fileId.trim())}';
  return MessageAttachment(
    id: 'my-note-${attachment.fileId}',
    workspaceId: workspaceId,
    messageId: '',
    fileId: attachment.fileId,
    createdAt: attachment.createdAt,
    file: UploadedMessageFile(
      id: attachment.fileId,
      name: attachment.originalName,
      mimeType: attachment.mimeType,
      byteSize: attachment.byteSize,
      downloadPath: '$base/download',
      thumbnailUrl: attachment.hasServerThumbnail ? '$base/thumbnail' : null,
      createdAt: attachment.createdAt,
    ),
  );
}
