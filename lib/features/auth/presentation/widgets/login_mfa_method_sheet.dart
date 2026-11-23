import 'package:flutter/material.dart';

import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/login_mfa.dart';

/// Bảng chọn cách xác minh khác. Trả cách người dùng chọn (null khi đóng hoặc
/// chọn lại cách đang dùng). Passkey hiện mờ vì ứng dụng chưa hỗ trợ.
Future<LoginMfaMethod?> showLoginMfaMethodSheet(
  BuildContext context, {
  required List<LoginMfaMethod> methods,
  required LoginMfaMethod? current,
}) {
  return showModalBottomSheet<LoginMfaMethod>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => LoginMfaMethodSheet(methods: methods, current: current),
  );
}

class LoginMfaMethodSheet extends StatefulWidget {
  const LoginMfaMethodSheet({
    required this.methods,
    required this.current,
    super.key,
  });

  final List<LoginMfaMethod> methods;
  final LoginMfaMethod? current;

  @override
  State<LoginMfaMethodSheet> createState() => _LoginMfaMethodSheetState();
}

class _LoginMfaMethodSheetState extends State<LoginMfaMethodSheet> {
  bool _passkeyExplained = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.md,
        0,
        WebTuiSpacing.md,
        WebTuiSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.md,
              0,
              WebTuiSpacing.md,
              WebTuiSpacing.sm,
            ),
            child: Semantics(
              header: true,
              child: Text(
                tr('Chọn cách xác minh', 'Choose how to verify'),
                style: WebTuiTypography.titleMedium.copyWith(
                  fontSize: 18,
                  color: WebTuiColors.textPrimary,
                ),
              ),
            ),
          ),
          for (final method in widget.methods)
            _MethodRow(
              key: Key('login_mfa_method_${method.apiValue}'),
              method: method,
              selected: method == widget.current,
              onTap: method.supportedInApp
                  ? () => Navigator.of(
                      context,
                    ).pop(method == widget.current ? null : method)
                  : () => setState(() => _passkeyExplained = true),
            ),
          if (_passkeyExplained)
            Padding(
              key: const Key('login_mfa_passkey_explanation'),
              padding: const EdgeInsets.fromLTRB(
                56 + WebTuiSpacing.md,
                0,
                WebTuiSpacing.md,
                WebTuiSpacing.sm,
              ),
              child: Text(
                tr(
                  'Passkey cần trình duyệt xác nhận khoá trên máy. Hãy đăng nhập '
                      'bằng passkey trên trình duyệt, rồi bật thêm ứng dụng xác '
                      'thực trong Cài đặt › Bảo mật để đăng nhập được trên điện thoại.',
                  'Passkeys need a browser to confirm the key on your device. Sign '
                      'in with your passkey in a browser, then turn on an '
                      'authenticator app in Settings › Security to sign in on your phone.',
                ),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.method,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final LoginMfaMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = method.supportedInApp;
    final (icon, title, subtitle) = switch (method) {
      LoginMfaMethod.totp => (
        WebTuiIcons.shieldCheck,
        tr('Ứng dụng xác thực', 'Authenticator app'),
        tr(
          'Nhập mã 6 số đang hiện trên điện thoại',
          'Enter the 6-digit code shown on your phone',
        ),
      ),
      LoginMfaMethod.recoveryCode => (
        WebTuiIcons.key,
        tr('Mã khôi phục', 'Recovery code'),
        tr(
          'Dùng khi không có điện thoại bên cạnh',
          'Use it when your phone is not with you',
        ),
      ),
      LoginMfaMethod.passkey => (
        WebTuiIcons.fingerprint,
        'Passkey',
        tr(
          'Chưa hỗ trợ trên ứng dụng, hãy dùng trình duyệt',
          'Not supported in the app yet, use a browser',
        ),
      ),
    };

    return Semantics(
      button: true,
      selected: selected,
      hint: available
          ? null
          : tr('Chưa dùng được trên ứng dụng', 'Not available in the app'),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WebTuiSpacing.md,
              vertical: WebTuiSpacing.md,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Icon(
                    icon,
                    size: 24,
                    color: available
                        ? WebTuiColors.primary
                        : WebTuiColors.textMuted,
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: WebTuiTypography.bodyMedium.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: available
                              ? WebTuiColors.textPrimary
                              : WebTuiColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: WebTuiSpacing.xxs),
                      Text(
                        subtitle,
                        style: WebTuiTypography.bodySmall.copyWith(
                          color: available
                              ? WebTuiColors.textSecondary
                              : WebTuiColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: WebTuiSpacing.sm),
                  Icon(
                    WebTuiIcons.check,
                    size: 20,
                    color: WebTuiColors.primary,
                    semanticLabel: tr('Đang dùng', 'In use'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
