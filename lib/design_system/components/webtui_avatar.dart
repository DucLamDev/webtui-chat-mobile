import 'package:flutter/material.dart';

import '../tokens/webtui_colors.dart';
import '../tokens/webtui_density.dart';
import '../tokens/webtui_typography.dart';

class WebTuiAvatarNetworkScope extends InheritedWidget {
  const WebTuiAvatarNetworkScope({
    required super.child,
    this.apiBaseUri,
    this.headers,
    super.key,
  });

  final Uri? apiBaseUri;
  final Map<String, String>? headers;

  static WebTuiAvatarNetworkScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WebTuiAvatarNetworkScope>();
  }

  @override
  bool updateShouldNotify(WebTuiAvatarNetworkScope oldWidget) {
    return apiBaseUri != oldWidget.apiBaseUri || headers != oldWidget.headers;
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
    final resolvedImageUrl = _resolvedImageUrl(context);
    final imageHeaders = WebTuiAvatarNetworkScope.maybeOf(context)?.headers;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipOval(
              child: DecoratedBox(
                decoration: BoxDecoration(color: color),
                child: resolvedImageUrl != null
                    ? Image.network(
                        resolvedImageUrl,
                        fit: BoxFit.cover,
                        headers: imageHeaders,
                        errorBuilder: (_, _, _) => _fallback,
                      )
                    : _fallback,
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

  String? _resolvedImageUrl(BuildContext context) {
    final value = imageUrl?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return value;
    }

    final baseUri = WebTuiAvatarNetworkScope.maybeOf(context)?.apiBaseUri;
    if (baseUri == null) {
      return value;
    }
    return baseUri.resolve(value).toString();
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
