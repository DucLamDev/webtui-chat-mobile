import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../controllers/ide_web_controller.dart';

/// Màn trạng thái của VPSTTT IDE (mọi trạng thái trừ lúc đã mở trang).
class IdeWebStateView extends StatelessWidget {
  const IdeWebStateView({
    required this.state,
    required this.onRetry,
    required this.onClose,
    super.key,
  });

  final IdeWebState state;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cancel = (
      key: const Key('ide_web_cancel'),
      label: tr('Huỷ', 'Cancel'),
      onPressed: onClose,
    );
    final close = (
      key: const Key('ide_web_close_action'),
      label: tr('Đóng', 'Close'),
      onPressed: onClose,
    );
    final reopen = (
      key: const Key('ide_web_retry'),
      label: tr('Mở lại', 'Reopen'),
      onPressed: onRetry,
    );
    return switch (state) {
      IdeWebLoading() || IdeWebReady() || IdeWebClosed() => _Frame(
        key: const Key('ide_web_loading'),
        title: tr('Đang mở VPSTTT IDE…', 'Opening VPSTTT IDE…'),
        busy: true,
        secondary: cancel,
      ),
      IdeWebWaitingBrowser() => _Frame(
        key: const Key('ide_web_waiting'),
        icon: Icons.open_in_browser_rounded,
        title: tr(
          'Hoàn tất đăng nhập trong trình duyệt',
          'Finish signing in in your browser',
        ),
        message: tr(
          'Đăng nhập xong, ứng dụng tự mở VPSTTT IDE.',
          'VPSTTT IDE opens here once you have signed in.',
        ),
        primary: reopen,
        secondary: cancel,
      ),
      IdeWebUnavailable(:final rateLimited) => _Frame(
        key: const Key('ide_web_unavailable'),
        icon: Icons.wifi_off_rounded,
        title: rateLimited
            ? tr('Mở quá nhiều lần', 'Too many attempts')
            : tr(
                'Chưa kết nối được VPSTTT IDE',
                'Could not connect to VPSTTT IDE',
              ),
        message: rateLimited
            ? tr(
                'Chờ ít phút rồi thử lại. Tin nhắn vẫn dùng bình thường.',
                'Wait a few minutes and try again. Chat is not affected.',
              )
            : tr(
                'Kiểm tra mạng rồi thử lại. Tin nhắn vẫn dùng bình thường.',
                'Check your connection and try again. Chat is not affected.',
              ),
        primary: (
          key: const Key('ide_web_retry'),
          label: tr('Thử lại', 'Retry'),
          onPressed: onRetry,
        ),
        secondary: close,
      ),
      IdeWebDisabled() => _Frame(
        key: const Key('ide_web_disabled'),
        icon: Icons.power_settings_new_rounded,
        title: tr('VPSTTT IDE đang tắt', 'VPSTTT IDE is turned off'),
        message: tr(
          'Quản trị đang tắt VPSTTT IDE. Vui lòng quay lại sau.',
          'Your administrator has turned VPSTTT IDE off. Come back later.',
        ),
        secondary: close,
      ),
      IdeWebNotAllowed() => _Frame(
        key: const Key('ide_web_not_allowed'),
        icon: Icons.lock_outline_rounded,
        title: tr('Chưa được cấp quyền', 'No access yet'),
        message: tr(
          'Tài khoản của bạn chưa được dùng VPSTTT IDE. Liên hệ quản trị để được cấp quyền.',
          'Your account cannot use VPSTTT IDE yet. Ask your administrator for access.',
        ),
        secondary: close,
      ),
      IdeWebExpired() => _Frame(
        key: const Key('ide_web_expired'),
        icon: Icons.schedule_rounded,
        title: tr('Phiên đã hết hạn', 'Session expired'),
        message: tr(
          'Mở lại để tiếp tục dùng VPSTTT IDE.',
          'Reopen to keep using VPSTTT IDE.',
        ),
        primary: reopen,
        secondary: close,
      ),
      IdeWebViewTooOld() => _Frame(
        key: const Key('ide_web_too_old'),
        icon: Icons.system_update_rounded,
        title: tr(
          'Cần cập nhật Android System WebView',
          'Update Android System WebView',
        ),
        message: tr(
          'Cập nhật Android System WebView trong kho ứng dụng rồi mở lại VPSTTT IDE.',
          'Update Android System WebView in the app store, then open VPSTTT IDE again.',
        ),
        secondary: close,
      ),
    };
  }
}

typedef _Action = ({Key key, String label, VoidCallback onPressed});

/// Khung chung: cuộn được nên chữ to không bị cắt.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    this.message,
    this.icon,
    this.busy = false,
    this.primary,
    this.secondary,
    super.key,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final bool busy;
  final _Action? primary;
  final _Action? secondary;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    final message = this.message;
    final primary = this.primary;
    final secondary = this.secondary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WebTuiSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (busy)
                Center(
                  child: SizedBox.square(
                    dimension: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: c.primary,
                    ),
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 40, color: c.textSecondary),
              const SizedBox(height: WebTuiSpacing.lg),
              Semantics(
                container: true,
                liveRegion: true,
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: WebTuiTypography.titleMedium.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: WebTuiSpacing.sm),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: WebTuiTypography.bodyMedium.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: WebTuiSpacing.xl),
              if (primary != null) ...[
                FilledButton(
                  key: primary.key,
                  onPressed: primary.onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.primaryFill,
                    foregroundColor: c.textOnPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(primary.label),
                ),
                const SizedBox(height: WebTuiSpacing.sm),
              ],
              if (secondary != null)
                TextButton(
                  key: secondary.key,
                  onPressed: secondary.onPressed,
                  style: TextButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(secondary.label),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
