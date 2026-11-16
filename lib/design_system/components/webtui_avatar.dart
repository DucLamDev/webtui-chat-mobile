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

/// Ảnh đại diện tròn, không viền / nền bao: ảnh phủ kín vòng tròn và canh lên
/// phía trên (nơi thường có mặt); chưa có ảnh thì 2 chữ cái trắng (hoặc biểu
/// tượng trắng) trên dải màu chéo. Chấm trạng thái nằm trên mép tròn ở góc
/// 4 giờ 30, viền cùng màu nền để không đè vào mặt.
class WebTuiAvatar extends StatelessWidget {
  const WebTuiAvatar({
    required this.label,
    this.icon,
    this.imageUrl,
    this.status,
    this.color,
    this.foregroundColor,
    this.gradientBase,
    this.size = WebTuiListDensity.avatarSize,
    this.allowPublicRequest = false,
    this.square = false,
    super.key,
  });

  /// Ô vuông bo góc thay vì ảnh tròn (logo tổ chức, ảnh xem trước tệp).
  final bool square;

  /// Ảnh công khai (logo tổ chức), không cần đăng nhập để tải.
  final bool allowPublicRequest;
  final String label;
  final IconData? icon;
  final String? imageUrl;
  final WebTuiPresenceStatus? status;

  /// Nền đặc thay cho dải màu (giữ cho chỗ cần nền riêng).
  final Color? color;
  final Color? foregroundColor;

  /// Màu gốc của dải màu (kênh theo loại biểu tượng); trống thì chọn một trong
  /// [webTuiAvatarGradients] theo tên.
  final Color? gradientBase;
  final double size;

  /// Ảnh chân dung: canh dọc ở 32% từ trên xuống (Alignment y = 0,32 × 2 − 1).
  static const imageAlignment = Alignment(0, -0.36);

  @override
  Widget build(BuildContext context) {
    final dot = webTuiPresenceDotSize(size);
    // Tâm chấm nằm trên mép tròn ở góc 45°: cách mép hộp size × (1 − cos45°) / 2.
    final inset = size * 0.1464 - dot / 2;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: _clip(
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  gradient: color == null ? _gradient : null,
                ),
                child: WebTuiBoundedNetworkImage(
                  imageUrl: imageUrl,
                  width: size,
                  height: size,
                  maxBytes: webTuiMaxAvatarImageBytes,
                  allowPublicRequest: allowPublicRequest,
                  fit: BoxFit.cover,
                  alignment: square ? Alignment.center : imageAlignment,
                  fallback: _fallback,
                ),
              ),
            ),
          ),
          if (status != null)
            Positioned(
              right: inset,
              bottom: inset,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: status!.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: WebTuiColors.page,
                    width: dot >= 14 ? 2.5 : 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _clip(Widget child) {
    if (!square) return ClipOval(child: child);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: child,
    );
  }

  LinearGradient get _gradient {
    final base = gradientBase;
    if (base != null) {
      return LinearGradient(
        begin: const Alignment(-0.35, -1),
        end: const Alignment(0.35, 1),
        colors: [Color.lerp(base, Colors.white, 0.16)!, base],
      );
    }
    return webTuiAvatarGradientFor(label);
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
    final foreground = foregroundColor ?? Colors.white;
    return Center(
      child: icon == null
          ? Text(
              _initials,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: foreground,
                fontSize: (size * 0.36).clamp(11, 34).toDouble(),
                height: 1,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(icon, color: foreground, size: size * 0.48),
    );
  }
}

/// Cỡ chấm trạng thái theo cỡ ảnh đại diện.
double webTuiPresenceDotSize(double avatarSize) {
  if (avatarSize >= 80) return 20;
  if (avatarSize >= 48) return 14;
  if (avatarSize >= 36) return 12;
  return 10;
}

/// 8 dải màu cho ảnh chưa có hình: giữa dải đạt từ 4,9:1 với chữ trắng.
const webTuiAvatarGradients = <List<Color>>[
  [Color(0xFFE5454D), Color(0xFFBF1E29)],
  [Color(0xFFCC5F1C), Color(0xFFA04008)],
  [Color(0xFF1E9152), Color(0xFF0E6836)],
  [Color(0xFF169290), Color(0xFF09625F)],
  [Color(0xFF3277E0), Color(0xFF1653B8)],
  [Color(0xFF6E5BD8), Color(0xFF4834B3)],
  [Color(0xFFC24A93), Color(0xFF922766)],
  [Color(0xFF1F82B5), Color(0xFF0D5A84)],
];

/// Dải màu cố định theo tên (cùng một người luôn cùng một màu).
LinearGradient webTuiAvatarGradientFor(String label) {
  var hash = 0;
  for (final unit in label.trim().toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final colors = webTuiAvatarGradients[hash % webTuiAvatarGradients.length];
  return LinearGradient(
    begin: const Alignment(-0.35, -1),
    end: const Alignment(0.35, 1),
    colors: colors,
  );
}

class WebTuiBoundedNetworkImage extends StatelessWidget {
  const WebTuiBoundedNetworkImage({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.fallback,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
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
  final AlignmentGeometry alignment;
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
      alignment: alignment,
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
