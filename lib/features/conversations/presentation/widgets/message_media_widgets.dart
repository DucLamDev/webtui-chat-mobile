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
import '../../../../core/audio/playable_audio.dart';
import '../../../../core/media/exclusive_media_playback.dart';
import '../../../../core/media/media_playback.dart';
import '../../../../core/network/media_auto_download_policy.dart';
import '../../../../core/network/recent_download_failures.dart';
import '../../../../core/network/redirect_safe_file_downloader.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../../core/storage/cached_image_bytes.dart';
import '../../../../design_system/components/webtui_owned_decoded_image.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../auth/domain/repositories/auth_token_repository.dart';
import '../../application/use_cases/message_attachment_use_cases.dart';
import '../../data/files/attachment_media_cache_keys.dart';
import '../../data/files/scoped_attachment_file_store.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_voice.dart';
import '../controllers/media_cache_providers.dart';
import '../controllers/media_gallery_saver.dart';
import '../controllers/message_video_stream.dart';
import '../controllers/voice_playback_link.dart';

export '../../data/files/attachment_media_cache_keys.dart'
    show attachmentDownloadUri, attachmentThumbnailUri, galleryFileName;

Future<void> openMessageImageGallery(
  BuildContext context, {
  required List<MessageAttachment> attachments,
  required int initialIndex,
  Uri? apiBaseUri,
  String? title,
}) {
  if (attachments.isEmpty) return Future.value();
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _MessageImageGalleryScreen(
        apiBaseUri: apiBaseUri,
        attachments: attachments,
        initialIndex: initialIndex.clamp(0, attachments.length - 1),
        title: title ?? tr('Ảnh đã gửi', 'Sent photos'),
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
  bool _saving = false;

  Future<void> _saveCurrent() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await saveMessageAttachmentsToGallery(
        context,
        attachments: [widget.attachments[_index]],
        apiBaseUri: widget.apiBaseUri,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
        actions: [
          if (isGallerySaveable(widget.attachments[_index]))
            IconButton(
              key: const ValueKey('gallery-save'),
              tooltip: tr('Lưu ảnh về máy', 'Save photo to device'),
              onPressed: _saving ? null : _saveCurrent,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(WebTuiIcons.download),
            ),
          const SizedBox(width: 4),
        ],
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
                preferThumbnail: false,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Giờ gửi nằm góc dưới phải TRÊN ảnh / video, trong viên nền tối mờ.
class MessageMediaTimeBadge extends StatelessWidget {
  const MessageMediaTimeBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      bottom: 8,
      child: DecoratedBox(
        key: const Key('message_media_time_badge'),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            label,
            style: WebTuiTypography.labelSmall.copyWith(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tỉ lệ rộng / cao đã biết của ảnh, video theo mã tệp (bộ nhớ trong, có giới
/// hạn số mục) để cuộn lên xuống không bị nhảy khung.
final class MessageMediaAspectCache {
  const MessageMediaAspectCache._();

  static const int maxEntries = 256;
  static final LinkedHashMap<String, double> _entries =
      LinkedHashMap<String, double>();

  static double? get(String key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  static void put(String key, double ratio) {
    if (key.isEmpty || !ratio.isFinite || ratio <= 0) return;
    _entries.remove(key);
    _entries[key] = ratio;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  static int get length => _entries.length;

  @visibleForTesting
  static void clear() => _entries.clear();
}

const double messageMediaMinRatio = 0.5;
const double messageMediaMaxRatio = 2.0;
const double messageMediaUnknownRatio = 4 / 3;

/// Kích thước ô ảnh / video ôm đúng tỉ lệ (kẹp [0.5, 2.0]) trong khung tối đa:
/// ảnh dọc cao tối đa, ảnh ngang rộng tối đa.
Size fitMessageMediaBox({
  required double ratio,
  required double maxWidth,
  required double maxHeight,
}) {
  final safe = ratio.isFinite && ratio > 0 ? ratio : messageMediaUnknownRatio;
  final clamped = safe.clamp(messageMediaMinRatio, messageMediaMaxRatio);
  var width = maxWidth;
  var height = width / clamped;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * clamped;
  }
  return Size(width, height);
}

/// Giới hạn ô ảnh / video đơn trong bong bóng (theo bề ngang màn hình).
Size messageMediaMaxBox(BuildContext context) {
  final viewportWidth = MediaQuery.sizeOf(context).width;
  return Size(
    (viewportWidth * 0.66).clamp(188, 258).toDouble(),
    (viewportWidth * 0.72).clamp(188, 286).toDouble(),
  );
}

Widget _coverVideo(VideoPlayerController controller) {
  final size = controller.value.size;
  if (size.width <= 0 || size.height <= 0) return VideoPlayer(controller);
  return FittedBox(
    fit: BoxFit.cover,
    clipBehavior: Clip.hardEdge,
    child: SizedBox(
      width: size.width,
      height: size.height,
      child: VideoPlayer(controller),
    ),
  );
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
    this.preferThumbnail = true,
    this.timeLabel,
    this.adaptive = false,
    super.key,
  });

  final MessageAttachment attachment;
  final Uri? apiBaseUri;

  /// Ô ôm sát đúng tỉ lệ ảnh thật (trong khung [maxWidth] x [maxHeight]) thay
  /// vì rộng cố định; dùng cho ảnh đơn trong bong bóng.
  final bool adaptive;

  /// Giờ gửi hiện trên góc dưới phải của ảnh (null: không hiện).
  final String? timeLabel;

  /// Dùng ảnh thu nhỏ (nếu máy chủ có) cho danh sách / bong bóng; màn xem ảnh
  /// đặt `false` để mở bản gốc (tới [maxImageFullscreenBytes], lớn hơn nữa
  /// thì dùng ảnh thu nhỏ).
  final bool preferThumbnail;
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
  Uri? _thumbnailUri;
  File? _localImageFile;
  int _loadGeneration = 0;
  double? _reportedRatio;
  ImageStream? _sizeStream;
  ImageStreamListener? _sizeListener;

  /// Đang dùng dữ liệu di động, người dùng tắt tự tải ảnh và ảnh chưa có
  /// trong kho: hiện ô "Chạm để tải ảnh" thay cho ảnh.
  bool _needsTapToDownload = false;

  /// Người dùng đã chạm "Chạm để tải ảnh": tải bất kể loại mạng.
  bool _manualDownload = false;

  /// Lượt tải vừa rồi bị dừng vì chưa được tự tải (xem [_needsTapToDownload]).
  bool _blockedByNetwork = false;

  /// Cỡ tối đa của ảnh gốc: bong bóng [maxImagePreviewBytes], màn xem toàn
  /// màn hình [maxImageFullscreenBytes] (giải mã vẫn giới hạn 2048 px).
  int get _originalLimit =>
      widget.preferThumbnail ? maxImagePreviewBytes : maxImageFullscreenBytes;

  String get _ratioKey {
    final attachment = widget.attachment;
    return attachment.fileId.isNotEmpty ? attachment.fileId : attachment.id;
  }

  double? get _knownRatio {
    final file = widget.attachment.file;
    final width = file.width ?? 0;
    final height = file.height ?? 0;
    if (width > 0 && height > 0) return width / height;
    return MessageMediaAspectCache.get(_ratioKey) ?? _reportedRatio;
  }

  void _onImageSize(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final ratio = size.width / size.height;
    MessageMediaAspectCache.put(_ratioKey, ratio);
    scheduleMicrotask(() {
      if (!mounted || _reportedRatio == ratio) return;
      setState(() => _reportedRatio = ratio);
    });
  }

  void _stopSizeListener() {
    final stream = _sizeStream;
    final listener = _sizeListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _sizeStream = null;
    _sizeListener = null;
  }

  void _listenLocalSize(File file) {
    _stopSizeListener();
    if (!widget.adaptive || _knownRatio != null) return;
    final stream = FileImage(file).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      _onImageSize(
        Size(info.image.width.toDouble(), info.image.height.toDouble()),
      );
    }, onError: (_, _) {});
    stream.addListener(listener);
    _sizeStream = stream;
    _sizeListener = listener;
  }

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
        oldWidget.attachment.file.thumbnailUrl !=
            widget.attachment.file.thumbnailUrl ||
        oldWidget.preferThumbnail != widget.preferThumbnail ||
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
    _needsTapToDownload = false;
    _manualDownload = false;
    final localPath = widget.attachment.file.localPath?.trim();
    if (widget.attachment.isImage &&
        localPath != null &&
        localPath.isNotEmpty) {
      _localImageFile = File(localPath);
      _imageUri = null;
      _thumbnailUri = null;
      _listenLocalSize(_localImageFile!);
      return;
    }
    _localImageFile = null;
    _stopSizeListener();
    final uri = attachmentDownloadUri(widget.attachment, widget.apiBaseUri);
    _imageUri =
        uri != null &&
            attachmentPreviewWithinLimit(
              widget.attachment.file.byteSize,
              maxBytes: _originalLimit,
            )
        ? uri
        : null;
    // Màn toàn màn hình: ảnh gốc quá lớn thì vẫn còn ảnh thu nhỏ để xem.
    _thumbnailUri = widget.preferThumbnail || _imageUri == null
        ? attachmentThumbnailUri(widget.attachment, widget.apiBaseUri)
        : null;
  }

  Future<Uint8List?> _load(Uri uri, int generation) async {
    _blockedByNetwork = false;
    var bytes = await _loadOnce(uri, generation);
    final original = _imageUri;
    if (bytes == null && uri == _thumbnailUri && original != null) {
      // Ảnh thu nhỏ chưa có / lỗi: quay về ảnh gốc như trước.
      bytes = await _loadOnce(original, generation);
    }
    if (bytes == null &&
        _blockedByNetwork &&
        mounted &&
        generation == _loadGeneration) {
      scheduleMicrotask(() {
        if (!mounted || generation != _loadGeneration) return;
        setState(() => _needsTapToDownload = true);
      });
    }
    return bytes;
  }

  /// Ảnh chưa có trên máy có được tự tải không (dữ liệu di động + công tắc
  /// tắt thì không); ảnh đã có trong kho luôn hiện ngay.
  Future<bool> _mayDownload(File cacheFile) async {
    if (_manualDownload || !mounted) return true;
    final policy = ref.read(mediaAutoDownloadPolicyProvider);
    if (await policy.canAutoDownloadImage()) return true;
    return await attachmentMediaCache.lookup(cacheFile) != null;
  }

  /// Chạm "Chạm để tải ảnh": tải ảnh này bất kể loại mạng.
  void _downloadManually() {
    setState(() {
      _needsTapToDownload = false;
      _manualDownload = true;
      _loadGeneration += 1;
    });
  }

  Future<Uint8List?> _loadOnce(Uri uri, int generation) async {
    final binding = await _captureAttachmentDownloadBinding(
      read: ref.read,
      attachmentUri: uri,
      apiBaseUri: widget.apiBaseUri,
    );
    if (binding == null) return null;
    Future<bool> isCurrent() async =>
        mounted &&
        generation == _loadGeneration &&
        await binding.isStillCurrent();
    final maxBytes = uri == _thumbnailUri
        ? maxImagePreviewBytes
        : _originalLimit;
    final cacheFile = await binding.cacheFile(
      purpose: 'image',
      uri: uri,
      variant: attachmentImageCacheVariant(widget.attachment),
    );
    if (!await _mayDownload(cacheFile)) {
      _blockedByNetwork = true;
      return null;
    }
    // Kho đệm 7 ngày trên máy; ảnh vừa bị từ chối (403 / 404) thì không hỏi
    // lại máy chủ mỗi lần vẽ lại.
    final bytes = await loadCachedImageBytes(
      cache: attachmentMediaCache,
      failures: mediaDownloadFailures,
      failureKey: binding.failureKey(uri),
      file: cacheFile,
      maxBytes: maxBytes,
      download: () => _imageDownloadGate.run(
        () => _downloader.downloadBytes(
          uri: uri,
          maxBytes: maxBytes,
          accept: uri == _thumbnailUri
              ? 'image/jpeg'
              : widget.attachment.file.mimeType,
          bearerToken: binding.bearerToken,
          isStillCurrent: isCurrent,
        ),
      ),
      // Đăng xuất / đổi phiên giữa chừng thì không ghi vào kho.
      isStillCurrent: binding.isStillCurrent,
    );
    return bytes != null && await isCurrent() ? bytes : null;
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _stopSizeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uri = _thumbnailUri ?? _imageUri;
    final localImageFile = _localImageFile;
    final generation = _loadGeneration;
    final adaptive = widget.adaptive;
    final box = adaptive
        ? fitMessageMediaBox(
            ratio: _knownRatio ?? messageMediaUnknownRatio,
            maxWidth: widget.maxWidth,
            maxHeight: widget.maxHeight,
          )
        : null;
    final boxWidth = box?.width ?? widget.maxWidth;
    final boxHeight = box?.height ?? widget.height;
    final boxFit = adaptive ? BoxFit.cover : widget.fit;
    final placeholder = _ImagePlaceholder(height: boxHeight, width: boxWidth);
    final image = localImageFile == null && uri != null && _needsTapToDownload
        ? _ImagePlaceholder(
            height: boxHeight,
            width: boxWidth,
            onTapToDownload: _downloadManually,
          )
        : localImageFile != null
        ? Image.file(
            localImageFile,
            width: boxWidth,
            height: boxHeight,
            fit: boxFit,
            errorBuilder: (_, _, _) => placeholder,
          )
        : uri == null
        ? placeholder
        : WebTuiOwnedDecodedImage(
            requestKey:
                '$uri|${widget.attachment.file.byteSize}|'
                '${widget.attachment.file.mimeType}|$generation',
            loadBytes: () => _load(uri, generation),
            maxEncodedBytes: _originalLimit,
            decodeTargetWidth: (boxWidth * 3).ceil().clamp(1, 2048),
            decodeTargetHeight: widget.maxHeight.isFinite
                ? (widget.maxHeight * 3).ceil().clamp(1, 2048)
                : 2048,
            width: boxWidth,
            height: boxHeight,
            fit: boxFit,
            onImageSize: adaptive ? _onImageSize : null,
            loading: _ImagePlaceholder(
              height: boxHeight,
              width: boxWidth,
              loading: true,
            ),
            fallback: placeholder,
          );
    return Semantics(
      button: widget.onPressed != null,
      label: tr(
        'Mở ảnh ${widget.attachment.file.name}',
        'Open photo ${widget.attachment.file.name}',
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        onTap: widget.onPressed,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: widget.maxHeight,
                  maxWidth: widget.maxWidth,
                ),
                child: image,
              ),
              if (widget.timeLabel != null)
                MessageMediaTimeBadge(label: widget.timeLabel!),
            ],
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
    this.voice,
    this.playbackLink,
    this.outgoing = false,
    super.key,
  });

  final MessageAttachment attachment;
  final Uri? apiBaseUri;

  /// Tin của mình: bong bóng xanh nhạt; tin người khác: bong bóng trắng.
  final bool outgoing;

  /// `metadata.voice` của tin: hiện thời lượng và sóng âm trước khi tải tệp.
  final MessageVoiceMetadata? voice;

  /// Nối với phần "Xem lời": báo vị trí đang phát, nhận lệnh tua tới một đoạn.
  final VoicePlaybackLink? playbackLink;

  @override
  ConsumerState<MessageVoiceAttachmentView> createState() =>
      _MessageVoiceAttachmentViewState();
}

class _MessageVoiceAttachmentViewState
    extends ConsumerState<MessageVoiceAttachmentView> {
  static const _downloader = RedirectSafeFileDownloader();
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
  String? _playablePath;
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
    widget.playbackLink?.attach(_seekAndPlay);
    _subscriptions
      ..add(
        _player.onDurationChanged.listen((duration) {
          if (mounted) setState(() => _duration = duration);
        }),
      )
      ..add(
        _player.onPositionChanged.listen((position) {
          if (!mounted) return;
          setState(() => _position = position);
          widget.playbackLink?.reportPosition(position.inMilliseconds);
        }),
      )
      ..add(
        _player.onPlayerStateChanged.listen((state) {
          if (mounted) setState(() => _playerState = state);
        }),
      )
      ..add(
        _player.onPlayerComplete.listen((_) {
          ExclusiveMediaPlayback.release(this);
          if (mounted) {
            setState(() {
              _position = Duration.zero;
              _playerState = PlayerState.completed;
            });
            widget.playbackLink?.reportPosition(0);
          }
        }),
      );
  }

  @override
  void dispose() {
    ExclusiveMediaPlayback.release(this);
    widget.playbackLink?.detach(_seekAndPlay);
    _loadGeneration += 1;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageVoiceAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.playbackLink, widget.playbackLink)) {
      oldWidget.playbackLink?.detach(_seekAndPlay);
      widget.playbackLink?.attach(_seekAndPlay);
    }
    if (oldWidget.attachment.file.downloadPath !=
            widget.attachment.file.downloadPath ||
        oldWidget.apiBaseUri != widget.apiBaseUri) {
      _loadGeneration += 1;
      _audioFile = null;
      _playablePath = null;
      _binding = null;
      _loading = false;
      _failed = false;
      unawaited(_player.stop());
      widget.playbackLink?.reportPosition(0);
    }
  }

  /// Nguồn phát khác (tin thoại / video khác) bắt đầu phát: tạm dừng tin này.
  Future<void> _pauseForOther() async {
    if (_playing) await _player.pause();
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
    // Chỉ một nguồn có tiếng tại một thời điểm.
    ExclusiveMediaPlayback.claim(this, _pauseForOther);
    if (_playerState == PlayerState.completed) {
      await _player.play(
        DeviceFileSource(
          _playablePath ?? _audioFile!.path,
          mimeType: _playablePath == null
              ? widget.attachment.file.mimeType
              : 'audio/wav',
        ),
      );
      return;
    }
    await _player.resume();
  }

  Future<void> _loadAndPlay() async {
    final generation = ++_loadGeneration;
    // Tải xong chỉ tự phát khi người dùng chưa bấm phát cái khác / chưa gọi.
    final playToken = ExclusiveMediaPlayback.beginRequest();
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
    try {
      final binding = await _captureAttachmentDownloadBinding(
        read: ref.read,
        attachmentUri: uri,
        apiBaseUri: widget.apiBaseUri,
      );
      if (binding == null) throw StateError('instance binding unavailable');
      Future<bool> operationIsCurrent() async {
        return mounted &&
            generation == _loadGeneration &&
            await binding.isStillCurrent();
      }

      // Kho đệm 7 ngày của tài khoản: nghe lại không tải lại. Lượt tải chỉ
      // dừng khi đổi phiên (không dừng khi cuộn khỏi bong bóng): bong bóng
      // dựng lại tự nối vào lượt đang tải, không tải lại từ đầu. Lượt tải có
      // thể chạy sau khi bong bóng đã huỷ: không đọc `widget` trong đó.
      final file = widget.attachment.file;
      final readyFile = await attachmentMediaCache.ensureFile(
        await binding.cacheFile(
          purpose: 'voice',
          uri: uri,
          originalName: file.name,
        ),
        expectedBytes: file.byteSize,
        download: (target) => _voiceDownloadGate.run(
          () => _downloader.download(
            uri: uri,
            target: target,
            maxBytes: maxVoicePlaybackBytes,
            expectedBytes: file.byteSize,
            accept: file.mimeType,
            bearerToken: binding.bearerToken,
            isStillCurrent: binding.isStillCurrent,
          ),
        ),
      );
      if (!mounted ||
          generation != _loadGeneration ||
          !await operationIsCurrent()) {
        throw StateError('instance binding changed');
      }
      // iPhone: AVPlayer không đọc được WebM / Ogg, đổi sang WAV trước khi phát.
      String? playablePath;
      if (audioNeedsTranscode(
        name: widget.attachment.file.name,
        mimeType: widget.attachment.file.mimeType,
      )) {
        final playable = await playableAudioFile(
          source: readyFile,
          cacheKey: attachmentPlayableAudioCacheKey(widget.attachment),
          // WAV nằm trong kho đệm của tài khoản trên máy chủ này: dùng lại 7
          // ngày; đăng xuất / đổi máy chủ / thu hồi phiên xoá cùng tệp đính kèm.
          cacheDirectory: await binding.cacheDirectory('playable-audio'),
        );
        if (playable.path != readyFile.path) playablePath = playable.path;
        if (!mounted ||
            generation != _loadGeneration ||
            !await operationIsCurrent()) {
          throw StateError('instance binding changed');
        }
      }
      _audioFile = readyFile;
      _playablePath = playablePath;
      _binding = binding;
      setState(() => _loading = false);
      if (!ExclusiveMediaPlayback.isLatestRequest(playToken)) {
        // Trong lúc tải, người dùng đã phát tin khác hoặc bắt đầu cuộc gọi:
        // để sẵn sàng, bấm lần nữa mới phát.
        return;
      }
      ExclusiveMediaPlayback.claim(this, _pauseForOther);
      await _player.play(
        DeviceFileSource(
          playablePath ?? readyFile.path,
          mimeType: playablePath == null
              ? widget.attachment.file.mimeType
              : 'audio/wav',
        ),
      );
    } on Object {
      // Tệp trong kho đệm dùng chung: không xoá ở đây, kho tự dọn sau 7 ngày.
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

  /// Phần "Xem lời" chạm một đoạn: phát (tải tệp nếu chưa có) rồi tua tới đầu đoạn.
  Future<void> _seekAndPlay(int milliseconds) async {
    if (_loading) return;
    if (!_playing) await _togglePlayback();
    if (!mounted || _failed || _audioFile == null) return;
    final target = Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);
    await _player.seek(target);
    if (!mounted) return;
    setState(() => _position = target);
    widget.playbackLink?.reportPosition(target.inMilliseconds);
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
    final metadataWaveform = widget.voice?.waveform ?? const <int>[];
    final waveform = metadataWaveform.isEmpty
        ? _waveform
        : [for (final level in metadataWaveform) 4 + level * 24 / 100];
    final knownDuration = _duration > Duration.zero
        ? _duration
        : widget.voice?.duration ?? Duration.zero;
    return SizedBox(
      width: width.toDouble(),
      child: DecoratedBox(
        key: const Key('message_voice_bubble'),
        decoration: BoxDecoration(
          color: widget.outgoing
              ? WebTuiColors.messageOutgoing
              : WebTuiColors.messageIncoming,
          borderRadius: BorderRadius.circular(24),
          boxShadow: widget.outgoing
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x14172033),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 14, 5),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 36,
                child: IconButton.filled(
                  tooltip: _playing
                      ? tr('Tạm dừng', 'Pause')
                      : tr('Phát tin nhắn thoại', 'Play voice message'),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: WebTuiColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _loading ? null : _togglePlayback,
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _playing ? WebTuiIcons.pause : WebTuiIcons.play,
                          size: 18,
                        ),
                ),
              ),
              const SizedBox(width: 10),
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
                        for (var index = 0; index < waveform.length; index++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0.6,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: index / waveform.length <= progress
                                      ? WebTuiColors.primary
                                      : const Color(0xFF9AA9C2),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: SizedBox(height: waveform[index]),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _failed
                    ? '--:--'
                    : _formatDuration(_playing ? _position : knownDuration),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_playing) ...[
                const SizedBox(width: 3),
                TextButton(
                  onPressed: _cycleRate,
                  style: TextButton.styleFrom(
                    foregroundColor: WebTuiColors.primary,
                    minimumSize: const Size(28, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('${_rateLabel(_playbackRate)}x'),
                ),
              ],
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
    this.uploadProgress,
    this.uploadStage,
    this.timeLabel,
    super.key,
  });

  final MessageAttachment attachment;
  final Uri? apiBaseUri;
  final bool allowFullscreen;

  /// Giờ gửi hiện trên góc dưới phải của khung video (null: không hiện, và
  /// còn dòng tên tệp phía dưới như trước).
  final String? timeLabel;

  /// Tiến độ nén / tải lên 0..1 của bong bóng tạm (null: không hiện vòng).
  final double? uploadProgress;

  /// `compressing` hoặc `uploading` (chỉ dùng khi [uploadProgress] có giá trị).
  final String? uploadStage;

  /// Video của bong bóng tạm: còn trên máy, chưa có trên máy chủ.
  bool get isLocalPreview {
    final path = attachment.file.localPath?.trim() ?? '';
    return attachment.file.status == 'local-preview' && path.isNotEmpty;
  }

  @override
  ConsumerState<MessageVideoAttachmentView> createState() =>
      _MessageVideoAttachmentViewState();
}

