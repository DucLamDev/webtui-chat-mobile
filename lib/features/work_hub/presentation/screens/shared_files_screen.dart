import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../conversations/presentation/widgets/message_media_widgets.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/shared_audio_controller.dart';
import '../controllers/shared_file_logic.dart';
import '../controllers/shared_file_providers.dart';
import '../controllers/work_hub_providers.dart';
import '../widgets/shared_file_sheet.dart';
import '../widgets/shared_file_viewers.dart';
import '../widgets/shared_file_widgets.dart';
import '../widgets/work_common.dart';

/// Kích thước tệp dạng "1,2 MB".
String sharedFileSizeLabel(int bytes) => sharedFileSizeText(bytes);

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
  late final SharedAudioController _audio;

  @override
  void initState() {
    super.initState();
    _audio = SharedAudioController(
      engineFactory: ref.read(sharedAudioEngineFactoryProvider),
      resolver: () =>
          ref.read(sharedFileMediaResolverProvider(widget.workspaceId)),
    );
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onTap(SharedFile file, List<SharedFile> shown) async {
    final action = sharedFileTapAction(file);
    final apiBase = ref.read(activeServerUriProvider);
    switch (action) {
      case SharedFileTapAction.playInline:
        await _audio.toggle(file);
        if (_audio.failed) _message('Không phát được ghi âm này.');
      case SharedFileTapAction.openImage:
        final images = shown
            .where((item) => item.kind == SharedFileKind.image)
            .toList(growable: false);
        await openMessageImageGallery(
          context,
          attachments: [
            for (final image in images)
              sharedFileAttachment(widget.workspaceId, image, coverOnly: false),
          ],
          initialIndex: images.indexWhere((item) => item.id == file.id),
          apiBaseUri: apiBase,
          title: 'Tệp chia sẻ',
        );
      case SharedFileTapAction.videoSheet:
      case SharedFileTapAction.pdfSheet:
      case SharedFileTapAction.openSheet:
        await _audio.stop();
        if (!mounted) return;
        final choice = await showSharedFileActionSheet(
          context,
          workspaceId: widget.workspaceId,
          file: file,
          apiBaseUri: apiBase,
          action: action,
        );
        if (choice != null) await _run(choice, file);
    }
  }

  Future<void> _run(SharedFileSheetChoice choice, SharedFile file) async {
    final resolver = ref.read(
      sharedFileMediaResolverProvider(widget.workspaceId),
    );
    switch (choice) {
      case SharedFileSheetChoice.view:
        final page = file.kind == SharedFileKind.video
            ? SharedVideoPlayerPage(file: file, resolver: resolver)
            : SharedPdfViewerPage(file: file, resolver: resolver);
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => page),
        );
      case SharedFileSheetChoice.open:
      case SharedFileSheetChoice.openExternally:
        _message('Đang tải ${shortenFileName(file.name, maxLength: 24)}…');
        try {
          final local = await resolver.localFile(file);
          if (!await openSharedFileExternally(local)) {
            _message('Không có ứng dụng nào mở được tệp này.');
          } else if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
        } on Object {
          _message('Không thể tải tệp này. Hãy thử lại.');
        }
    }
  }

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
                      WorkSkeleton(height: 60, radius: 14),
                      SizedBox(height: 10),
                      WorkSkeleton(height: 60, radius: 14),
                      SizedBox(height: 10),
                      WorkSkeleton(height: 60, radius: 14),
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
                        indent: 64,
                        color: WebTuiColors.border.withValues(alpha: 0.7),
                      ),
                      itemBuilder: (context, index) => SharedFileRow(
                        workspaceId: widget.workspaceId,
                        file: shown[index],
                        apiBaseUri: ref.watch(activeServerUriProvider),
                        audio: _audio,
                        onTap: () => unawaited(_onTap(shown[index], shown)),
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
