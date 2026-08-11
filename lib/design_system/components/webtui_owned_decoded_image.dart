import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Decodes image bytes into an image owned by this widget without inserting
/// the encoded bytes into Flutter's global [ImageCache].
///
/// This matters for untrusted padded images: the framework's global memory
/// provider can retain the full encoded byte list while budgeting only the
/// decoded pixel size. The owned image is disposed as soon as this widget is
/// replaced or leaves the tree.
class WebTuiOwnedDecodedImage extends StatefulWidget {
  const WebTuiOwnedDecodedImage({
    required this.requestKey,
    required this.loadBytes,
    required this.maxEncodedBytes,
    required this.decodeTargetWidth,
    required this.decodeTargetHeight,
    required this.fallback,
    required this.loading,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.semanticLabel,
    @visibleForTesting this.onImageCreated,
    @visibleForTesting this.onImageDisposed,
    @visibleForTesting this.onDecodeError,
    super.key,
  });

  final Object requestKey;
  final Future<Uint8List?> Function() loadBytes;
  final int maxEncodedBytes;
  final int decodeTargetWidth;
  final int decodeTargetHeight;
  final Widget fallback;
  final Widget loading;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? semanticLabel;
  final VoidCallback? onImageCreated;
  final VoidCallback? onImageDisposed;
  final ValueChanged<Object>? onDecodeError;

  @override
  State<WebTuiOwnedDecodedImage> createState() =>
      _WebTuiOwnedDecodedImageState();
}

class _WebTuiOwnedDecodedImageState extends State<WebTuiOwnedDecodedImage> {
  ui.Image? _image;
  int _generation = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _startDecode();
  }

  @override
  void didUpdateWidget(covariant WebTuiOwnedDecodedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestKey != widget.requestKey ||
        oldWidget.maxEncodedBytes != widget.maxEncodedBytes ||
        oldWidget.decodeTargetWidth != widget.decodeTargetWidth ||
        oldWidget.decodeTargetHeight != widget.decodeTargetHeight) {
      _startDecode();
    }
  }

  void _startDecode() {
    final generation = ++_generation;
    final previous = _image;
    _image = null;
    _disposeImage(previous);
    _loading = true;
    unawaited(_decode(generation));
  }

  Future<void> _decode(int generation) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      final bytes = await widget.loadBytes();
      if (!_isCurrent(generation)) return;
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.lengthInBytes > widget.maxEncodedBytes) {
        _finish(generation);
        return;
      }
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      if (!_isCurrent(generation)) return;
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!_isCurrent(generation)) return;
      final sourceWidth = descriptor.width;
      final sourceHeight = descriptor.height;
      if (sourceWidth <= 0 || sourceHeight <= 0) {
        _finish(generation);
        return;
      }
      final widthScale = widget.decodeTargetWidth.clamp(1, 2048) / sourceWidth;
      final heightScale =
          widget.decodeTargetHeight.clamp(1, 2048) / sourceHeight;
      final scale = widthScale < heightScale ? widthScale : heightScale;
      final boundedScale = scale < 1 ? scale : 1.0;
      final targetWidth = (sourceWidth * boundedScale).round().clamp(1, 2048);
      final targetHeight = (sourceHeight * boundedScale).round().clamp(1, 2048);
      codec = await descriptor.instantiateCodec(
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      if (!_isCurrent(generation)) return;
      final frame = await codec.getNextFrame();
      decoded = frame.image;
      widget.onImageCreated?.call();
      if (!_isCurrent(generation)) {
        _disposeImage(decoded);
        decoded = null;
        return;
      }
      _finish(generation, decoded);
      decoded = null;
    } on Object catch (error) {
      widget.onDecodeError?.call(error);
      _disposeImage(decoded);
      if (_isCurrent(generation)) _finish(generation);
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  bool _isCurrent(int generation) {
    return mounted && generation == _generation;
  }

  void _finish(int generation, [ui.Image? image]) {
    if (!_isCurrent(generation)) {
      _disposeImage(image);
      return;
    }
    setState(() {
      final previous = _image;
      _image = image;
      _loading = false;
      _disposeImage(previous);
    });
  }

  @override
  void dispose() {
    _generation++;
    _disposeImage(_image);
    _image = null;
    super.dispose();
  }

  void _disposeImage(ui.Image? image) {
    if (image == null) return;
    image.dispose();
    widget.onImageDisposed?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return widget.loading;
    final image = _image;
    if (image == null) return widget.fallback;
    final rendered = RawImage(
      image: image,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
    );
    final label = widget.semanticLabel?.trim();
    if (label == null || label.isEmpty) return rendered;
    return Semantics(image: true, label: label, child: rendered);
  }
}
