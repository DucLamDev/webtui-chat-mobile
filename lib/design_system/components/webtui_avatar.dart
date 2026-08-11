import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/network/redirect_safe_file_downloader.dart';
import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
import '../tokens/webtui_typography.dart';
import 'webtui_owned_decoded_image.dart';

const webTuiMaxAvatarImageBytes = 512 * 1024;
const webTuiMaxBrandImageBytes = 1024 * 1024;

typedef WebTuiNetworkImageLoader =
    Future<Uint8List?> Function(
      Uri uri, {
      required int maxBytes,
      required bool allowPublicRequest,
    });

class WebTuiAvatarNetworkScope extends InheritedWidget {
  const WebTuiAvatarNetworkScope({
    required super.child,
    this.apiBaseUri,
    this.cacheKey,
    this.loadBytes,
    super.key,
  });

  final Uri? apiBaseUri;
  final String? cacheKey;
  final WebTuiNetworkImageLoader? loadBytes;

  static WebTuiAvatarNetworkScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WebTuiAvatarNetworkScope>();
  }

  @override
  bool updateShouldNotify(WebTuiAvatarNetworkScope oldWidget) {
    return apiBaseUri != oldWidget.apiBaseUri || cacheKey != oldWidget.cacheKey;
  }
}

enum WebTuiPresenceStatus {
  online,
  away,
  offline;

  Color get color {
    return switch (this) {
      WebTuiPresenceStatus.online => WebTuiColors.accentGreen,
      WebTuiPresenceStatus.away => WebTuiColors.accentAmber,
      WebTuiPresenceStatus.offline => WebTuiColors.textMuted,
    };
  }
}

class WebTuiAvatar extends StatelessWidget {
  const WebTuiAvatar({
    required this.label,
    this.icon,
    this.imageUrl,
    this.status,
    this.color = WebTuiColors.primarySoft,
    this.foregroundColor = WebTuiColors.primary,
    this.size = WebTuiListDensity.avatarSize,
    super.key,
  });

  final String label;
  final IconData? icon;
  final String? imageUrl;
  final WebTuiPresenceStatus? status;
  final Color color;
  final Color foregroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipOval(
              child: DecoratedBox(
                decoration: BoxDecoration(color: color),
                child: WebTuiBoundedNetworkImage(
                  imageUrl: imageUrl,
                  width: size,
                  height: size,
                  maxBytes: webTuiMaxAvatarImageBytes,
                  fit: BoxFit.cover,
                  fallback: _fallback,
                ),
              ),
            ),
          ),
          if (status != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: status!.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: WebTuiColors.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get _initials {
    final normalized = label.trim();
    if (normalized.isEmpty) {
      return '?';
    }

    final words = normalized.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return words.first.characters.take(2).toString().toUpperCase();
    }

    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }

  Widget get _fallback {
    return Center(
      child: icon == null
          ? Text(
              _initials,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w800,
              ),
            )
          : Icon(icon, color: foregroundColor, size: size * 0.5),
    );
  }
}

class WebTuiBoundedNetworkImage extends StatelessWidget {
  const WebTuiBoundedNetworkImage({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.fallback,
    this.fit = BoxFit.contain,
    this.maxBytes = webTuiMaxBrandImageBytes,
    this.allowPublicRequest = false,
    this.semanticLabel,
    super.key,
  });

  final String? imageUrl;
  final double width;
  final double height;
  final Widget fallback;
  final BoxFit fit;
  final int maxBytes;
  final bool allowPublicRequest;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scope = WebTuiAvatarNetworkScope.maybeOf(context);
    final uri = _resolveNetworkImageUri(
      rawValue: imageUrl,
      apiBaseUri: scope?.apiBaseUri,
    );
    final loader = scope?.loadBytes;
    if (uri == null || loader == null || width <= 0 || height <= 0) {
      return fallback;
    }
    final boundedMaxBytes = maxBytes.clamp(1, webTuiMaxBrandImageBytes);
    final requestKey =
        '${scope?.cacheKey ?? ''}|$uri|$boundedMaxBytes|'
        '$allowPublicRequest';
    return WebTuiOwnedDecodedImage(
      key: ValueKey(requestKey),
      requestKey: requestKey,
      loadBytes: () => loader(
        uri,
        maxBytes: boundedMaxBytes,
        allowPublicRequest: allowPublicRequest,
      ),
      maxEncodedBytes: boundedMaxBytes,
      decodeTargetWidth: (width * 3).ceil().clamp(1, 1024),
      decodeTargetHeight: (height * 3).ceil().clamp(1, 1024),
      fit: fit,
      width: width,
      height: height,
      semanticLabel: semanticLabel,
      fallback: fallback,
      loading: fallback,
    );
  }
}

Uri? _resolveNetworkImageUri({
  required String? rawValue,
  required Uri? apiBaseUri,
}) {
  final value = rawValue?.trim();
  if (value == null || value.isEmpty) return null;
  final parsed = Uri.tryParse(value);
  final uri = parsed != null && parsed.hasScheme
      ? parsed
      : apiBaseUri?.resolve(value);
  if (uri == null ||
      !redirectSafeHttpUriAllowed(uri) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }
  return uri;
}
