import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/redirect_safe_file_downloader.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../../design_system/components/webtui_owned_decoded_image.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../auth/domain/repositories/auth_token_repository.dart';
import '../../application/use_cases/message_attachment_use_cases.dart';
import '../../data/files/scoped_attachment_file_store.dart';
import '../../domain/entities/chat_message.dart';

Future<void> openMessageImageGallery(
  BuildContext context, {
  required List<MessageAttachment> attachments,
  required int initialIndex,
  Uri? apiBaseUri,
  String title = 'Ảnh đã gửi',
}) {
  if (attachments.isEmpty) return Future.value();
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _MessageImageGalleryScreen(
        apiBaseUri: apiBaseUri,
        attachments: attachments,
        initialIndex: initialIndex.clamp(0, attachments.length - 1),
        title: title,
      ),
    ),
  );
}

class _MessageImageGalleryScreen extends StatefulWidget {
  const _MessageImageGalleryScreen({
    required this.attachments,
    required this.initialIndex,
    required this.title,
    this.apiBaseUri,
  });

  final List<MessageAttachment> attachments;
  final int initialIndex;
  final String title;
  final Uri? apiBaseUri;

  @override
  State<_MessageImageGalleryScreen> createState() =>
      _MessageImageGalleryScreenState();
}

class _MessageImageGalleryScreenState
    extends State<_MessageImageGalleryScreen> {
  late final PageController _controller;
  late int _index;

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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFF101318),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101318),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 15)),
            Text(
              '${_index + 1}/${widget.attachments.length}',
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
        itemCount: widget.attachments.length,
        onPageChanged: (value) => setState(() => _index = value),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Center(
              child: MessageImageAttachmentView(
                attachment: widget.attachments[index],
                apiBaseUri: widget.apiBaseUri,
                fit: BoxFit.contain,
                maxHeight: size.height - 140,
                maxWidth: size.width,
              ),
            ),
          );
        },
      ),
    );
  }
}

class MessageImageAttachmentView extends ConsumerStatefulWidget {
  const MessageImageAttachmentView({
    required this.attachment,
    this.apiBaseUri,
    this.fit = BoxFit.cover,
    this.height,
    this.maxHeight = 300,
    this.maxWidth = 260,
    this.onPressed,
    super.key,
  });

  final MessageAttachment attachment;
  final Uri? apiBaseUri;
  final BoxFit fit;
  final double? height;
  final double maxHeight;
  final double maxWidth;
  final VoidCallback? onPressed;

  @override
  ConsumerState<MessageImageAttachmentView> createState() =>
      _MessageImageAttachmentViewState();
}