class _MessageVideoAttachmentViewState
    extends ConsumerState<MessageVideoAttachmentView> {
  static const _downloader = RedirectSafeFileDownloader();

  double? _thumbnailRatio;

  void _onThumbnailSize(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final ratio = size.width / size.height;
    final key = widget.attachment.fileId.isNotEmpty
        ? widget.attachment.fileId
        : widget.attachment.id;
    MessageMediaAspectCache.put(key, ratio);
    scheduleMicrotask(() {
      if (!mounted || _thumbnailRatio == ratio) return;
      setState(() => _thumbnailRatio = ratio);
    });
  }

  VideoPlayerController? _controller;
  _AttachmentDownloadBinding? _binding;
  int _initializationGeneration = 0;
  bool _loading = false;
  bool _failed = false;

  /// [_controller] phát dần từ đường `/stream` (mã sống 15 phút): lỗi giữa
  /// chừng (tạm dừng lâu, video dài) thì xin đường mới rồi phát tiếp.
  bool _controllerStreamed = false;

  /// Trạng thái trình phát đã vẽ lên màn: listener chỉ vẽ lại khi đổi.
  bool _shownPlaying = false;
  bool _shownCompleted = false;
  bool _shownError = false;

  /// Vị trí gần nhất trước khi lỗi (giá trị lỗi của trình phát xoá hết vị
  /// trí): khôi phục thì tua về đây.
  Duration _lastPosition = Duration.zero;

  /// Người dùng muốn video đang chạy (bấm phát, chưa tạm dừng / chưa hết):
  /// khôi phục xong thì phát tiếp.
  bool _wantsPlaying = false;

  final MessageVideoRecoveryBudget _recoveryBudget =
      MessageVideoRecoveryBudget();

  /// Tiến độ tải chung (theo tệp kho) mà bong bóng này đang theo dõi.
  ValueNotifier<double>? _progressSource;

  /// Phần đã tải (0..1) khi phải tải cả video về máy rồi mới phát (iPhone).
  double? _downloadProgress;

  /// Bấm nút phát trên ảnh bìa: sẵn sàng thì phát luôn.
  bool _playWhenReady = false;

  /// Đã xét tải ngầm video phát dần này vào kho (mỗi video một lần).
  bool _backgroundCacheChecked = false;

  /// Số khung xem trước (video cũ chưa có ảnh bìa) đang giữ bộ giải mã; giới
  /// hạn để cuộn qua nhiều video không làm cạn bộ giải mã của máy.
  static int _activePreviews = 0;
  static const int _maxActivePreviews = 3;
  bool _previewCounted = false;
  bool _previewTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPreview());
  }

  /// Video cũ không có ảnh bìa: mở đường phát dần rồi dừng ở khung đầu, để
  /// bong bóng có hình xem trước và bấm phát chạy ngay.
  void _startPreview() {
    if (!mounted ||
        _previewTried ||
        widget.isLocalPreview ||
        _controller != null ||
        _loading ||
        attachmentThumbnailUri(widget.attachment, widget.apiBaseUri) != null ||
        !widget.allowFullscreen) {
      return;
    }
    _previewTried = true;
    if (_activePreviews >= _maxActivePreviews) return;
    _activePreviews += 1;
    _previewCounted = true;
    unawaited(_initialize(previewOnly: true));
  }

  void _releasePreviewSlot() {
    if (!_previewCounted) return;
    _previewCounted = false;
    _activePreviews -= 1;
  }

  @override
  void didUpdateWidget(covariant MessageVideoAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.file.downloadPath !=
            widget.attachment.file.downloadPath ||
        oldWidget.apiBaseUri != widget.apiBaseUri) {
      _initializationGeneration += 1;
      final previous = _swapController(null);
      ExclusiveMediaPlayback.release(this);
      _stopWatchingProgress();
      _binding = null;
      _loading = false;
      _failed = false;
      _playWhenReady = false;
      _wantsPlaying = false;
      _downloadProgress = null;
      _previewTried = false;
      _backgroundCacheChecked = false;
      _releasePreviewSlot();
      unawaited(previous?.dispose());
      WidgetsBinding.instance.addPostFrameCallback((_) => _startPreview());
    }
  }

  void _requestDownload() {
    if (_loading || _controller != null) return;
    unawaited(_initialize());
  }

  /// Bấm vào video: phát; video vừa lỗi thì thử tải lại (mạng chập chờn).
  void _onPlayTapped() {
    _playWhenReady = true;
    _playRequestToken = ExclusiveMediaPlayback.beginRequest();
    _requestDownload();
  }

  /// Chạm vòng chờ (vd. đang mở khung xem trước, tới 24 giây): sẵn sàng thì
  /// phát luôn, không bắt chạm lại.
  void _onLoadingTapped() {
    _playWhenReady = true;
    _playRequestToken = ExclusiveMediaPlayback.beginRequest();
  }

  /// Mã lượt bấm phát (xem [ExclusiveMediaPlayback.beginRequest]): sẵn sàng
  /// thì chỉ tự phát khi vẫn là lượt mới nhất.
  int _playRequestToken = -1;

  /// Thay trình phát: gỡ listener của trình phát cũ, gắn vào trình phát mới.
  /// Trả trình phát cũ để nơi gọi huỷ.
  VideoPlayerController? _swapController(
    VideoPlayerController? next, {
    bool streamed = false,
  }) {
    final previous = _controller;
    previous?.removeListener(_onControllerChanged);
    _controller = next;
    _controllerStreamed = next != null && streamed;
    if (next != null) {
      final value = next.value;
      _shownPlaying = value.isPlaying;
      _shownCompleted = _videoCompleted(value);
      _shownError = value.hasError;
      if (!value.hasError) _lastPosition = value.position;
      next.addListener(_onControllerChanged);
    }
    return previous;
  }

  static bool _videoCompleted(VideoPlayerValue value) {
    return value.isInitialized &&
        !value.isPlaying &&
        value.duration > Duration.zero &&
        value.position >= value.duration;
  }

  /// Trình phát đổi trạng thái: vẽ lại nút Phát / Tạm dừng và nhãn thời lượng
  /// khi đang phát / đã hết / lỗi đổi; lỗi thì thử khôi phục.
  void _onControllerChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (!value.hasError) _lastPosition = value.position;
    final playing = value.isPlaying;
    final completed = _videoCompleted(value);
    final error = value.hasError;
    if (playing == _shownPlaying &&
        completed == _shownCompleted &&
        error == _shownError) {
      return;
    }
    final becameCompleted = completed && !_shownCompleted;
    final becameError = error && !_shownError;
    setState(() {
      _shownPlaying = playing;
      _shownCompleted = completed;
      _shownError = error;
    });
    if (becameCompleted) {
      _wantsPlaying = false;
      ExclusiveMediaPlayback.release(this);
    }
    if (becameError) unawaited(_onPlaybackError(controller));
  }

  /// Trình phát báo lỗi. Phát dần (đường có mã sống 15 phút): xin đường mới,
  /// tua về chỗ cũ, phát tiếp nếu đang phát (tối đa
  /// [MessageVideoRecoveryBudget.maxAttempts] lần mỗi phút); không phát dần
  /// lại được thì [_initialize] tự lùi về tải tệp. Quá số lần / tệp trên máy
  /// lỗi: hiện trạng thái lỗi có nút thử lại.
  Future<void> _onPlaybackError(VideoPlayerController failed) async {
    if (!mounted || !identical(_controller, failed)) return;
    final action = messageVideoErrorAction(
      streamed: _controllerStreamed,
      budget: _recoveryBudget,
      now: DateTime.now(),
    );
    final resumeAt = _lastPosition;
    final resumePlaying = _wantsPlaying;
    _initializationGeneration += 1;
    _swapController(null);
    ExclusiveMediaPlayback.release(this);
    _releasePreviewSlot();
    _binding = null;
    _wantsPlaying = false;
    if (action == MessageVideoErrorAction.fail) {
      _playWhenReady = false;
      setState(() {
        _loading = false;
        _failed = true;
      });
      await failed.dispose();
      return;
    }
    setState(() => _loading = true);
    await failed.dispose();
    if (!mounted) return;
    _playWhenReady = resumePlaying;
    // Phát tiếp sau khi khôi phục chỉ khi chưa có ai phát cái khác / gọi.
    _playRequestToken = ExclusiveMediaPlayback.currentRequest;
    await _initialize(freshStream: true, resumeAt: resumeAt);
  }

  /// Theo dõi tiến độ chung của lượt tải vào [path] (tạo mới nếu chưa có ai
  /// tải): bong bóng dựng lại vẫn thấy phần trăm của lượt đang chạy.
  ValueNotifier<double> _watchDownloadProgress(String path) {
    final notifier = _mediaDownloadProgress.putIfAbsent(
      path,
      () => ValueNotifier<double>(0),
    );
    _stopWatchingProgress();
    _progressSource = notifier..addListener(_onSharedProgress);
    if (notifier.value > 0) _onSharedProgress();
    return notifier;
  }

  void _stopWatchingProgress() {
    _progressSource?.removeListener(_onSharedProgress);
    _progressSource = null;
  }

  void _onSharedProgress() {
    final source = _progressSource;
    if (!mounted || source == null) return;
    final next = source.value.clamp(0.0, 1.0);
    final previous = _downloadProgress;
    // Chỉ vẽ lại khi đổi ít nhất 1%: tệp lớn có hàng nghìn khúc.
    if (previous != null && (next * 100).floor() == (previous * 100).floor()) {
      return;
    }
    setState(() => _downloadProgress = next);
  }

  /// Vòng chờ khi mở video; đang tải cả tệp về máy thì hiện phần trăm.
  Widget _buildLoadingIndicator() {
    final progress = _downloadProgress;
    final percent = progress == null ? null : (progress * 100).floor();
    return Semantics(
      label: percent == null
          ? tr('Đang mở video', 'Opening video')
          : tr('Đang tải video $percent%', 'Downloading video $percent%'),
      onTap: _onLoadingTapped,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onLoadingTapped,
        child: Container(
          key: const ValueKey('video-loading'),
          width: 56,
          height: 56,
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                color: Colors.white,
                backgroundColor: progress == null ? null : Colors.white24,
              ),
              if (percent != null)
                Center(
                  child: Text(
                    '$percent%',
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mở đường phát dần của video (xin link mới một lần nếu link cũ bị từ chối;
  /// [fresh]: bỏ qua link đã nhớ ngay từ đầu, dùng khi khôi phục sau lỗi).
  /// Trả null khi không phát dần được, lúc đó caller chuyển sang tải về.
  Future<VideoPlayerController?> _openStream(
    int generation, {
    bool fresh = false,
  }) async {
    // iPhone: phát dần hay đứng ở ảnh bìa; luôn tải về rồi phát tệp.
    if (preferLocalMediaPlayback()) return null;
    final workspaceId = workspaceIdFromFilePath(
      widget.attachment.file.downloadPath,
    );
    final fileId = widget.attachment.fileId;
    if (workspaceId == null || fileId.isEmpty) return null;
    for (final freshLink in fresh ? const [true] : const [false, true]) {
      final stream = await resolveMessageVideoStream(
        ref,
        workspaceId: workspaceId,
        fileId: fileId,
        fresh: freshLink,
      );
      if (stream == null ||
          !mounted ||
          generation != _initializationGeneration) {
        return null;
      }
      final ready = await initializeStreamOrNull(
        messageVideoStreamController(stream),
      );
      if (ready != null) return ready;
    }
    return null;
  }

  /// Mở video: phát dần nếu được, không thì tải cả tệp vào kho rồi phát.
  /// [freshStream]: xin đường phát dần mới (khôi phục sau lỗi); [resumeAt]:
  /// tua tới vị trí này khi trình phát sẵn sàng.
  Future<void> _initialize({
    bool previewOnly = false,
    bool freshStream = false,
    Duration? resumeAt,
  }) async {
    final generation = ++_initializationGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _downloadProgress = null;
      });
    }
    final uri = attachmentDownloadUri(widget.attachment, widget.apiBaseUri);
    if (uri == null) {
      _markVideoFailure(generation, previewOnly: previewOnly);
      return;
    }

    final binding = await _captureAttachmentDownloadBinding(
      read: ref.read,
      attachmentUri: uri,
      apiBaseUri: widget.apiBaseUri,
    );
    if (binding == null ||
        generation != _initializationGeneration ||
        !mounted) {
      _markVideoFailure(generation, previewOnly: previewOnly);
      return;
    }

    final byteSize = widget.attachment.file.byteSize;
    // Không rõ cỡ (máy chủ cũ): vẫn cho tải, không so cỡ.
    final expectedBytes = byteSize > 0 ? byteSize : null;
    VideoPlayerController? next;
    try {
      Future<bool> operationIsCurrent() async {
        return mounted &&
            generation == _initializationGeneration &&
            await binding.isStillCurrent();
      }

      // Đã tải về trong 7 ngày qua: phát thẳng tệp trên máy, không hỏi mạng.
      // Cùng tệp kho với "Lưu vào thư viện ảnh": xem rồi lưu không tải lại.
      final cacheTarget = await binding.cacheFile(
        purpose: 'video',
        uri: uri,
        originalName: galleryFileName(widget.attachment),
      );
      final cached = await attachmentMediaCache.lookup(
        cacheTarget,
        expectedBytes: expectedBytes,
      );
      if (cached == null) {
        // Ưu tiên phát dần: không phải tải hết tệp mới xem được.
        final streamed = await _openStream(generation, fresh: freshStream);
        if (streamed != null) {
          if (!await operationIsCurrent()) {
            await streamed.dispose();
            throw const RedirectSafeDownloadException(
              'instance binding changed',
            );
          }
          await streamed.setLooping(false);
          if (resumeAt != null && resumeAt > Duration.zero) {
            await streamed.seekTo(resumeAt);
          }
          if (!mounted || generation != _initializationGeneration) {
            await streamed.dispose();
            return;
          }
          await _activateController(
            streamed,
            binding: binding,
            generation: generation,
            streamed: true,
          );
          return;
        }
        if (previewOnly) {
          // Chỉ xem trước: không tải cả tệp về chỉ để lấy khung hình.
          throw const RedirectSafeDownloadException('preview unavailable');
        }
        if (freshStream) {
          // Tự khôi phục (người dùng không bấm gì): xin đường phát mới không
          // được thì báo lỗi có nút thử lại, không tự tải cả tệp (tốn 4G).
          throw const RedirectSafeDownloadException('stream recovery failed');
        }
        if (byteSize > maxVideoPlaybackBytes) {
          throw const RedirectSafeDownloadException('video too large');
        }
      }

      // Tải vào kho đệm của tài khoản (giữ 7 ngày): xem lại không tải lại.
      // Lượt tải chỉ dừng khi đổi phiên, không dừng khi cuộn khỏi bong bóng:
      // bong bóng dựng lại nối vào lượt đang tải (kho gộp lượt trùng) và
      // thấy phần trăm qua tiến độ chung.
      final File readyFile;
      if (cached != null) {
        readyFile = cached;
      } else {
        final progressPath = cacheTarget.path;
        final progress = _watchDownloadProgress(progressPath);
        // Lượt tải có thể chạy sau khi bong bóng đã huỷ: không đọc `widget`.
        final mimeType = widget.attachment.file.mimeType;
        try {
          readyFile = await attachmentMediaCache.ensureFile(
            cacheTarget,
            expectedBytes: expectedBytes,
            download: (target) => _videoDownloadGate.run(
              () => _downloader.download(
                uri: uri,
                target: target,
                maxBytes: maxVideoPlaybackBytes,
                expectedBytes: expectedBytes,
                accept: mimeType,
                bearerToken: binding.bearerToken,
                isStillCurrent: binding.isStillCurrent,
                onProgress: (received, total) {
                  if (total > 0) progress.value = received / total;
                },
              ),
            ),
          );
        } finally {
          if (identical(_progressSource, progress)) _stopWatchingProgress();
          if (identical(_mediaDownloadProgress[progressPath], progress)) {
            _mediaDownloadProgress.remove(progressPath);
          }
        }
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
      if (resumeAt != null && resumeAt > Duration.zero) {
        await next.seekTo(resumeAt);
      }
      if (!await operationIsCurrent() ||
          generation != _initializationGeneration ||
          !mounted) {
        throw const RedirectSafeDownloadException('instance binding changed');
      }
      final ready = next;
      next = null;
      await _activateController(
        ready,
        binding: binding,
        generation: generation,
        streamed: false,
      );
    } on Object {
      // Tệp trong kho đệm dùng chung: không xoá ở đây, kho tự dọn sau 7 ngày.
      await next?.dispose();
      _markVideoFailure(generation, previewOnly: previewOnly);
    }
  }

  /// Đưa trình phát đã sẵn sàng lên màn (huỷ trình phát cũ); đã bấm phát thì
  /// phát luôn.
  Future<void> _activateController(
    VideoPlayerController controller, {
    required _AttachmentDownloadBinding binding,
    required int generation,
    required bool streamed,
  }) async {
    final previous = _swapController(controller, streamed: streamed);
    setState(() {
      _binding = binding;
      _loading = false;
      _failed = false;
      _downloadProgress = null;
    });
    if (previous != null) await previous.dispose();
    if (_playWhenReady && mounted && generation == _initializationGeneration) {
      _playWhenReady = false;
      // Trong lúc tải / khôi phục, người dùng đã phát cái khác hoặc bắt đầu
      // cuộc gọi: để sẵn sàng, không tự phát chen ngang.
      if (ExclusiveMediaPlayback.isLatestRequest(_playRequestToken)) {
        await _togglePlayback();
      }
    }
  }

  void _markVideoFailure(int generation, {bool previewOnly = false}) {
    if (!mounted || generation != _initializationGeneration) return;
    if (previewOnly) _releasePreviewSlot();
    if (previewOnly && _playWhenReady) {
      // Đã chạm chờ phát trong lúc mở xem trước: xem trước hỏng thì mở hẳn
      // video (phát dần lần nữa hoặc tải về).
      unawaited(_initialize());
      return;
    }
    _playWhenReady = false;
    setState(() {
      _loading = false;
      // Xem trước hỏng thì giữ ô tối có nút phát, chưa báo lỗi.
      if (!previewOnly) _failed = true;
    });
  }

  @override
  void dispose() {
    _releasePreviewSlot();
    _initializationGeneration += 1;
    ExclusiveMediaPlayback.release(this);
    _stopWatchingProgress();
    unawaited(_swapController(null)?.dispose());
    super.dispose();
  }

  /// Nguồn phát khác (tin thoại / video khác) bắt đầu phát: tạm dừng video này.
  Future<void> _pauseForOther() async {
    _wantsPlaying = false;
    final controller = _controller;
    if (controller != null && controller.value.isPlaying) {
      await controller.pause();
    }
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
      _wantsPlaying = false;
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (controller.value.isPlaying) {
      _wantsPlaying = false;
      await controller.pause();
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      _wantsPlaying = true;
      // Chỉ một nguồn có tiếng: tin thoại / video khác đang phát thì dừng.
      ExclusiveMediaPlayback.claim(this, _pauseForOther);
      await controller.play();
      if (_controllerStreamed) {
        unawaited(_cacheStreamedVideo(binding, previewOnly: !_wantsPlaying));
      }
    }
    if (mounted) setState(() {});
  }

  /// Video phát dần (chưa có trong kho) vừa được phát: tải ngầm vào đúng tệp
  /// kho của video (cùng khoá / tên với đường tải về, kho gộp lượt trùng) để
  /// lần xem sau phát thẳng từ máy. Chỉ khi cỡ tối đa
  /// [backgroundVideoCacheMaxBytes] và đang dùng Wi-Fi hoặc người dùng cho
  /// phép tự tải khi dùng dữ liệu di động. Lỗi chỉ bỏ qua (lần sau xem lại).
  Future<void> _cacheStreamedVideo(
    _AttachmentDownloadBinding binding, {
    required bool previewOnly,
  }) async {
    if (_backgroundCacheChecked || !mounted) return;
    _backgroundCacheChecked = true;
    final attachment = widget.attachment;
    final uri = attachmentDownloadUri(attachment, widget.apiBaseUri);
    if (uri == null) return;
    final byteSize = attachment.file.byteSize;
    final policy = ref.read(mediaAutoDownloadPolicyProvider);
    try {
      if (!await policy.canBackgroundCacheVideo(
        byteSize: byteSize,
        previewOnly: previewOnly,
      )) {
        return;
      }
      final target = await binding.cacheFile(
        purpose: 'video',
        uri: uri,
        originalName: galleryFileName(attachment),
      );
      if (!await binding.isStillCurrent()) return;
      final mimeType = attachment.file.mimeType;
      await attachmentMediaCache.ensureFile(
        target,
        expectedBytes: byteSize,
        download: (file) => _videoDownloadGate.run(
          () => _downloader.download(
            uri: uri,
            target: file,
            maxBytes: backgroundVideoCacheMaxBytes,
            expectedBytes: byteSize,
            accept: mimeType,
            bearerToken: binding.bearerToken,
            isStillCurrent: binding.isStillCurrent,
          ),
        ),
      );
    } on Object {
      // Tải ngầm là việc phụ: video vẫn đang phát dần bình thường.
    }
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
      _wantsPlaying = false;
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

  /// Ảnh bìa + nút phát lớn giữa + thời lượng ở góc. Chỉ bấm mới tải video.
  Widget _buildThumbnailCover(Uri thumbnailUri, String? durationText) {
    final label = durationText == null
        ? tr('Phát video', 'Play video')
        : tr('Phát video, $durationText', 'Play video, $durationText');
    return Stack(
      fit: StackFit.expand,
      children: [
        _VideoThumbnailImage(
          key: ValueKey('video-thumbnail-${widget.attachment.fileId}'),
          uri: thumbnailUri,
          apiBaseUri: widget.apiBaseUri,
          onImageSize: _onThumbnailSize,
        ),
        Center(
          child: _loading
              ? _buildLoadingIndicator()
              : Semantics(
                  button: true,
                  label: _failed
                      ? tr(
                          'Không phát được video, chạm để thử lại',
                          'Can\'t play video, tap to retry',
                        )
                      : label,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onPlayTapped,
                    child: Container(
                      key: const ValueKey('video-thumbnail-play'),
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _failed
                            ? CupertinoIcons.exclamationmark_triangle
                            : CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
        ),
        if (durationText != null)
          Positioned(
            right: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(WebTuiRadii.sm),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  durationText,
                  key: const ValueKey('video-thumbnail-duration'),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _durationBadge(String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(WebTuiRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: WebTuiTypography.labelSmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// Video chưa có ảnh bìa và chưa có khung hình xem trước: ô tối có biểu
  /// tượng phim, tên tệp, thời lượng và nút phát (không bao giờ là ô đen trống).
  Widget _buildPlaceholderCover(String? durationText) {
    final name = widget.attachment.file.name;
    return Stack(
      key: const ValueKey('video-placeholder'),
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A3140), Color(0xFF151921)],
            ),
          ),
        ),
        const Align(
          alignment: Alignment(0, -0.55),
          child: Icon(CupertinoIcons.film, color: Colors.white38, size: 30),
        ),
        Center(
          child: _loading
              ? _buildLoadingIndicator()
              : Semantics(
                  button: true,
                  label: _failed
                      ? tr(
                          'Không phát được video, chạm để thử lại',
                          'Can\'t play video, tap to retry',
                        )
                      : tr('Phát video', 'Play video'),
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onPlayTapped,
                    child: Container(
                      key: const ValueKey('video-placeholder-play'),
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _failed
                            ? CupertinoIcons.exclamationmark_triangle
                            : CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
        ),
        // Có dòng tên tệp riêng phía dưới (không có nhãn giờ) thì khỏi lặp.
        if (widget.timeLabel != null)
          Positioned(
            left: 10,
            right: durationText == null ? 10 : 64,
            bottom: 8,
            child: Text(
              _failed
                  ? tr(
                      'Không phát được, chạm để thử lại',
                      'Can\'t play, tap to retry',
                    )
                  : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WebTuiTypography.labelSmall.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (durationText != null)
          Positioned(right: 6, bottom: 6, child: _durationBadge(durationText)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLocalPreview) {
      return MessageLocalVideoPreview(
        path: widget.attachment.file.localPath!.trim(),
        fileName: widget.attachment.file.name,
        progress: widget.uploadProgress,
        stage: widget.uploadStage,
        allowFullscreen: widget.allowFullscreen,
        timeLabel: widget.timeLabel,
      );
    }
    final controller = _controller;
    final initialized = controller?.value.isInitialized == true;
    final activeController = initialized ? controller! : null;
    final file = widget.attachment.file;
    final thumbnailUri = attachmentThumbnailUri(
      widget.attachment,
      widget.apiBaseUri,
    );
    final knownWidth = file.width ?? 0;
    final knownHeight = file.height ?? 0;
    final ratioKey = widget.attachment.fileId.isNotEmpty
        ? widget.attachment.fileId
        : widget.attachment.id;
    if (initialized && activeController!.value.aspectRatio > 0) {
      MessageMediaAspectCache.put(ratioKey, activeController.value.aspectRatio);
    }
    final double rawRatio = initialized
        ? activeController!.value.aspectRatio
        : knownWidth > 0 && knownHeight > 0
        ? knownWidth / knownHeight
        : MessageMediaAspectCache.get(ratioKey) ?? _thumbnailRatio ?? 16 / 9;
    final durationMs = file.durationMs ?? 0;
    // Máy chủ chưa ghi thời lượng thì lấy thời lượng thật của trình phát.
    final playerDuration = activeController?.value.duration ?? Duration.zero;
    final durationText = durationMs > 0
        ? _formatDuration(Duration(milliseconds: durationMs))
        : playerDuration > Duration.zero
        ? _formatDuration(playerDuration)
        : null;
    final Size box;
    if (widget.allowFullscreen) {
      final maxBox = messageMediaMaxBox(context);
      box = fitMessageMediaBox(
        ratio: rawRatio,
        maxWidth: maxBox.width,
        maxHeight: maxBox.height,
      );
    } else {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final ratio = rawRatio.clamp(0.65, 1.9).toDouble();
      box = Size(screenWidth, screenWidth / ratio);
    }
    final width = box.width;
    final aspectRatio = box.width / box.height;
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
                      _coverVideo(activeController)
                    else if (thumbnailUri != null)
                      _buildThumbnailCover(thumbnailUri, durationText)
                    else
                      _buildPlaceholderCover(durationText),
                    if (activeController != null)
                      Center(
                        child: IconButton.filled(
                          tooltip: activeController.value.isPlaying
                              ? tr('Tạm dừng', 'Pause')
                              : tr('Phát video', 'Play video'),
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
                    if (activeController != null &&
                        durationText != null &&
                        !activeController.value.isPlaying)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: _durationBadge(durationText),
                      ),
                    if (widget.allowFullscreen && activeController != null)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: IconButton.filledTonal(
                          tooltip: tr('Toàn màn hình', 'Full screen'),
                          onPressed: _openFullscreen,
                          icon: const Icon(
                            CupertinoIcons.arrow_up_left_arrow_down_right,
                            size: 18,
                          ),
                        ),
                      ),
                    if (widget.timeLabel != null)
                      MessageMediaTimeBadge(label: widget.timeLabel!),
                  ],
                ),
              ),
              if (activeController != null)
                VideoProgressIndicator(
                  activeController,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: WebTuiColors.primary,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12,
                  ),
                ),
              if (widget.allowFullscreen && widget.timeLabel == null)
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
                              ? tr('Không phát được video', 'Can\'t play video')
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

/// Ảnh bìa video tải kèm xác thực (cùng cách tải ảnh trong bong bóng). Lỗi
/// hoặc chưa có thì hiện nền tối, không chặn nút phát.
class _VideoThumbnailImage extends ConsumerStatefulWidget {
  const _VideoThumbnailImage({
    required this.uri,
    required this.apiBaseUri,
    this.onImageSize,
    super.key,
  });

  final Uri uri;
  final Uri? apiBaseUri;
  final ValueChanged<Size>? onImageSize;

  @override
  ConsumerState<_VideoThumbnailImage> createState() =>
      _VideoThumbnailImageState();
}

class _VideoThumbnailImageState extends ConsumerState<_VideoThumbnailImage> {
  static const _downloader = RedirectSafeFileDownloader();
  static const int _maxThumbnailBytes = 2 * 1024 * 1024;

  int _generation = 0;

  Future<Uint8List?> _load(int generation) async {
    final binding = await _captureAttachmentDownloadBinding(
      read: ref.read,
      attachmentUri: widget.uri,
      apiBaseUri: widget.apiBaseUri,
    );
    if (binding == null) return null;
    final uri = widget.uri;
    Future<bool> isCurrent() async =>
        mounted && generation == _generation && await binding.isStillCurrent();
    final bytes = await loadCachedImageBytes(
      cache: attachmentMediaCache,
      failures: mediaDownloadFailures,
      failureKey: binding.failureKey(uri),
      file: await binding.cacheFile(purpose: 'image', uri: uri),
      maxBytes: _maxThumbnailBytes,
      download: () => _imageDownloadGate.run(
        () => _downloader.downloadBytes(
          uri: uri,
          maxBytes: _maxThumbnailBytes,
          accept: 'image/jpeg',
          bearerToken: binding.bearerToken,
          isStillCurrent: isCurrent,
        ),
      ),
      isStillCurrent: binding.isStillCurrent,
    );
    return bytes != null && await isCurrent() ? bytes : null;
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        oldWidget.apiBaseUri != widget.apiBaseUri) {
      _generation += 1;
    }
  }

  @override
  void dispose() {
    _generation += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : width * 9 / 16;
        return WebTuiOwnedDecodedImage(
          requestKey: '${widget.uri}|$generation',
          loadBytes: () => _load(generation),
          maxEncodedBytes: _maxThumbnailBytes,
          decodeTargetWidth: (width * 3).ceil().clamp(1, 2048),
          decodeTargetHeight: (height * 3).ceil().clamp(1, 2048),
          width: width,
          height: height,
          fit: BoxFit.cover,
          onImageSize: widget.onImageSize,
          loading: const ColoredBox(color: Color(0xFF1B1F27)),
          fallback: const ColoredBox(color: Color(0xFF1B1F27)),
        );
      },
    );
  }
}

/// Khung video của tin đang gửi: không tải gì từ máy chủ, chỉ hiện khung hình
/// đầu của tệp trên máy (lỗi thì nền tối) và vòng tiến độ nén / tải lên.
class MessageLocalVideoPreview extends StatefulWidget {
  const MessageLocalVideoPreview({
    required this.path,
    required this.fileName,
    this.progress,
    this.stage,
    this.allowFullscreen = true,
    this.timeLabel,
    super.key,
  });

  final String path;
  final String fileName;
  final String? timeLabel;
  final double? progress;
  final String? stage;
  final bool allowFullscreen;

  @override
  State<MessageLocalVideoPreview> createState() =>
      _MessageLocalVideoPreviewState();
}

class _MessageLocalVideoPreviewState extends State<MessageLocalVideoPreview> {
  VideoPlayerController? _controller;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFirstFrame());
  }

  @override
  void didUpdateWidget(covariant MessageLocalVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      final previous = _controller;
      _controller = null;
      unawaited(previous?.dispose());
      unawaited(_loadFirstFrame());
    }
  }

  Future<void> _loadFirstFrame() async {
    final generation = ++_generation;
    VideoPlayerController? next;
    try {
      final file = File(widget.path);
      if (!await file.exists()) return;
      next = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await next.initialize();
      await next.setLooping(false);
      if (!mounted || generation != _generation) {
        await next.dispose();
        return;
      }
      setState(() => _controller = next);
    } on Object {
      // Không xem trước được thì chỉ hiện nền tối.
      await next?.dispose();
    }
  }

  @override
  void dispose() {
    _generation += 1;
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller?.value.isInitialized == true;
    if (ready && controller!.value.aspectRatio > 0) {
      MessageMediaAspectCache.put(widget.path, controller.value.aspectRatio);
    }
    final rawRatio = ready
        ? controller!.value.aspectRatio
        : MessageMediaAspectCache.get(widget.path) ?? 16 / 9;
    final Size box;
    if (widget.allowFullscreen) {
      final maxBox = messageMediaMaxBox(context);
      box = fitMessageMediaBox(
        ratio: rawRatio,
        maxWidth: maxBox.width,
        maxHeight: maxBox.height,
      );
    } else {
      final screenWidth = MediaQuery.sizeOf(context).width;
      box = Size(screenWidth, screenWidth / rawRatio.clamp(0.65, 1.9));
    }
    final width = box.width;
    final aspectRatio = box.width / box.height;
    final progress = widget.progress;
    final compressing = widget.stage == 'compressing';
    final percent = ((progress ?? 0) * 100).clamp(0, 100).round();
    final label = compressing
        ? tr('Đang nén…', 'Compressing…')
        : tr('Đang tải lên $percent%', 'Uploading $percent%');
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        child: ColoredBox(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (ready)
                  IgnorePointer(child: _coverVideo(controller!))
                else
                  const SizedBox.expand(),
                if (progress == null)
                  const Center(
                    child: Icon(
                      CupertinoIcons.play_circle_fill,
                      color: Colors.white70,
                      size: 44,
                    ),
                  )
                else
                  Semantics(
                    // Không đặt liveRegion: tiến độ đổi mỗi 1 %, trình đọc màn
                    // hình sẽ đọc liên tục.
                    label: 'Video ${widget.fileName}: $label',
                    child: ExcludeSemantics(
                      child: ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox.square(
                                dimension: 44,
                                child: CircularProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  strokeWidth: 3,
                                  color: Colors.white,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                              const SizedBox(height: WebTuiSpacing.xs),
                              Text(
                                label,
                                style: WebTuiTypography.labelSmall.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.timeLabel != null)
                  MessageMediaTimeBadge(label: widget.timeLabel!),
              ],
            ),
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
      _showFailure(tr('Đường dẫn tệp không hợp lệ.', 'Invalid file path.'));
      return;
    }
    setState(() => _opening = true);
    try {
      final target = await _downloadAttachmentFile(
        ref.read,
        attachment: widget.attachment,
        uri: uri,
        apiBaseUri: widget.apiBaseUri,
        originalName: widget.attachment.file.name,
      );
      // Đã rời màn trong lúc tải thì không bật app khác lên.
      if (!mounted) return;
      final opened = await OpenFilex.open(
        target.path,
        type: widget.attachment.file.mimeType,
      );
      if (opened.type != ResultType.done) {
        throw StateError(opened.message);
      }
    } on Object {
      _showFailure(
        tr(
          'Không thể tải hoặc mở tệp này trên thiết bị.',
          'Couldn\'t download or open this file on your device.',
        ),
      );
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
            ? WebTuiColors.messageOutgoing
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
                          : Icon(
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
                        '${_formatByteSize(widget.attachment.file.byteSize)} · ${tr('Nhấn để mở', 'Tap to open')}',
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
    this.onTapToDownload,
  });

  final double width;
  final double? height;
  final bool loading;

  /// Có giá trị: ô "Chạm để tải ảnh" (đang dùng dữ liệu di động, người dùng
  /// tắt tự tải ảnh).
  final VoidCallback? onTapToDownload;

  @override
  Widget build(BuildContext context) {
    final onTap = onTapToDownload;
    if (onTap != null) {
      final label = tr('Chạm để tải ảnh', 'Tap to download photo');
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('image-tap-to-download'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: height ?? width * 0.72,
            child: ColoredBox(
              color: WebTuiColors.primarySoft,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      WebTuiIcons.download,
                      color: WebTuiColors.primary,
                      size: 28,
                    ),
                    const SizedBox(height: WebTuiSpacing.xs),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
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
              : Icon(
                  CupertinoIcons.photo,
                  color: WebTuiColors.primary,
                  size: 28,
                ),
        ),
      ),
    );
  }
}

bool attachmentUriCanUseInstanceCredentials({
  required Uri attachmentUri,
  required Uri apiBaseUri,
  required Uri activeInstanceOrigin,
}) {
  return serverOriginsMatch(attachmentUri, apiBaseUri) &&
      serverOriginsMatch(apiBaseUri, activeInstanceOrigin);
}

/// Tải tệp đính kèm về bộ nhớ riêng của app (dùng lại nếu đã tải đủ), đúng máy chủ và phiên đăng nhập hiện tại.
Future<File> _downloadAttachmentFile(
  _ProviderReader read, {
  required MessageAttachment attachment,
  required Uri uri,
  required Uri? apiBaseUri,
  required String originalName,
  String purpose = 'file',
}) async {
  final binding = await _captureAttachmentDownloadBinding(
    read: read,
    attachmentUri: uri,
    apiBaseUri: apiBaseUri,
  );
  if (binding == null) {
    throw StateError('instance binding unavailable');
  }
  // Kho đệm 7 ngày của tài khoản: mở / lưu lại không tải lại.
  final target = await attachmentMediaCache.ensureFile(
    await binding.cacheFile(
      purpose: purpose,
      uri: uri,
      originalName: originalName,
    ),
    expectedBytes: attachment.file.byteSize,
    download: (target) => const RedirectSafeFileDownloader().download(
      uri: uri,
      target: target,
      maxBytes: UploadMessageAttachmentUseCase.maxBytes,
      expectedBytes: attachment.file.byteSize,
      accept: attachment.file.mimeType,
      bearerToken: binding.bearerToken,
      isStillCurrent: binding.isStillCurrent,
    ),
  );
  if (!await binding.isStillCurrent()) {
    throw StateError('instance binding changed');
  }
  return target;
}

String _normalizedMime(MessageAttachment attachment) =>
    attachment.file.mimeType.trim().toLowerCase();

/// Ảnh / video lưu được vào thư viện ảnh của máy (ảnh vẽ SVG thì không).
bool isGallerySaveable(MessageAttachment attachment) {
  final mime = _normalizedMime(attachment);
  if (mime.startsWith('video/')) return true;
  return mime.startsWith('image/') && !mime.contains('svg');
}

/// Mã tệp đang được tải để lưu; bấm "Lưu" lần nữa khi chưa xong thì bỏ qua tệp đó.
final Set<String> _gallerySavesInFlight = <String>{};

/// Tải ảnh / video của tin nhắn rồi lưu vào thư viện ảnh của máy; báo kết quả bằng SnackBar.
/// Đọc provider qua container nên vẫn chạy tiếp khi bảng thao tác / màn xem ảnh đã đóng.
Future<void> saveMessageAttachmentsToGallery(
  BuildContext context, {
  required List<MessageAttachment> attachments,
  Uri? apiBaseUri,
}) async {
  final media = attachments
      .where(isGallerySaveable)
      .where((item) => !_gallerySavesInFlight.contains(item.fileId))
      .toList(growable: false);
  if (media.isEmpty) return;
  _gallerySavesInFlight.addAll(media.map((item) => item.fileId));
  try {
    await _saveAttachmentsToGallery(context, media, apiBaseUri);
  } finally {
    _gallerySavesInFlight.removeAll(media.map((item) => item.fileId));
  }
}

Future<void> _saveAttachmentsToGallery(
  BuildContext context,
  List<MessageAttachment> media,
  Uri? apiBaseUri,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final saver = container.read(mediaGallerySaverProvider);
  final hasVideo = media.any(
    (item) => _normalizedMime(item).startsWith('video/'),
  );
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          hasVideo
              ? tr('Đang tải video về để lưu…', 'Downloading video to save…')
              : tr('Đang lưu ảnh…', 'Saving photo…'),
        ),
        duration: const Duration(seconds: 30),
      ),
    );
  var saved = 0;
  var denied = false;
  for (final attachment in media) {
    final uri = attachmentDownloadUri(attachment, apiBaseUri);
    if (uri == null) continue;
    try {
      final isVideo = _normalizedMime(attachment).startsWith('video/');
      final file = await _downloadAttachmentFile(
        container.read,
        attachment: attachment,
        uri: uri,
        apiBaseUri: apiBaseUri,
        originalName: galleryFileName(attachment),
        // Video dùng chung tệp kho với lúc phát: đã xem thì lưu không tải lại.
        purpose: isVideo ? 'video' : 'file',
      );
      final result = await saver.save(file.path, isVideo: isVideo);
      if (result == MediaGallerySaveResult.saved) saved += 1;
      if (result == MediaGallerySaveResult.permissionDenied) {
        denied = true;
        break;
      }
    } on Object {
      // Một tệp lỗi không chặn các tệp còn lại; báo chung ở cuối.
    }
  }
  final String message;
  if (denied) {
    message = tr(
      'Chưa cho phép lưu vào thư viện ảnh. Hãy bật quyền Ảnh cho WebTUI Chat trong Cài đặt của máy.',
      'Photo library access is off. Allow Photos for WebTUI Chat in your device Settings.',
    );
  } else if (saved == media.length) {
    message = media.length == 1
        ? (hasVideo
              ? tr(
                  'Đã lưu video vào thư viện ảnh',
                  'Video saved to your photos',
                )
              : tr('Đã lưu ảnh vào thư viện ảnh', 'Photo saved to your photos'))
        : tr(
            'Đã lưu $saved ảnh / video vào thư viện ảnh',
            'Saved $saved items to your photos',
          );
  } else if (saved > 0) {
    message = tr(
      'Đã lưu $saved / ${media.length} tệp, phần còn lại bị lỗi',
      'Saved $saved of ${media.length}, the rest failed',
    );
  } else {
    message = tr(
      'Không lưu được. Kiểm tra mạng rồi thử lại.',
      'Couldn\'t save. Check your connection and try again.',
    );
  }
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Đọc provider từ `WidgetRef` hoặc `ProviderContainer` (việc chạy tiếp sau khi màn / bảng đã đóng).
typedef _ProviderReader = T Function<T>(ProviderListenable<T> provider);

Future<_AttachmentDownloadBinding?> _captureAttachmentDownloadBinding({
  required _ProviderReader read,
  required Uri attachmentUri,
  required Uri? apiBaseUri,
}) async {
  final instanceScope = read(activeServerDiscoveryProvider)?.instanceScope;
  if (instanceScope == null ||
      (apiBaseUri != null &&
          !serverOriginsMatch(apiBaseUri, instanceScope.origin))) {
    return null;
  }
  final tokenRepository = read(authTokenRepositoryProvider);
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
  // Đọc cả khi không gửi kèm token: mã người dùng trong token chọn thư mục
  // kho đệm của tài khoản.
  final accessToken = (await tokenRepository.readAccessTokenIfCurrent(
    guard,
  ))?.trim();
  String? bearerToken;
  if (usesInstanceCredentials) {
    bearerToken = accessToken;
    if (bearerToken == null || bearerToken.isEmpty) return null;
  }
  if (!await tokenRepository.isMutationGuardCurrent(guard)) return null;
  return _AttachmentDownloadBinding(
    instanceScope: instanceScope,
    guard: guard,
    bearerToken: bearerToken,
    accountKey: mediaCacheAccountKey(
      accessToken: accessToken,
      sessionGeneration: guard.generation,
    ),
    tokenRepository: tokenRepository,
  );
}

final class _AttachmentDownloadBinding {
  const _AttachmentDownloadBinding({
    required this.instanceScope,
    required this.guard,
    required this.bearerToken,
    required this.accountKey,
    required AuthTokenRepository tokenRepository,
  }) : _tokenRepository = tokenRepository;

  final InstanceScope instanceScope;
  final AuthTokenMutationGuard guard;
  final String? bearerToken;

  /// Tài khoản đang đăng nhập (xem [mediaCacheAccountKey]): chọn thư mục kho
  /// đệm, tài khoản khác không đọc được tệp đã tải.
  final String accountKey;
  final AuthTokenRepository _tokenRepository;

  Future<bool> isStillCurrent() {
    return _tokenRepository.isMutationGuardCurrent(guard);
  }

  /// Tệp trong kho đệm 7 ngày của tài khoản cho địa chỉ tải [uri].
  Future<File> cacheFile({
    required String purpose,
    required Uri uri,
    String variant = '',
    String originalName = '',
  }) {
    return const ScopedAttachmentFileStore().cacheFileFor(
      instanceScope: instanceScope,
      accountKey: accountKey,
      purpose: purpose,
      key: attachmentMediaCacheKey(uri, variant: variant),
      originalName: originalName,
    );
  }

  Future<Directory> cacheDirectory(String purpose) {
    return const ScopedAttachmentFileStore().cacheDirectoryFor(
      instanceScope: instanceScope,
      accountKey: accountKey,
      purpose: purpose,
    );
  }

  /// Khoá nhớ lỗi tải (403 / 404) của [uri] theo máy chủ + tài khoản.
  String failureKey(Uri uri) => '${instanceScope.storageId}|$accountKey|$uri';
}

const int maxImagePreviewBytes = 5 * 1024 * 1024;

/// Ảnh gốc tối đa ở màn xem ảnh toàn màn hình (bong bóng vẫn
/// [maxImagePreviewBytes]); lớn hơn thì dùng ảnh thu nhỏ.
const int maxImageFullscreenBytes = 30 * 1024 * 1024;
const int maxVoicePlaybackBytes = 100 * 1024 * 1024;

/// Video tải cả tệp về rồi phát (iPhone luôn vậy): bằng mức gửi tối đa, để
/// video nào gửi được cũng xem được.
const int maxVideoPlaybackBytes = UploadMessageAttachmentUseCase.maxBytes;

/// Tiến độ (0..1) của các lượt tải video vào kho đang chạy, theo đường dẫn
/// tệp kho: bong bóng dựng lại (cuộn đi rồi quay lại) vẫn thấy phần trăm của
/// lượt đang tải. Lượt tải xong / lỗi thì gỡ khỏi bảng.
final Map<String, ValueNotifier<double>> _mediaDownloadProgress = {};

/// Giới hạn số lần tự khôi phục video phát dần: tối đa [maxAttempts] lần trong
/// [window], quá thì báo lỗi để người dùng tự thử lại (tránh vòng lặp xin
/// đường mới khi máy chủ / mạng hỏng hẳn).
final class MessageVideoRecoveryBudget {
  MessageVideoRecoveryBudget({
    this.maxAttempts = 2,
    this.window = const Duration(minutes: 1),
  });

  final int maxAttempts;
  final Duration window;
  final List<DateTime> _attempts = [];

  /// Còn lượt khôi phục lúc [now] thì ghi nhận một lượt và trả true.
  bool tryAcquire(DateTime now) {
    _attempts.removeWhere((attempt) => now.difference(attempt) >= window);
    if (_attempts.length >= maxAttempts) return false;
    _attempts.add(now);
    return true;
  }
}

enum MessageVideoErrorAction {
  /// Xin đường phát dần mới, tua về chỗ cũ, phát tiếp.
  recover,

  /// Hiện trạng thái lỗi có nút thử lại.
  fail,
}

/// Trình phát video báo lỗi thì làm gì: chỉ trình phát dần (đường có mã sống
/// 15 phút, hết hạn khi tạm dừng lâu / video dài) mới tự khôi phục, trong giới
/// hạn [budget]; tệp trên máy lỗi thì khôi phục cũng vô ích.
MessageVideoErrorAction messageVideoErrorAction({
  required bool streamed,
  required MessageVideoRecoveryBudget budget,
  required DateTime now,
}) {
  if (!streamed) return MessageVideoErrorAction.fail;
  return budget.tryAcquire(now)
      ? MessageVideoErrorAction.recover
      : MessageVideoErrorAction.fail;
}

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
