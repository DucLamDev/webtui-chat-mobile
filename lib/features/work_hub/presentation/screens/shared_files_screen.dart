import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/presentation/widgets/message_media_widgets.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/shared_audio_controller.dart';
import '../controllers/shared_file_display.dart';
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

/// Tệp đã chia sẻ trong workspace: lọc theo loại (kèm số tệp), tìm theo tên,
/// chia nhóm theo thời gian; Ảnh / Video hiện dạng lưới, còn lại là các khối
/// bo tròn.
class SharedFilesScreen extends ConsumerStatefulWidget {
  const SharedFilesScreen({required this.workspaceId, this.now, super.key});

  final String workspaceId;

  /// Mốc giờ để chia nhóm Hôm nay / Hôm qua (test truyền cố định).
  final DateTime? now;

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
  final _search = TextEditingController();
  bool _searching = false;

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
    _search.dispose();
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
    final query = _search.text.trim().toLowerCase();
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        backgroundColor: WebTuiColors.background,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: _searching
            ? TextField(
                key: const Key('files_search'),
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Tìm tệp theo tên...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              )
            : Text(
                'Tệp chia sẻ',
                style: WebTuiTypography.titleLarge.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: WebTuiColors.textPrimary,
                ),
              ),
        actions: [
          IconButton(
            key: const Key('files_search_toggle'),
            tooltip: _searching ? 'Đóng tìm kiếm' : 'Tìm tệp',
            icon: Icon(_searching ? WebTuiIcons.close : WebTuiIcons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
            }),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: async.when(
          loading: () => Column(
            children: [
              _filterBar(const []),
              const Expanded(child: SharedFilesSkeleton()),
            ],
          ),
          error: (error, _) => Center(
            child: WorkErrorBox(
              message: workHubErrorText(error),
              onRetry: () => ref.invalidate(sharedFilesProvider),
            ),
          ),
          data: (files) {
            final matching = query.isEmpty
                ? files
                : files
                      .where(
                        (file) => '${file.name} ${sharedFileTitle(file)}'
                            .toLowerCase()
                            .contains(query),
                      )
                      .toList(growable: false);
            final shown = matching
                .where((file) => _filter == null || file.kind == _filter)
                .toList(growable: false);
            return Column(
              children: [
                _filterBar(matching),
                Expanded(
                  child: shown.isEmpty
                      ? WorkEmptyBox(
                          icon: WebTuiIcons.sharedFiles,
                          message: files.isEmpty
                              ? 'Chưa có tệp nào'
                              : query.isNotEmpty
                              ? 'Không thấy tệp nào tên "${_search.text.trim()}"'
                              : 'Không có tệp nào ở mục này',
                        )
                      : RefreshIndicator(
                          onRefresh: () async =>
                              ref.invalidate(sharedFilesProvider),
                          child: _content(shown),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filterBar(List<SharedFile> files) {
    return SharedFilesFilterBar(
      filters: _filters,
      selected: _filter,
      counts: countSharedFilesByKind(files),
      total: files.length,
      onSelected: (kind) => setState(() => _filter = kind),
    );
  }

  Widget _content(List<SharedFile> shown) {
    final now = widget.now ?? DateTime.now();
    final grid =
        _filter == SharedFileKind.image || _filter == SharedFileKind.video;
    final sections = groupSharedFiles(shown, now, byMonth: grid);
    final apiBase = ref.watch(activeServerUriProvider);
    return CustomScrollView(
      key: const Key('files_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final section in sections) ...[
          SliverToBoxAdapter(
            child: SharedFilesSectionHeader(
              title: section.title,
              count: section.files.length,
            ),
          ),
          if (grid)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => SharedMediaGridTile(
                    workspaceId: widget.workspaceId,
                    file: section.files[index],
                    apiBaseUri: apiBase,
                    onTap: () => unawaited(_onTap(section.files[index], shown)),
                  ),
                  childCount: section.files.length,
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: SharedFilesSectionCard(
                children: [
                  for (final file in section.files)
                    SharedFileRow(
                      workspaceId: widget.workspaceId,
                      file: file,
                      apiBaseUri: apiBase,
                      audio: _audio,
                      subtitle: sharedFileSubtitle(
                        file,
                        showTime: section.showTime,
                        now: now,
                      ),
                      onTap: () => unawaited(_onTap(file, shown)),
                    ),
                ],
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }
}