class _MessageImageAttachmentViewState
    extends ConsumerState<MessageImageAttachmentView> {
  static const _downloader = RedirectSafeFileDownloader();

  Uri? _imageUri;
  File? _localImageFile;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant MessageImageAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.file.downloadPath !=
            widget.attachment.file.downloadPath ||
        oldWidget.attachment.file.localPath !=
            widget.attachment.file.localPath ||
        oldWidget.attachment.file.byteSize != widget.attachment.file.byteSize ||
        oldWidget.attachment.file.mimeType != widget.attachment.file.mimeType ||
        oldWidget.apiBaseUri != widget.apiBaseUri ||
        oldWidget.maxHeight != widget.maxHeight ||
        oldWidget.maxWidth != widget.maxWidth) {
      _reload();
    }
  }

  void _reload() {
    _loadGeneration++;
    final localPath = widget.attachment.file.localPath?.trim();
    if (widget.attachment.isImage &&
        localPath != null &&
        localPath.isNotEmpty) {
      _localImageFile = File(localPath);
      _imageUri = null;
      return;
    }
    _localImageFile = null;
    final uri = attachmentDownloadUri(widget.attachment, widget.apiBaseUri);
    _imageUri =
        uri != null &&
            attachmentPreviewWithinLimit(
              widget.attachment.file.byteSize,
              maxBytes: maxImagePreviewBytes,
            )
        ? uri
        : null;
  }

  Future<Uint8List?> _load(Uri uri, int generation) async {
    final binding = await _captureAttachmentDownloadBinding(
      ref: ref,
      attachmentUri: uri,
      apiBaseUri: widget.apiBaseUri,
    );
    if (binding == null) return null;
    try {
      return await _imageDownloadGate.run(
        () => _downloader.downloadBytes(
          uri: uri,
          maxBytes: maxImagePreviewBytes,
          accept: widget.attachment.file.mimeType,
          bearerToken: binding.bearerToken,
          isStillCurrent: () async =>
              mounted &&
              generation == _loadGeneration &&
              await binding.isStillCurrent(),
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uri = _imageUri;
    final localImageFile = _localImageFile;
    final generation = _loadGeneration;
    final placeholder = _ImagePlaceholder(
      height: widget.height,
      width: widget.maxWidth,
    );
    final image = localImageFile != null
        ? Image.file(
            localImageFile,
            width: widget.maxWidth,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: (_, _, _) => placeholder,
          )
        : uri == null
        ? placeholder
        : WebTuiOwnedDecodedImage(
            requestKey:
                '$uri|${widget.attachment.file.byteSize}|'
                '${widget.attachment.file.mimeType}|$generation',
            loadBytes: () => _load(uri, generation),
            maxEncodedBytes: maxImagePreviewBytes,
            decodeTargetWidth: (widget.maxWidth * 3).ceil().clamp(1, 2048),
            decodeTargetHeight: widget.maxHeight.isFinite
                ? (widget.maxHeight * 3).ceil().clamp(1, 2048)
                : 2048,
            width: widget.maxWidth,
            height: widget.height,
            fit: widget.fit,
            loading: _ImagePlaceholder(
              height: widget.height,
              width: widget.maxWidth,
              loading: true,
            ),
            fallback: placeholder,
          );
    return Semantics(
      button: widget.onPressed != null,
      label: 'Mở ảnh ${widget.attachment.file.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        onTap: widget.onPressed,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WebTuiRadii.md),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: widget.maxHeight,
              maxWidth: widget.maxWidth,
            ),
            child: image,
          ),
        ),
      ),
    );
  }
}

class MessageVoiceAttachmentView extends ConsumerStatefulWidget {
  const MessageVoiceAttachmentView({
    required this.attachment,
    this.apiBaseUri,
    super.key,
  });

  final MessageAttachment attachment;
  final Uri? apiBaseUri;

  @override
  ConsumerState<MessageVoiceAttachmentView> createState() =>
      _MessageVoiceAttachmentViewState();
}

