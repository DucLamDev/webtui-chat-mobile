import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_download_service.dart';
import '../../../application/ide_files_service.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_file_models.dart';
import '../../controllers/ide_files_controllers.dart';
import '../../widgets/files/ide_code_view.dart';
import '../../widgets/files/ide_file_actions.dart';
import '../../widgets/files/ide_file_job_dialog.dart';
import '../../widgets/files/ide_file_transfer.dart';
import '../../widgets/files/ide_files_ui.dart';
import '../../widgets/files/ide_image_viewer.dart';
import '../../widgets/ide_wb.dart';
import '../../widgets/markdown/ide_markdown.dart';
import 'ide_diff_screen.dart';
import 'ide_file_editor_screen.dart';

enum _Mode { loading, text, image, video, pdf, tooBig, secret, error }

/// Xem một tệp: mã (tô màu, nhảy tới dòng), Markdown, ảnh, video, PDF,
/// Office (đổi sang PDF trên máy IDE). Tệp > 3 MB chỉ cho tải về.
class IdeFileViewerScreen extends ConsumerStatefulWidget {
  const IdeFileViewerScreen({
    required this.root,
    required this.path,
    this.size,
    this.line,
    super.key,
  });

  final String root;
  final String path;

  /// Cỡ tệp nếu đã biết (null → hỏi `files.stat`).
  final int? size;

  /// Dòng cần nhảy tới (từ kết quả tìm theo chữ).
  final int? line;

  @override
  ConsumerState<IdeFileViewerScreen> createState() =>
      _IdeFileViewerScreenState();
}

class _IdeFileViewerScreenState extends ConsumerState<IdeFileViewerScreen> {
  _Mode _mode = _Mode.loading;
  Object? _error;
  String _text = '';
  int _mtime = 0;
  bool _preview = true;
  IdeDownloadedFile? _file;
  VideoPlayerController? _video;
  PdfControllerPinch? _pdf;
  String _note = '';

