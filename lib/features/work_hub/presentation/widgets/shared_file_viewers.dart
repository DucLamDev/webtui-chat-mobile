import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/shared_file_logic.dart';

const _viewerBackground = Color(0xFF101318);

/// Mở tệp bằng ứng dụng có sẵn trên máy; trả false khi không mở được.
Future<bool> openSharedFileExternally(File file) async {
  try {
    final result = await OpenFilex.open(file.path);
    return result.type == ResultType.done;
  } on Object {
    return false;
  }
}

/// Trình phát video toàn màn: phát dần qua đường dẫn có mã; lỗi thì tải tệp
/// rồi phát bản cục bộ.
class SharedVideoPlayerPage extends StatefulWidget {
  const SharedVideoPlayerPage({
    required this.file,
    required this.resolver,
    super.key,
  });

  final SharedFile file;
  final SharedFileMediaResolver resolver;

  @override
  State<SharedVideoPlayerPage> createState() => _SharedVideoPlayerPageState();
}

class _SharedVideoPlayerPageState extends State<SharedVideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<VideoPlayerController?> _tryInit(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.initialize();
      return controller;
    } on Object {
      await controller.dispose();
      return null;
    }
  }

  Future<void> _start() async {
    setState(() => _failed = false);
    VideoPlayerController? ready;
    try {
      final stream = await widget.resolver.streamUri(widget.file);
      if (stream != null) {
        // Địa chỉ phát dần tự mang mã ngắn hạn, không gửi thông tin đăng nhập.
        ready = await _tryInit(
          VideoPlayerController.networkUrl(
            stream,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          ),
        );
      }
      if (ready == null && !_disposed) {
        final local = await widget.resolver.localFile(widget.file);
        if (_disposed) return;
        ready = await _tryInit(
          VideoPlayerController.file(
            local,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          ),
        );
      }
    } on Object {
      ready = null;
    }
    if (_disposed) {
      await ready?.dispose();
      return;
    }
    if (ready == null) {
      setState(() => _failed = true);
      return;
    }
    await ready.setLooping(false);
    await ready.play();
    setState(() => _controller = ready);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_controller?.dispose());
    super.dispose();
  }

  String _clock(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: _failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Không phát được video này.',
                            style: TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const Key('video_retry'),
                            onPressed: _start,
                            child: const Text('Thử lại'),
                          ),
                        ],
                      )
                    : controller == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : GestureDetector(
                        onTap: () => setState(() {
                          controller.value.isPlaying
                              ? controller.pause()
                              : controller.play();
                        }),
                        child: AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                key: const Key('video_close'),
                tooltip: 'Đóng',
                color: Colors.white,
                icon: const Icon(WebTuiIcons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            if (controller != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => Row(
                    children: [
                      IconButton(
                        key: const Key('video_toggle'),
                        color: Colors.white,
                        tooltip: value.isPlaying ? 'Dừng' : 'Phát',
                        icon: Icon(
                          value.isPlaying
                              ? WebTuiIcons.pause
                              : WebTuiIcons.play,
                        ),
                        onPressed: () => value.isPlaying
                            ? controller.pause()
                            : controller.play(),
                      ),
                      Text(
                        _clock(value.position),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _clock(value.duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Trình xem PDF toàn màn ngay trong app (tải qua bộ nhớ đệm rồi dựng bằng
/// trình hiển thị PDF của hệ điều hành).
class SharedPdfViewerPage extends StatefulWidget {
  const SharedPdfViewerPage({
    required this.file,
    required this.resolver,
    super.key,
  });

  final SharedFile file;
  final SharedFileMediaResolver resolver;

  @override
  State<SharedPdfViewerPage> createState() => _SharedPdfViewerPageState();
}

class _SharedPdfViewerPageState extends State<SharedPdfViewerPage> {
  PdfControllerPinch? _controller;
  File? _local;
  bool _failed = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final local = await widget.resolver.localFile(widget.file);
      if (_disposed) return;
      _local = local;
      final controller = PdfControllerPinch(
        document: PdfDocument.openFile(local.path),
      );
      setState(() => _controller = controller);
    } on Object {
      if (!_disposed) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openExternally() async {
    final local = _local;
    var ok = false;
    if (local != null) ok = await openSharedFileExternally(local);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được tệp bằng ứng dụng khác.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: _viewerBackground,
      appBar: AppBar(
        backgroundColor: _viewerBackground,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          key: const Key('pdf_close'),
          tooltip: 'Đóng',
          icon: const Icon(WebTuiIcons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shortenFileName(widget.file.name, maxLength: 28),
              style: const TextStyle(fontSize: 15),
            ),
            if (controller != null)
              PdfPageNumber(
                controller: controller,
                builder: (_, _, page, pages) => Text(
                  'Trang $page / ${pages ?? 0}',
                  key: const Key('pdf_page_number'),
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('pdf_open_external'),
            tooltip: 'Mở bằng ứng dụng khác',
            icon: const Icon(WebTuiIcons.externalLink),
            onPressed: _local == null ? null : _openExternally,
          ),
        ],
      ),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Không mở được tệp PDF này.',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        key: const Key('pdf_retry'),
                        onPressed: _load,
                        child: const Text('Thử lại'),
                      ),
                      if (_local != null)
                        OutlinedButton(
                          onPressed: _openExternally,
                          child: const Text(
                            'Mở bằng ứng dụng khác',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            )
          : controller == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : PdfViewPinch(
              controller: controller,
              scrollDirection: Axis.vertical,
              backgroundDecoration: const BoxDecoration(
                color: _viewerBackground,
              ),
              onDocumentError: (_) {
                if (mounted) setState(() => _failed = true);
              },
              builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                documentLoaderBuilder: (_) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                pageLoaderBuilder: (_) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
    );
  }
}
