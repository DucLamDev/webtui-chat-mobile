import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/domain/entities/chat_message.dart';
import '../../../conversations/presentation/widgets/message_media_widgets.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/work_hub_providers.dart';
import '../widgets/work_common.dart';

/// Kích thước tệp dạng "1,2 MB".
String sharedFileSizeLabel(int bytes) {
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

IconData sharedFileIcon(SharedFileKind kind) {
  return switch (kind) {
    SharedFileKind.image => WebTuiIcons.image,
    SharedFileKind.video => WebTuiIcons.videoFile,
    SharedFileKind.audio => WebTuiIcons.audioFile,
    SharedFileKind.document => WebTuiIcons.file,
  };
}

/// Tệp đã chia sẻ trong workspace, lọc theo loại.
class SharedFilesScreen extends ConsumerStatefulWidget {
  const SharedFilesScreen({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  ConsumerState<SharedFilesScreen> createState() => _SharedFilesScreenState();
}

class _SharedFilesScreenState extends ConsumerState<SharedFilesScreen> {
  static const _filters = <(SharedFileKind?, String)>[
    (null, 'Tất cả'),
    (SharedFileKind.image, 'Ảnh'),
    (SharedFileKind.video, 'Video'),
    (SharedFileKind.document, 'Tài liệu'),
    (SharedFileKind.audio, 'Ghi âm'),
  ];

  SharedFileKind? _filter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sharedFilesProvider(widget.workspaceId));
    return Scaffold(
      appBar: AppBar(title: const Text('Tệp chia sẻ')),
      body: SafeArea(
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  for (final (kind, label) in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('files_filter_${kind?.name ?? 'all'}'),
                        label: Text(label),
                        selected: _filter == kind,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _filter = kind),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      WorkSkeleton(height: 56, radius: 14),
                      SizedBox(height: 10),
                      WorkSkeleton(height: 56, radius: 14),
                      SizedBox(height: 10),
                      WorkSkeleton(height: 56, radius: 14),
                    ],
                  ),
                ),
                error: (error, _) => Center(
                  child: WorkErrorBox(
                    message: workHubErrorText(error),
                    onRetry: () => ref.invalidate(sharedFilesProvider),
                  ),
                ),
                data: (files) {
                  final shown = files
                      .where((file) => _filter == null || file.kind == _filter)
                      .toList(growable: false);
                  if (shown.isEmpty) {
                    return WorkEmptyBox(
                      icon: WebTuiIcons.sharedFiles,
                      message: files.isEmpty
                          ? 'Chưa có tệp nào'
                          : 'Không có tệp nào ở mục này',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(sharedFilesProvider),
                    child: ListView.separated(
                      key: const Key('files_list'),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 60,
                        color: WebTuiColors.border.withValues(alpha: 0.7),
                      ),
                      itemBuilder: (context, index) => _FileRow(
                        file: shown[index],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SharedFileViewerPage(
                              workspaceId: widget.workspaceId,
                              file: shown[index],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onTap});

  final SharedFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final kind = file.kind;
    final colors = webTuiShortcutColors(switch (kind) {
      SharedFileKind.image => 'green',
      SharedFileKind.video => 'violet',
      SharedFileKind.audio => 'orange',
      SharedFileKind.document => 'blue',
    });
    final date = file.createdAt.toLocal();
    return InkWell(
      key: Key('file_${file.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            WorkIconBox(
              icon: sharedFileIcon(kind),
              size: 44,
              radius: 13,
              background: colors.background,
              foreground: colors.foreground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${sharedFileSizeLabel(file.byteSize)} · '
                    '${workShortDate(date)}/${date.year}',
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trình xem một tệp: dùng lại các khung xem ảnh / video / ghi âm / tệp của
/// phòng chat (tải qua luồng tải có sẵn).
class SharedFileViewerPage extends ConsumerWidget {
  const SharedFileViewerPage({
    required this.workspaceId,
    required this.file,
    super.key,
  });

  final String workspaceId;
  final SharedFile file;

  MessageAttachment get _attachment {
    return MessageAttachment(
      id: file.id,
      workspaceId: workspaceId,
      messageId: '',
      fileId: file.id,
      createdAt: file.createdAt,
      file: UploadedMessageFile(
        id: file.id,
        name: file.name,
        mimeType: file.mimeType,
        byteSize: file.byteSize,
        createdAt: file.createdAt,
        downloadPath:
            '/api/v1/workspaces/${Uri.encodeComponent(workspaceId)}'
            '/files/${Uri.encodeComponent(file.id)}/download',
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiBaseUri = ref.watch(activeServerUriProvider);
    final attachment = _attachment;
    final body = switch (file.kind) {
      SharedFileKind.image => MessageImageAttachmentView(
        attachment: attachment,
        apiBaseUri: apiBaseUri,
        preferThumbnail: false,
        fit: BoxFit.contain,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
      ),
      SharedFileKind.video => MessageVideoAttachmentView(
        attachment: attachment,
        apiBaseUri: apiBaseUri,
      ),
      SharedFileKind.audio => MessageVoiceAttachmentView(
        attachment: attachment,
        apiBaseUri: apiBaseUri,
      ),
      SharedFileKind.document => MessageFileAttachmentView(
        attachment: attachment,
        outgoing: false,
        apiBaseUri: apiBaseUri,
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(padding: const EdgeInsets.all(16), child: body),
        ),
      ),
    );
  }
}
