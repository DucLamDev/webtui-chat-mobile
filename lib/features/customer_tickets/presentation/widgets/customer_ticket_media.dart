import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../domain/entities/customer_ticket.dart';

/// Ảnh khách gửi trong ticket (URL tuyệt đối, tên miền khác). Tải không kèm
/// token qua use case, giải mã bằng [WebTuiOwnedDecodedImage] (không dùng
/// `Image.network`, không đưa byte vào bộ nhớ đệm ảnh chung).
class CustomerTicketRemoteImage extends ConsumerWidget {
  const CustomerTicketRemoteImage({
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    super.key,
  });

  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadImage = ref.watch(loadCustomerTicketImageUseCaseProvider);
    final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final targetWidth = (width * pixelRatio).ceil().clamp(1, 2048);
    final targetHeight = (height * pixelRatio).ceil().clamp(1, 2048);
    final requestKey = '$url|$targetWidth|$targetHeight';
    return SizedBox(
      width: width,
      height: height,
      child: WebTuiOwnedDecodedImage(
        key: ValueKey(requestKey),
        requestKey: requestKey,
        loadBytes: () => loadImage.execute(url),
        maxEncodedBytes: customerTicketMaxImageBytes,
        decodeTargetWidth: targetWidth,
        decodeTargetHeight: targetHeight,
        width: width,
        height: height,
        fit: fit,
        semanticLabel: semanticLabel,
        loading: const _ImagePlaceholder(loading: true),
        fallback: const _ImagePlaceholder(loading: false),
      ),
    );
  }
}

/// Xem trước ảnh vừa chọn trên máy (byte cục bộ, không qua mạng).
class CustomerTicketLocalImage extends StatelessWidget {
  const CustomerTicketLocalImage({
    required this.image,
    required this.size,
    super.key,
  });

  final CustomerTicketImageUpload image;
  final double size;

  @override
  Widget build(BuildContext context) {
    final target = (size * 3).ceil();
    return WebTuiOwnedDecodedImage(
      requestKey: identityHashCode(image.bytes),
      loadBytes: () async => image.bytes,
      maxEncodedBytes: customerTicketMaxImageBytes,
      decodeTargetWidth: target,
      decodeTargetHeight: target,
      width: size,
      height: size,
      fit: BoxFit.cover,
      semanticLabel: image.name,
      loading: const _ImagePlaceholder(loading: true),
      fallback: const _ImagePlaceholder(loading: false),
    );
  }
}

/// Xem ảnh khách gửi cỡ lớn (chụm để phóng to).
Future<void> showCustomerTicketImageViewer(BuildContext context, String url) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _CustomerTicketImageViewer(url: url),
    ),
  );
}

class _CustomerTicketImageViewer extends StatelessWidget {
  const _CustomerTicketImageViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Ảnh khách gửi'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: CustomerTicketRemoteImage(
                  url: url,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  fit: BoxFit.contain,
                  semanticLabel: 'Ảnh khách gửi',
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.backgroundMuted,
        borderRadius: BorderRadius.circular(WebTuiRadii.sm),
      ),
      child: Center(
        child: loading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.broken_image_outlined,
                color: WebTuiColors.textMuted,
              ),
      ),
    );
  }
}
