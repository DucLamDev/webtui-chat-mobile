import 'package:flutter/material.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../controllers/ide_web_controller.dart';
import 'ide_web_buttons.dart';
import 'ide_web_code_window.dart';

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
    final c = WebTuiColors.of(context);
    final cancel = IdeWebAction(
      key: const Key('ide_web_cancel'),
      label: tr('Huỷ', 'Cancel'),
      onPressed: onClose,
    );
    final close = IdeWebAction(
      key: const Key('ide_web_close_action'),
      label: tr('Đóng', 'Close'),
      onPressed: onClose,
    );
    IdeWebAction retry(String label) => IdeWebAction(
      key: const Key('ide_web_retry'),
      label: label,
      onPressed: onRetry,
    );
    return switch (state) {
      IdeWebLoading() || IdeWebReady() || IdeWebClosed() => _Frame(
        key: const Key('ide_web_loading'),
        mood: IdeWebWindowMood.opening,
        title: tr('Đang mở VPSTTT IDE…', 'Opening VPSTTT IDE…'),
        message: tr(
          'Đang nối tới không gian làm việc của bạn.',
          'Connecting to your workspace.',
        ),
        secondary: cancel,
      ),
      IdeWebWaitingBrowser() => _Frame(
        key: const Key('ide_web_waiting'),
        mood: IdeWebWindowMood.browser,
        title: tr('Đăng nhập trong trình duyệt', 'Sign in in your browser'),
        body: _Steps([
          tr(
            'Đăng nhập ở trang vừa mở trong trình duyệt',
            'Sign in on the page that just opened',
          ),
          tr(
            'Làm theo bước xác nhận trên trang đó',
            'Follow the confirmation steps there',
          ),
          tr(
            'Xong thì ứng dụng tự mở VPSTTT IDE',
            'The app opens VPSTTT IDE by itself',
          ),
        ]),
        primary: retry(tr('Mở lại trang đăng nhập', 'Reopen the sign-in page')),
        secondary: cancel,
      ),
      IdeWebUnavailable(rateLimited: true) => _Frame(
        key: const Key('ide_web_unavailable'),
        badge: Icons.hourglass_top_rounded,
        badgeColor: IdeWebInk.alertAmber,
        title: tr('Mở quá nhiều lần', 'Too many attempts'),
        message: tr(
          'Chờ ít phút rồi thử lại. Trò chuyện không bị ảnh hưởng.',
          'Wait a few minutes and try again. Chat is not affected.',
        ),
        primary: retry(tr('Thử lại', 'Retry')),
        secondary: close,
      ),
      IdeWebUnavailable() => _Frame(
        key: const Key('ide_web_unavailable'),
        badge: Icons.cloud_off_rounded,
        badgeColor: IdeWebInk.alertRed,
        title: tr(
          'Chưa kết nối được VPSTTT IDE',
          'Could not connect to VPSTTT IDE',
        ),
        message: tr(
          'Kiểm tra mạng rồi thử lại.',
          'Check your connection and try again.',
        ),
        body: _StatusRows([
          (
            icon: Icons.chat_bubble_rounded,
            label: tr('Trò chuyện', 'Chat'),
            value: tr('Không bị ảnh hưởng', 'Not affected'),
            color: c.accentGreen,
          ),
          (
            icon: Icons.dns_rounded,
            label: tr('Máy chủ IDE', 'IDE server'),
            value: tr('Chưa phản hồi', 'No response'),
            color: c.danger,
          ),
        ]),
        primary: retry(tr('Thử lại', 'Retry')),
        secondary: close,
      ),
      IdeWebDisabled() => _Frame(
        key: const Key('ide_web_disabled'),
        badge: Icons.power_settings_new_rounded,
        badgeColor: IdeWebInk.slate,
        title: tr('VPSTTT IDE đang tắt', 'VPSTTT IDE is turned off'),
        message: tr(
          'Quản trị đang tạm tắt. Vui lòng quay lại sau.',
          'Your administrator has turned it off. Come back later.',
        ),
        secondary: close,
      ),
      IdeWebNotAllowed() => _Frame(
        key: const Key('ide_web_not_allowed'),
        badge: Icons.lock_rounded,
        badgeColor: IdeWebInk.slate,
        title: tr('Chưa được cấp quyền', 'No access yet'),
        message: tr(
          'Tài khoản của bạn chưa được dùng VPSTTT IDE. Liên hệ quản trị để được cấp quyền.',
          'Your account cannot use VPSTTT IDE yet. Ask your administrator for access.',
        ),
        secondary: close,
      ),
      IdeWebExpired() => _Frame(
        key: const Key('ide_web_expired'),
        badge: Icons.history_rounded,
        badgeColor: c.primaryFill,
        title: tr('Phiên đã hết hạn', 'Session expired'),
        message: tr(
          'Mở lại để tiếp tục làm việc trong VPSTTT IDE.',
          'Reopen to keep working in VPSTTT IDE.',
        ),
        primary: retry(tr('Mở lại', 'Reopen')),
        secondary: close,
      ),
      IdeWebViewTooOld() => _Frame(
        key: const Key('ide_web_too_old'),
        badge: Icons.system_update_rounded,
        badgeColor: IdeWebInk.alertAmber,
        title: tr(
          'Cần cập nhật Android System WebView',
          'Update Android System WebView',
        ),
        message: tr(
          'Cập nhật trong kho ứng dụng rồi mở lại VPSTTT IDE.',
          'Update it in the app store, then open VPSTTT IDE again.',
        ),
        secondary: close,
      ),
    };
  }
}

