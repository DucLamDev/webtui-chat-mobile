import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
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
  Future<Uint8List?>? _imageFuture;

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
        oldWidget.apiBaseUri != widget.apiBaseUri) {
      _reload();
    }
  }

  void _reload() {
    final uri = attachmentDownloadUri(widget.attachment, widget.apiBaseUri);
    _imageFuture = uri == null ? Future<Uint8List?>.value() : _load(uri);
  }

  Future<Uint8List?> _load(Uri uri) async {
    final result = await ref
        .read(downloadMessageAttachmentBytesUseCaseProvider)
        .execute(downloadUri: uri, mimeType: widget.attachment.file.mimeType);
    final bytes = result.valueOrNull;
    return bytes == null || bytes.isEmpty ? null : bytes;
  }

  @override
  Widget build(BuildContext context) {
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
            child: FutureBuilder<Uint8List?>(
              future: _imageFuture,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _ImagePlaceholder(
                    height: widget.height,
                    width: widget.maxWidth,
                    loading: true,
                  );
                }
                if (bytes == null || bytes.isEmpty) {
                  return _ImagePlaceholder(
                    height: widget.height,
                    width: widget.maxWidth,
                  );
                }
                return Image.memory(
                  bytes,
                  fit: widget.fit,
                  height: widget.height,
                  width: widget.maxWidth,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _ImagePlaceholder(
                    height: widget.height,
                    width: widget.maxWidth,
                  ),
                );
              },
            ),
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
  Uint8List? _bytes;
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
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_bytes == null) {
      await _loadAndPlay();
      return;
    }
    if (_playerState == PlayerState.completed) {
      await _player.play(
        BytesSource(_bytes!, mimeType: widget.attachment.file.mimeType),
      );
      return;
    }
    await _player.resume();
  }

  Future<void> _loadAndPlay() async {
    final uri = attachmentDownloadUri(widget.attachment, widget.apiBaseUri);
    if (uri == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    final result = await ref
        .read(downloadMessageAttachmentBytesUseCaseProvider)
        .execute(downloadUri: uri, mimeType: widget.attachment.file.mimeType);
    if (!mounted) return;
    switch (result) {
      case Success<Uint8List>(value: final bytes) when bytes.isNotEmpty:
        _bytes = bytes;
        setState(() => _loading = false);
        await _player.play(
          BytesSource(bytes, mimeType: widget.attachment.file.mimeType),
        );
      default:
        setState(() {
          _loading = false;
          _failed = true;
        });
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
  return uri.hasScheme ? uri : apiBaseUri?.resolve(rawPath);
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