  String get _name => ideBaseName(widget.path);
  IdeFileKind get _kind => ideFileKindOf(_name);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_video?.dispose());
    _pdf?.dispose();
    final f = _file;
    if (f != null) unawaited(ref.read(ideDownloadServiceProvider).discard(f));
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _mode = _Mode.loading;
      _error = null;
    });
    final files = ref.read(ideFilesServiceProvider);
    try {
      var size = widget.size;
      if (size == null) {
        final st = await files.stat(widget.path);
        if (st.secret) return _set(_Mode.secret);
        size = st.size;
      }
      switch (_kind) {
        case IdeFileKind.code || IdeFileKind.markdown:
          if (size > ideFileTextMaxBytes) return _set(_Mode.tooBig);
          final t = await files.read(widget.path);
          if (!mounted) return;
          _text = t.text;
          _mtime = t.mtime;
          _set(_Mode.text);
        case IdeFileKind.image || IdeFileKind.video || IdeFileKind.pdf:
          if (size > ideFileTextMaxBytes) return _set(_Mode.tooBig);
          await _openMedia(widget.path, _kind);
        case IdeFileKind.office:
          if (size > ideFileTextMaxBytes) return _set(_Mode.tooBig);
          await _openOffice(files);
        case IdeFileKind.other:
          _set(_Mode.tooBig, note: 'binary');
      }
    } on IdeTooLarge {
      _set(_Mode.tooBig);
    } on IdeUnsupported {
      _set(_Mode.tooBig, note: 'binary');
    } on IdeForbidden {
      _set(_Mode.secret);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _mode = _Mode.error;
        });
      }
    }
  }

  void _set(_Mode mode, {String note = ''}) {
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _note = note;
    });
  }

  Future<void> _openMedia(String path, IdeFileKind kind) async {
    final service = ref.read(ideDownloadServiceProvider);
    final dl = service.start(path);
    final f = await dl.done;
    if (!mounted) {
      await service.discard(f);
      return;
    }
    _file = f;
    switch (kind) {
      case IdeFileKind.image:
        _set(_Mode.image);
      case IdeFileKind.video:
        final c = VideoPlayerController.file(
          f.file,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        try {
          await c.initialize();
        } on Object {
          await c.dispose();
          return _set(_Mode.tooBig, note: 'binary');
        }
        if (!mounted) {
          await c.dispose();
          return;
        }
        _video = c;
        _set(_Mode.video);
      default:
        try {
          final doc = PdfDocument.openFile(f.file.path);
          _pdf = PdfControllerPinch(document: doc);
          await doc;
        } on Object {
          _pdf?.dispose();
          _pdf = null;
          return _set(_Mode.tooBig, note: 'binary');
        }
        _set(_Mode.pdf);
    }
  }

  Future<void> _openOffice(IdeFilesService files) async {
    final job = await files.officePdf(widget.path);
    if (!mounted) return;
    final out = await showIdeFileJobDialog(
      context,
      job: job,
      title: tr('Đang đổi sang PDF', 'Converting to PDF'),
    );
    if (!mounted) return;
    if (out == null) {
      // Người dùng ẩn hộp: việc vẫn chạy trên máy IDE.
      return _set(_Mode.error, note: 'hidden');
    }
    if (!out.ok || out.path.isEmpty || !ideIsSafePath(out.path)) {
      throw const IdeError('ide_error', 'Không đổi được sang PDF.');
    }
    await _openMedia(out.path, IdeFileKind.pdf);
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      IdePageRoute<bool>(
        dark: true,
        builder: (_) => IdeFileEditorScreen(
          root: widget.root,
          path: widget.path,
          initialText: _text,
          baseMtime: _mtime,
        ),
      ),
    );
    if (saved == true && mounted) unawaited(_load());
  }

  bool get _canEdit => _mode == _Mode.text;

  @override
  Widget build(BuildContext context) {
    final isMd = _kind == IdeFileKind.markdown && _mode == _Mode.text;
    return Scaffold(
      appBar: AppBar(
        title: Text(_name, overflow: TextOverflow.ellipsis),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (isMd)
            IconButton(
              key: const Key('ide_md_toggle'),
              tooltip: _preview
                  ? tr('Xem mã nguồn', 'View source')
                  : tr('Xem bản đọc', 'View preview'),
              icon: Icon(
                _preview ? Icons.code_rounded : Icons.article_outlined,
              ),
              onPressed: () => setState(() => _preview = !_preview),
            ),
          if (_canEdit)
            IconButton(
              key: const Key('ide_file_edit'),
              tooltip: tr('Sửa', 'Edit'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
          PopupMenuButton<String>(
            key: const Key('ide_viewer_menu'),
            tooltip: tr('Thêm', 'More'),
            onSelected: _onMenu,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'download',
                child: Text(tr('Tải về máy', 'Download')),
              ),
              PopupMenuItem(
                value: 'ai',
                child: Text(tr('Hỏi AI về tệp này', 'Ask AI about this file')),
              ),
              PopupMenuItem(
                value: 'diff',
                child: Text(tr('Xem thay đổi (git)', 'View changes (git)')),
              ),
              PopupMenuItem(
                value: 'path',
                child: Text(tr('Chép đường dẫn', 'Copy path')),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  void _onMenu(String v) {
    switch (v) {
      case 'download':
        unawaited(ideDownloadAndSave(context, ref, widget.path));
      case 'ai':
        unawaited(
          ideAskAiAboutPath(context, root: widget.root, path: widget.path),
        );
      case 'diff':
        unawaited(
          Navigator.of(context).push(
            IdePageRoute<void>(
              dark: true,
              builder: (_) =>
                  IdeDiffScreen(root: widget.root, path: widget.path),
            ),
          ),
        );
      case 'path':
        unawaited(
          ideCopyText(
            context,
            widget.path,
            tr('Đã chép đường dẫn', 'Path copied'),
          ),
        );
    }
  }

  Widget _body() {
    switch (_mode) {
      case _Mode.loading:
        return WebTuiLoadingState(
          message: tr('Đang mở tệp...', 'Opening the file...'),
        );
      case _Mode.error:
        if (_note == 'hidden') {
          return WebTuiEmptyState(
            icon: Icons.hourglass_top_rounded,
            title: tr('Đang đổi sang PDF', 'Converting to PDF'),
            message: tr(
              'Việc vẫn chạy trên máy tính. Mở lại tệp sau ít phút.',
              'The job is still running on your computer. Reopen the file in a few minutes.',
            ),
          );
        }
        final e = _error;
        if (e is IdeForbidden) return _secretView();
        return WebTuiErrorState(
          title: tr('Không mở được tệp', 'Could not open the file'),
          message: e == null ? '' : ideFilesErrorText(e),
          onRetry: _load,
        );
      case _Mode.secret:
        return _secretView();
      case _Mode.tooBig:
        return _downloadOnly();
      case _Mode.text:
        if (_kind == IdeFileKind.markdown && _preview) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(WebTuiSpacing.lg),
            child: IdeMarkdown(text: _text),
          );
        }
        if (_text.isEmpty) {
          return WebTuiEmptyState(
            icon: Icons.description_outlined,
            title: tr('Tệp trống', 'Empty file'),
            message: tr(
              'Tệp này chưa có nội dung.',
              'This file has no content yet.',
            ),
          );
        }
        return IdeCodeView(
          text: _text,
          language: ideLanguageFor(_name),
          jumpToLine: widget.line,
        );
      case _Mode.image:
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Center(child: Image(image: ideBoundedImage(_file!.file))),
        );
      case _Mode.video:
        return _VideoBox(controller: _video!);
      case _Mode.pdf:
        return PdfViewPinch(controller: _pdf!);
    }
  }

  Widget _secretView() => WebTuiEmptyState(
    icon: Icons.lock_outline_rounded,
    title: tr('Tệp bí mật', 'Secret file'),
    message: tr(
      'Tệp bí mật chỉ mở trên máy tính.',
      'Secret files only open on your computer.',
    ),
  );

  Widget _downloadOnly() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 48,
              color: IdeWbPalette.of(context).text2,
            ),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              _note == 'binary'
                  ? tr(
                      'Không xem được loại tệp này trong app',
                      'This file type cannot be viewed in the app',
                    )
                  : tr('Tệp lớn hơn 3 MB', 'File is larger than 3 MB'),
              textAlign: TextAlign.center,
              style: IdeType.titleMedium,
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Text(
              tr(
                'Bạn có thể tải về máy.',
                'You can download it to your phone.',
              ),
              textAlign: TextAlign.center,
              style: IdeType.bodyMedium.copyWith(
                color: IdeWbPalette.of(context).text,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            FilledButton.icon(
              key: const Key('ide_download_only'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () =>
                  unawaited(ideDownloadAndSave(context, ref, widget.path)),
              icon: const Icon(Icons.download_rounded),
              label: Text(tr('Tải về', 'Download')),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoBox extends StatefulWidget {
  const _VideoBox({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_VideoBox> createState() => _VideoBoxState();
}

class _VideoBoxState extends State<_VideoBox> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio == 0
                  ? 16 / 9
                  : c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
        ),
        VideoProgressIndicator(c, allowScrubbing: true),
        IconButton(
          key: const Key('ide_video_toggle'),
          iconSize: 36,
          tooltip: c.value.isPlaying ? tr('Dừng', 'Pause') : tr('Phát', 'Play'),
          icon: Icon(
            c.value.isPlaying
                ? Icons.pause_circle_outline_rounded
                : Icons.play_circle_outline_rounded,
          ),
          onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
        ),
      ],
    );
  }
}
