import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../icons/webtui_icons.dart';
import 'webtui_avatar.dart';

/// Mở ảnh đại diện toàn màn hình (nền đen, chụm hai ngón để phóng to, chạm
/// nền / nút đóng / vuốt xuống để đóng). Không có ảnh thì không mở gì.
Future<void> showWebTuiAvatarViewer(
  BuildContext context, {
  required String? imageUrl,
  required String name,
  bool allowPublicRequest = false,
}) async {
  if (!webTuiAvatarHasImage(imageUrl)) return;
  await Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      barrierDismissible: true,
      barrierLabel: tr('Đóng ảnh', 'Close photo'),
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => WebTuiAvatarViewer(
        imageUrl: imageUrl!.trim(),
        name: name,
        allowPublicRequest: allowPublicRequest,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Có đường dẫn ảnh để mở trình xem (trống = đang dùng chữ cái / hình người).
bool webTuiAvatarHasImage(String? imageUrl) =>
    imageUrl != null && imageUrl.trim().isNotEmpty;

class WebTuiAvatarViewer extends StatelessWidget {
  const WebTuiAvatarViewer({
    required this.imageUrl,
    required this.name,
    this.allowPublicRequest = false,
    super.key,
  });

  final String imageUrl;
  final String name;
  final bool allowPublicRequest;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final side = size.shortestSide;
    void close() => Navigator.of(context).maybePop();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        key: const Key('avatar_viewer'),
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
                onVerticalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) > 300) close();
                },
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: WebTuiBoundedNetworkImage(
                      imageUrl: imageUrl,
                      width: side,
                      height: side,
                      maxBytes: webTuiMaxAvatarImageBytes,
                      allowPublicRequest: allowPublicRequest,
                      semanticLabel: tr(
                        'Ảnh đại diện của $name',
                        '$name profile photo',
                      ),
                      loading: SizedBox.square(
                        dimension: side,
                        child: const Center(
                          child: CircularProgressIndicator(
                            key: Key('avatar_viewer_loading'),
                            color: Colors.white70,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      // Ảnh lỗi / quá lớn: hiện chữ cái to thay vì vòng tải mãi.
                      fallback: SizedBox.square(
                        dimension: side,
                        child: Center(
                          child: WebTuiAvatar(
                            key: const Key('avatar_viewer_fallback'),
                            label: name,
                            size: side * 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Row(
                children: [
                  IconButton(
                    key: const Key('avatar_viewer_close'),
                    tooltip: tr('Đóng', 'Close'),
                    onPressed: close,
                    icon: const Icon(
                      WebTuiIcons.close,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