/// Khung chung: hình ở trên, chữ căn trái (dài thì cuộn), nút luôn ghim đáy. Màn
/// thấp hoặc chữ to thì hình thu nhỏ.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    this.mood = IdeWebWindowMood.resting,
    this.badge,
    this.badgeColor,
    this.message,
    this.body,
    this.primary,
    this.secondary,
    super.key,
  });

  final IdeWebWindowMood mood;
  final IconData? badge;
  final Color? badgeColor;
  final String title;
  final String? message;
  final Widget? body;
  final IdeWebAction? primary;
  final IdeWebAction? secondary;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    final message = this.message;
    final body = this.body;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 600 || ideWebLargeText(context);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      // Hình ở một chỗ cố định: đổi trạng thái không bị nhảy.
                      compact ? 12 : (box.maxHeight * 0.07).clamp(20, 64),
                      24,
                      20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        IdeWebCodeWindow(
                          mood: mood,
                          height: compact ? 120 : 200,
                          badge: badge,
                          badgeColor: badgeColor,
                        ),
                        SizedBox(height: compact ? 20 : 28),
                        Semantics(
                          container: true,
                          liveRegion: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                title,
                                style: WebTuiTypography.titleLarge.copyWith(
                                  fontSize: 24,
                                  height: 1.25,
                                  fontWeight: FontWeight.w800,
                                  color: c.textPrimary,
                                ),
                              ),
                              if (message != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  message,
                                  style: WebTuiTypography.bodyMedium.copyWith(
                                    fontSize: 15.5,
                                    height: 1.5,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (body != null) ...[const SizedBox(height: 20), body],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (primary case final action?) ...[
                        IdeWebButton.primary(action),
                        const SizedBox(height: WebTuiSpacing.xs),
                      ],
                      if (secondary case final action?)
                        IdeWebButton.secondary(action),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Các bước theo thứ tự (số có nghĩa: phải làm lần lượt).
class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    textScaler: TextScaler.noScaling,
                    style: WebTuiTypography.labelSmall.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      steps[i],
                      style: WebTuiTypography.bodyMedium.copyWith(
                        fontSize: 15.5,
                        height: 1.4,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

typedef _StatusRow = ({IconData icon, String label, String value, Color color});

/// Phần nào còn chạy, phần nào hỏng.
class _StatusRows extends StatelessWidget {
  const _StatusRows(this.rows);

  final List<_StatusRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = WebTuiColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 48, color: c.hairline),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(rows[i].icon, size: 20, color: c.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        Text(
                          rows[i].label,
                          style: WebTuiTypography.bodyMedium.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: rows[i].color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                rows[i].value,
                                style: WebTuiTypography.bodySmall.copyWith(
                                  fontSize: 14,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
