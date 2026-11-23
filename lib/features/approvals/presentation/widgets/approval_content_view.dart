import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../domain/entities/approval.dart';

/// Mở liên kết `https://` ở trình duyệt ngoài; trả `false` nếu không mở được.
typedef ApprovalLinkOpener = Future<bool> Function(Uri uri);

/// Khối nội dung để người duyệt đọc: chữ (chọn / chép được), ảnh, các ô nhãn /
/// giá trị và nút mở liên kết (chỉ khi `https://`).
class ApprovalContentView extends StatelessWidget {
  const ApprovalContentView({
    required this.content,
    this.onOpenLink,
    super.key,
  });

  final ApprovalContent content;
  final ApprovalLinkOpener? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final text = content.text;
    final image = content.imageUrl;
    final link = content.link;
    final linkUri = link?.uri;
    final theme = Theme.of(context);
    return Column(
      key: const Key('approval_content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (text.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: WebTuiColors.surface,
              borderRadius: BorderRadius.circular(WebTuiRadii.md),
              border: Border.all(color: WebTuiColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(WebTuiSpacing.md),
              child: SelectableText(
                text,
                key: const Key('approval_content_text'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: WebTuiColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ),
          ),
        if (image != null) ...[
          if (text.isNotEmpty) const SizedBox(height: WebTuiSpacing.md),
          ApprovalContentImage(imageUrl: image),
        ],
        if (content.fields.isNotEmpty) ...[
          const SizedBox(height: WebTuiSpacing.md),
          _Fields(fields: content.fields),
        ],
        if (link != null && linkUri != null && onOpenLink != null) ...[
          const SizedBox(height: WebTuiSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const Key('approval_content_link'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              label: Text(
                link.label.isEmpty
                    ? tr('Mở liên kết', 'Open link')
                    : link.label,
              ),
              onPressed: () => _open(context, linkUri),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await onOpenLink!(uri);
    if (!opened) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr('Không mở được liên kết.', 'Couldn\'t open the link.'),
          ),
        ),
      );
    }
  }
}

class _Fields extends StatelessWidget {
  const _Fields({required this.fields});

  final List<ApprovalContentField> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Chữ to: nhãn nằm trên giá trị để không bị bẻ từng chữ.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 18;
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: WebTuiColors.textSecondary,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: WebTuiColors.textPrimary,
      fontWeight: FontWeight.w500,
    );
    return DecoratedBox(
      key: const Key('approval_content_fields'),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: WebTuiColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) Divider(height: 1, color: WebTuiColors.hairline),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WebTuiSpacing.md,
                vertical: WebTuiSpacing.sm,
              ),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(fields[i].label, style: labelStyle),
                        const SizedBox(height: WebTuiSpacing.xxs),
                        SelectableText(fields[i].value, style: valueStyle),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 112,
                          child: Text(fields[i].label, style: labelStyle),
                        ),
                        const SizedBox(width: WebTuiSpacing.sm),
                        Expanded(
                          child: SelectableText(
                            fields[i].value,
                            style: valueStyle,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ảnh kèm nội dung: khung cố định, có ô chờ tải và ô báo lỗi; bấm để xem
/// toàn màn. Ảnh tải không kèm thông tin đăng nhập (máy chủ ảnh là bên ngoài).
class ApprovalContentImage extends StatelessWidget {
  const ApprovalContentImage({required this.imageUrl, super.key});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final height = math.min(width * 3 / 4, 360.0);
        return Semantics(
          button: true,
          label: tr(
            'Ảnh đính kèm, chạm để xem lớn',
            'Attached image, tap to enlarge',
          ),
          child: Material(
            color: WebTuiColors.backgroundMuted,
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('approval_content_image'),
              onTap: () => showApprovalImageViewer(context, imageUrl),
              child: WebTuiBoundedNetworkImage(
                imageUrl: imageUrl,
                width: width,
                height: height,
                maxBytes: webTuiMaxContentImageBytes,
                allowPublicRequest: true,
                semanticLabel: tr('Ảnh đính kèm', 'Attached image'),
                loading: _ImageState.loading(width: width, height: height),
                fallback: _ImageState.error(width: width, height: height),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ImageState extends StatelessWidget {
  const _ImageState.loading({required this.width, required this.height})
    : failed = false;

  const _ImageState.error({required this.width, required this.height})
    : failed = true;

  final double width;
  final double height;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: failed
            ? Padding(
                key: const Key('approval_content_image_error'),
                padding: const EdgeInsets.all(WebTuiSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      size: 32,
                      color: WebTuiColors.textSecondary,
                    ),
                    const SizedBox(height: WebTuiSpacing.xs),
                    Text(
                      tr('Không tải được ảnh', 'Couldn\'t load the image'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: WebTuiColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.square(
                key: Key('approval_content_image_loading'),
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      ),
    );
  }
}

/// Xem ảnh toàn màn (nền đen, chụm hai ngón để phóng to, chạm / vuốt xuống
/// hoặc nút đóng để đóng).
Future<void> showApprovalImageViewer(BuildContext context, String imageUrl) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      barrierDismissible: true,
      barrierLabel: tr('Đóng ảnh', 'Close image'),
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => _ApprovalImageViewer(imageUrl: imageUrl),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _ApprovalImageViewer extends StatelessWidget {
  const _ApprovalImageViewer({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    void close() => Navigator.of(context).maybePop();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        key: const Key('approval_image_viewer'),
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
                      width: size.width,
                      height: size.height,
                      maxBytes: webTuiMaxContentImageBytes,
                      allowPublicRequest: true,
                      semanticLabel: tr('Ảnh đính kèm', 'Attached image'),
                      loading: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white70,
                          strokeWidth: 2,
                        ),
                      ),
                      fallback: Center(
                        child: Text(
                          tr('Không tải được ảnh', 'Couldn\'t load the image'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: IconButton(
                  key: const Key('approval_image_viewer_close'),
                  tooltip: tr('Đóng', 'Close'),
                  onPressed: close,
                  icon: const Icon(
                    WebTuiIcons.close,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