class _MessageVoiceAttachmentViewState
    extends ConsumerState<MessageVoiceAttachmentView> {
  static const _downloader = RedirectSafeFileDownloader();
  static const _fileStore = ScopedAttachmentFileStore();
  static const _waveform = <double>[
    8,
    15,
    10,
    23,
    13,
    27,
    17,
    11,
    22,
    14,
    26,
    18,
    10,
    21,
    14,
    25,
    17,
    9,
    19,
    12,
    24,
    16,
    10,
    22,
    14,
    26,
  ];

  final AudioPlayer _player = AudioPlayer();
  final GlobalKey _waveformKey = GlobalKey();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  File? _audioFile;
  _AttachmentDownloadBinding? _binding;
  int _loadGeneration = 0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;
  double _playbackRate = 1;
  bool _loading = false;
  bool _failed = false;

  bool get _playing => _playerState == PlayerState.playing;

  @override
  void initState() {
    super.initState();
    _subscriptions
      ..add(
        _player.onDurationChanged.listen((duration) {
          if (mounted) setState(() => _duration = duration);
        }),
      )
      ..add(
        _player.onPositionChanged.listen((position) {
          if (mounted) setState(() => _position = position);
        }),
      )
      ..add(
        _player.onPlayerStateChanged.listen((state) {
          if (mounted) setState(() => _playerState = state);
        }),
      )
      ..add(
        _player.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() {
              _position = Duration.zero;
              _playerState = PlayerState.completed;
            });
          }
        }),
      );
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_disposeAudio(_player, _audioFile));
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageVoiceAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.file.downloadPath !=
            widget.attachment.file.downloadPath ||
        oldWidget.apiBaseUri != widget.apiBaseUri) {
      _loadGeneration += 1;
      final previousFile = _audioFile;
      _audioFile = null;
      _binding = null;
      _loading = false;
      _failed = false;
      unawaited(_player.stop());
      if (previousFile != null) unawaited(_deleteFile(previousFile));
    }
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    final binding = _binding;
    if (_audioFile == null || binding == null) {
      await _loadAndPlay();
      return;
    }
    if (!await binding.isStillCurrent()) {
      await _player.stop();
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (_playerState == PlayerState.completed) {
      await _player.play(
        DeviceFileSource(
          _audioFile!.path,
          mimeType: widget.attachment.file.mimeType,
        ),
      );
      return;
    }
    await _player.resume();
  }

  Future<void> _loadAndPlay() async {
    final generation = ++_loadGeneration;
    final uri = attachmentDownloadUri(widget.attachment, widget.apiBaseUri);
    if (uri == null ||
        !attachmentPreviewWithinLimit(
          widget.attachment.file.byteSize,
          maxBytes: maxVoicePlaybackBytes,
        )) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    File? downloaded;
    try {
      final binding = await _captureAttachmentDownloadBinding(
        ref: ref,
        attachmentUri: uri,
        apiBaseUri: widget.apiBaseUri,
      );
      if (binding == null) throw StateError('instance binding unavailable');
      Future<bool> operationIsCurrent() async {
        return mounted &&
            generation == _loadGeneration &&
            await binding.isStillCurrent();
      }

      final target = await _fileStore.fileFor(
        instanceScope: binding.instanceScope,
        sessionGeneration: binding.guard.generation,
        fileId: widget.attachment.fileId,
        originalName: widget.attachment.file.name,
        purpose: 'voice${identityHashCode(this)}',
      );
      if (!await target.exists() ||
          await target.length() != widget.attachment.file.byteSize) {
        downloaded = await _voiceDownloadGate.run(
          () => _downloader.download(
            uri: uri,
            target: target,
            maxBytes: maxVoicePlaybackBytes,
            expectedBytes: widget.attachment.file.byteSize,
            accept: widget.attachment.file.mimeType,
            bearerToken: binding.bearerToken,
            isStillCurrent: operationIsCurrent,
          ),
        );
      } else {
        downloaded = target;
      }
      final readyFile = downloaded;
      if (readyFile == null) throw StateError('audio download unavailable');
      if (!mounted ||
          generation != _loadGeneration ||
          !await operationIsCurrent()) {
        throw StateError('instance binding changed');
      }
      final previousFile = _audioFile;
      _audioFile = readyFile;
      _binding = binding;
      setState(() => _loading = false);
      await _player.play(
        DeviceFileSource(
          readyFile.path,
          mimeType: widget.attachment.file.mimeType,
        ),
      );
      if (previousFile != null && previousFile.path != readyFile.path) {
        await _deleteFile(previousFile);
      }
    } on Object {
      if (downloaded != null && downloaded.path != _audioFile?.path) {
        await _deleteFile(downloaded);
      }
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _seek(double fraction) async {
    if (_duration <= Duration.zero) return;
    final milliseconds = (_duration.inMilliseconds * fraction.clamp(0, 1))
        .round();
    await _player.seek(Duration(milliseconds: milliseconds));
  }

  Future<void> _cycleRate() async {
    final next = _playbackRate == 1
        ? 1.5
        : _playbackRate == 1.5
        ? 2.0
        : 1.0;
    await _player.setPlaybackRate(next);
    if (mounted) setState(() => _playbackRate = next);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0, 1);
    final width = (MediaQuery.sizeOf(context).width * 0.62).clamp(204, 254);
    return SizedBox(
      width: width.toDouble(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.primary,
          borderRadius: BorderRadius.circular(19),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24245EBE),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 31,
                child: IconButton.filled(
                  tooltip: _playing ? 'Tạm dừng' : 'Phát tin nhắn thoại',
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _loading ? null : _togglePlayback,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _playing
                              ? CupertinoIcons.pause_fill
                              : CupertinoIcons.play_fill,
                          size: 16,
                        ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final box =
                        _waveformKey.currentContext?.findRenderObject()
                            as RenderBox?;
                    if (box != null) {
                      unawaited(
                        _seek(details.localPosition.dx / box.size.width),
                      );
                    }
                  },
                  child: SizedBox(
                    key: _waveformKey,
                    height: 28,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        for (var index = 0; index < _waveform.length; index++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0.6,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: index / _waveform.length <= progress
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.42),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: SizedBox(height: _waveform[index]),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _failed
                    ? '--:--'
                    : _formatDuration(_playing ? _position : _duration),
                style: WebTuiTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 3),
              TextButton(
                onPressed: _cycleRate,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(28, 24),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('${_rateLabel(_playbackRate)}x'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MessageVideoAttachmentView extends ConsumerStatefulWidget {
  const MessageVideoAttachmentView({
    required this.attachment,
    this.apiBaseUri,
    this.allowFullscreen = true,
    super.key,
  });

  final MessageAttachment attachment;
  final Uri? apiBaseUri;
  final bool allowFullscreen;

  @override
  ConsumerState<MessageVideoAttachmentView> createState() =>
      _MessageVideoAttachmentViewState();
}

class _MessageVideoAttachmentViewState
    extends ConsumerState<MessageVideoAttachmentView> {
  static const _downloader = RedirectSafeFileDownloader();
  static const _fileStore = ScopedAttachmentFileStore();

  VideoPlayerController? _controller;
  File? _videoFile;
  _AttachmentDownloadBinding? _binding;
  int _initializationGeneration = 0;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant MessageVideoAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.file.downloadPath !=
            widget.attachment.file.downloadPath ||
        oldWidget.apiBaseUri != widget.apiBaseUri) {
      _initializationGeneration += 1;
      final previous = _controller;
      final previousFile = _videoFile;
      _controller = null;
      _videoFile = null;
      _binding = null;
      _loading = false;
      _failed = false;
      unawaited(_disposeVideo(previous, previousFile));
    }
  }

  void _requestDownload() {
    if (_loading || _controller != null) return;
    if (!attachmentPreviewWithinLimit(
      widget.attachment.file.byteSize,
      maxBytes: maxVideoPlaybackBytes,
    )) {
      setState(() => _failed = true);
      return;
    }
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final generation = ++_initializationGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    final uri = attachmentDownloadUri(widget.attachment, widget.apiBaseUri);
    if (uri == null) {
      _markVideoFailure(generation);
      return;
    }

    final binding = await _captureAttachmentDownloadBinding(
      ref: ref,
      attachmentUri: uri,
      apiBaseUri: widget.apiBaseUri,
    );
    if (binding == null ||
        generation != _initializationGeneration ||
        !mounted) {
      _markVideoFailure(generation);
      return;
    }

    File? downloaded;
    VideoPlayerController? next;
    try {
      Future<bool> operationIsCurrent() async {
        return mounted &&
            generation == _initializationGeneration &&
            await binding.isStillCurrent();
      }

      final target = await _fileStore.fileFor(
        instanceScope: binding.instanceScope,
        sessionGeneration: binding.guard.generation,
        fileId: widget.attachment.fileId,
        originalName: widget.attachment.file.name,
        purpose: 'video${identityHashCode(this)}',
      );
      if (!await target.exists() ||
          await target.length() != widget.attachment.file.byteSize) {
        downloaded = await _videoDownloadGate.run(
          () => _downloader.download(
            uri: uri,
            target: target,
            maxBytes: maxVideoPlaybackBytes,
            expectedBytes: widget.attachment.file.byteSize,
            accept: widget.attachment.file.mimeType,
            bearerToken: binding.bearerToken,
            isStillCurrent: operationIsCurrent,
          ),
        );
      } else {
        downloaded = target;
      }
      final readyFile = downloaded;
      if (readyFile == null) {
        throw const RedirectSafeDownloadException('video download unavailable');
      }
      if (!await operationIsCurrent() ||
          generation != _initializationGeneration ||
          !mounted) {
        throw const RedirectSafeDownloadException('instance binding changed');
      }

      next = VideoPlayerController.file(
        readyFile,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await next.initialize();
      await next.setLooping(false);
      if (!await operationIsCurrent() ||
          generation != _initializationGeneration ||
          !mounted) {
        throw const RedirectSafeDownloadException('instance binding changed');
      }
      final previous = _controller;
      final previousFile = _videoFile;
      setState(() {
        _controller = next;
        _videoFile = readyFile;
        _binding = binding;
        _loading = false;
        _failed = false;
      });
      if (previous != null) {
        await previous.dispose();
      }
      if (previousFile != null && previousFile.path != readyFile.path) {
        await _deleteFile(previousFile);
      }
    } on Object {
      await next?.dispose();
      if (downloaded != null && downloaded.path != _videoFile?.path) {
        await _deleteFile(downloaded);
      }
      _markVideoFailure(generation);
    }
  }

  void _markVideoFailure(int generation) {
    if (!mounted || generation != _initializationGeneration) return;
    setState(() {
      _loading = false;
      _failed = true;
    });
  }

  @override
  void dispose() {
    _initializationGeneration += 1;
    unawaited(_disposeVideo(_controller, _videoFile));
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    final binding = _binding;
    if (controller == null ||
        binding == null ||
        !await binding.isStillCurrent()) {
      if (controller?.value.isPlaying == true) {
        await controller?.pause();
      }
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _openFullscreen() async {
    final controller = _controller;
    final binding = _binding;
    if (controller == null ||
        binding == null ||
        !await binding.isStillCurrent() ||
        !mounted) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    }
    if (!await binding.isStillCurrent() || !mounted) return;
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              widget.attachment.file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Center(
            child: MessageVideoAttachmentView(
              attachment: widget.attachment,
              apiBaseUri: widget.apiBaseUri,
              allowFullscreen: false,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller?.value.isInitialized == true;
    final activeController = initialized ? controller! : null;
    final aspectRatio = initialized
        ? activeController!.value.aspectRatio.clamp(0.65, 1.9)
        : 16 / 9;
    final width = widget.allowFullscreen
        ? (MediaQuery.sizeOf(context).width * 0.72).clamp(230, 320).toDouble()
        : MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          widget.allowFullscreen ? WebTuiRadii.lg : 0,
        ),
        child: ColoredBox(
          color: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: aspectRatio.toDouble(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (activeController != null)
                      VideoPlayer(activeController)
                    else
                      Center(
                        child: _loading
                            ? const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              )
                            : IconButton.filled(
                                tooltip: _failed
                                    ? 'Video quá lớn hoặc không khả dụng'
                                    : 'Tải video để phát',
                                onPressed: _failed ? null : _requestDownload,
                                icon: Icon(
                                  _failed
                                      ? CupertinoIcons.exclamationmark_triangle
                                      : CupertinoIcons.arrow_down_circle_fill,
                                ),
                              ),
                      ),
                    if (activeController != null)
                      Center(
                        child: IconButton.filled(
                          tooltip: activeController.value.isPlaying
                              ? 'Tạm dừng'
                              : 'Phát video',
                          onPressed: _togglePlayback,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          icon: Icon(
                            activeController.value.isPlaying
                                ? CupertinoIcons.pause_fill
                                : CupertinoIcons.play_fill,
                          ),
                        ),
                      ),
                    if (widget.allowFullscreen && activeController != null)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: IconButton.filledTonal(
                          tooltip: 'Toàn màn hình',
                          onPressed: _openFullscreen,
                          icon: const Icon(
                            CupertinoIcons.arrow_up_left_arrow_down_right,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (activeController != null)
                VideoProgressIndicator(
                  activeController,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: WebTuiColors.primary,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12,
                  ),
                ),
              if (widget.allowFullscreen)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WebTuiSpacing.sm,
                    vertical: WebTuiSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.videocam_fill,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: WebTuiSpacing.xs),
                      Expanded(
                        child: Text(
                          _failed
                              ? 'Không phát được video'
                              : widget.attachment.file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.labelSmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MessageFileAttachmentView extends ConsumerStatefulWidget {
  const MessageFileAttachmentView({
    required this.attachment,
    required this.outgoing,
    this.apiBaseUri,
    super.key,
  });

  final MessageAttachment attachment;
  final bool outgoing;
  final Uri? apiBaseUri;

  @override
  ConsumerState<MessageFileAttachmentView> createState() =>
      _MessageFileAttachmentViewState();
}

class _MessageFileAttachmentViewState
    extends ConsumerState<MessageFileAttachmentView> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    final uri = attachmentDownloadUri(widget.attachment, widget.apiBaseUri);
    if (uri == null) {
      _showFailure('Đường dẫn tệp không hợp lệ.');
      return;
    }
    setState(() => _opening = true);
    try {
      final binding = await _captureAttachmentDownloadBinding(
        ref: ref,
        attachmentUri: uri,
        apiBaseUri: widget.apiBaseUri,
      );
      if (binding == null) {
        throw StateError('instance binding unavailable');
      }
      final target = await const ScopedAttachmentFileStore().fileFor(
        instanceScope: binding.instanceScope,
        sessionGeneration: binding.guard.generation,
        fileId: widget.attachment.fileId,
        originalName: widget.attachment.file.name,
        purpose: 'file',
      );
      if (!await target.exists() ||
          await target.length() != widget.attachment.file.byteSize) {
        await const RedirectSafeFileDownloader().download(
          uri: uri,
          target: target,
          maxBytes: UploadMessageAttachmentUseCase.maxBytes,
          expectedBytes: widget.attachment.file.byteSize,
          accept: widget.attachment.file.mimeType,
          bearerToken: binding.bearerToken,
          isStillCurrent: binding.isStillCurrent,
        );
      }
      if (!await binding.isStillCurrent()) {
        throw StateError('instance binding changed');
      }
      final opened = await OpenFilex.open(target.path);
      if (opened.type != ResultType.done) {
        throw StateError(opened.message);
      }
    } on Object {
      _showFailure('Không thể tải hoặc mở tệp này trên thiết bị.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _showFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 270),
      child: Material(
        color: widget.outgoing
            ? WebTuiColors.primarySoft
            : WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        child: InkWell(
          onTap: _opening ? null : _open,
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          child: Padding(
            padding: const EdgeInsets.all(WebTuiSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 38,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: WebTuiColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(WebTuiRadii.md),
                    ),
                    child: Center(
                      child: _opening
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              CupertinoIcons.doc_fill,
                              size: 20,
                              color: WebTuiColors.primary,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.attachment.file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WebTuiTypography.labelSmall.copyWith(
                          color: WebTuiColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${_formatByteSize(widget.attachment.file.byteSize)} · Nhấn để mở',
                        style: WebTuiTypography.labelSmall.copyWith(
                          color: WebTuiColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({
    required this.width,
    this.height,
    this.loading = false,
  });

  final double width;
  final double? height;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height ?? width * 0.72,
      child: ColoredBox(
        color: WebTuiColors.primarySoft,
        child: Center(
          child: loading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  CupertinoIcons.photo,
                  color: WebTuiColors.primary,
                  size: 28,
                ),
        ),
      ),
    );
  }
}

Uri? attachmentDownloadUri(MessageAttachment attachment, Uri? apiBaseUri) {
  final rawPath = attachment.file.downloadPath.trim();
  if (rawPath.isEmpty) return null;
  final uri = Uri.tryParse(rawPath);
  if (uri == null) return null;
  final resolved = uri.hasScheme ? uri : apiBaseUri?.resolve(rawPath);
  if (resolved == null ||
      !redirectSafeHttpUriAllowed(resolved) ||
      resolved.host.isEmpty ||
      resolved.userInfo.isNotEmpty ||
      resolved.fragment.isNotEmpty) {
    return null;
  }
  return resolved;
}

bool attachmentUriCanUseInstanceCredentials({
  required Uri attachmentUri,
  required Uri apiBaseUri,
  required Uri activeInstanceOrigin,
}) {
  return serverOriginsMatch(attachmentUri, apiBaseUri) &&
      serverOriginsMatch(apiBaseUri, activeInstanceOrigin);
}

Future<_AttachmentDownloadBinding?> _captureAttachmentDownloadBinding({
  required WidgetRef ref,
  required Uri attachmentUri,
  required Uri? apiBaseUri,
}) async {
  final instanceScope = ref.read(activeServerDiscoveryProvider)?.instanceScope;
  if (instanceScope == null ||
      (apiBaseUri != null &&
          !serverOriginsMatch(apiBaseUri, instanceScope.origin))) {
    return null;
  }
  final tokenRepository = ref.read(authTokenRepositoryProvider);
  final guard = await tokenRepository.captureMutationGuard();
  if (guard == null || guard.instanceScopeId != instanceScope.storageId) {
    return null;
  }

  final usesInstanceCredentials =
      apiBaseUri != null &&
      attachmentUriCanUseInstanceCredentials(
        attachmentUri: attachmentUri,
        apiBaseUri: apiBaseUri,
        activeInstanceOrigin: instanceScope.origin,
      );
  String? bearerToken;
  if (usesInstanceCredentials) {
    bearerToken = (await tokenRepository.readAccessTokenIfCurrent(
      guard,
    ))?.trim();
    if (bearerToken == null || bearerToken.isEmpty) return null;
  }
  if (!await tokenRepository.isMutationGuardCurrent(guard)) return null;
  return _AttachmentDownloadBinding(
    instanceScope: instanceScope,
    guard: guard,
    bearerToken: bearerToken,
    tokenRepository: tokenRepository,
  );
}

final class _AttachmentDownloadBinding {
  const _AttachmentDownloadBinding({
    required this.instanceScope,
    required this.guard,
    required this.bearerToken,
    required AuthTokenRepository tokenRepository,
  }) : _tokenRepository = tokenRepository;

  final InstanceScope instanceScope;
  final AuthTokenMutationGuard guard;
  final String? bearerToken;
  final AuthTokenRepository _tokenRepository;

  Future<bool> isStillCurrent() {
    return _tokenRepository.isMutationGuardCurrent(guard);
  }
}

Future<void> _disposeVideo(
  VideoPlayerController? controller,
  File? file,
) async {
  try {
    await controller?.dispose();
  } finally {
    if (file != null) await _deleteFile(file);
  }
}

Future<void> _disposeAudio(AudioPlayer player, File? file) async {
  try {
    await player.dispose();
  } finally {
    if (file != null) await _deleteFile(file);
  }
}

Future<void> _deleteFile(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on Object {
    // Session-scoped cache cleanup is the final best-effort fallback.
  }
}

const int maxImagePreviewBytes = 5 * 1024 * 1024;
const int maxVoicePlaybackBytes = 100 * 1024 * 1024;
const int maxVideoPlaybackBytes = 250 * 1024 * 1024;

final _imageDownloadGate = _BoundedAsyncGate(3);
final _voiceDownloadGate = _BoundedAsyncGate(2);
final _videoDownloadGate = _BoundedAsyncGate(2);

final class _BoundedAsyncGate {
  _BoundedAsyncGate(this.maximumConcurrent);

  final int maximumConcurrent;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() operation) async {
    if (_active < maximumConcurrent) {
      _active += 1;
    } else {
      final waiter = Completer<void>();
      _waiters.addLast(waiter);
      await waiter.future;
    }
    try {
      return await operation();
    } finally {
      if (_waiters.isNotEmpty) {
        // Transfer this occupied slot directly to the oldest waiter.
        _waiters.removeFirst().complete();
      } else {
        _active -= 1;
      }
    }
  }
}

bool attachmentPreviewWithinLimit(int byteSize, {required int maxBytes}) {
  return byteSize > 0 && byteSize <= maxBytes;
}

String _formatDuration(Duration value) {
  final totalSeconds = value.inSeconds.clamp(0, 359999);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _rateLabel(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

String _formatByteSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
