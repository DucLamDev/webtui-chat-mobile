import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../workspace/presentation/screens/workspace_selector_screen.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/login_mfa.dart';
import '../controllers/auth_flow_providers.dart';
import '../controllers/login_mfa_controller.dart';
import 'device_approval_pending_screen.dart';

/// Lượt chờ nằm trong bộ nhớ (`pendingLoginMfaChallengeProvider`), không nằm
/// trên đường dẫn.
const loginMfaPath = '/login-mfa';

/// Bước xác thực hai lớp sau mật khẩu / SSO / xác minh email.
class LoginMfaScreen extends ConsumerStatefulWidget {
  const LoginMfaScreen({super.key});

  @override
  ConsumerState<LoginMfaScreen> createState() => _LoginMfaScreenState();
}

class _LoginMfaScreenState extends ConsumerState<LoginMfaScreen> {
  final _codeController = TextEditingController();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _backToLogin() {
    ref.read(pendingLoginMfaChallengeProvider.notifier).state = null;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/login');
    }
  }

  void _onVerified(AuthSession session) {
    ref.read(pendingLoginMfaChallengeProvider.notifier).state = null;
    ref.invalidate(authAccessTokenProvider);
    if (session.isPendingApproval) {
      context.go(deviceApprovalPendingPath);
    } else {
      context.go(workspacePickerAfterLoginPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<LoginMfaState>(loginMfaControllerProvider, (previous, next) {
      final session = next.session;
      if (session != null && previous?.session == null) {
        _onVerified(session);
      }
      if (_codeController.text != next.code) {
        _codeController.value = TextEditingValue(
          text: next.code,
          selection: TextSelection.collapsed(offset: next.code.length),
        );
      }
    });
    final state = ref.watch(loginMfaControllerProvider);
    final controller = ref.read(loginMfaControllerProvider.notifier);
    final challenge = state.challenge;

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        leading: IconButton(
          key: const Key('login_mfa_back_button'),
          tooltip: tr('Quay lại', 'Back'),
          onPressed: _backToLogin,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(tr('Xác thực hai lớp', 'Two-factor verification')),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: challenge == null
            ? WebTuiErrorState(
                title: tr(
                  'Lượt xác thực không còn',
                  'The verification is no longer available',
                ),
                message: tr(
                  'Hãy đăng nhập lại để nhận lượt xác thực mới.',
                  'Sign in again to start a new verification.',
                ),
                onRetry: _backToLogin,
              )
            : challenge.onlyPasskey
            ? _PasskeyOnlyContent(onBack: _backToLogin)
            : _CodeContent(
                state: state,
                controller: controller,
                codeController: _codeController,
                secondsLeft: controller.secondsLeft(),
                onBack: _backToLogin,
              ),
      ),
    );
  }
}

class _CodeContent extends StatelessWidget {
  const _CodeContent({
    required this.state,
    required this.controller,
    required this.codeController,
    required this.secondsLeft,
    required this.onBack,
  });

  final LoginMfaState state;
  final LoginMfaController controller;
  final TextEditingController codeController;
  final int secondsLeft;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final challenge = state.challenge!;
    final method = state.method ?? LoginMfaMethod.totp;
    final totp = method == LoginMfaMethod.totp;
    final expired = state.mustRestart || secondsLeft <= 0;
    final errorMessage =
        state.errorMessage ??
        (expired
            ? tr(
                'Lượt đăng nhập đã hết hạn. Vui lòng nhập lại mật khẩu.',
                'This sign-in has expired. Please enter your password again.',
              )
            : null);
    final alternative = challenge.usableMethods
        .where((candidate) => candidate != method)
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        Icon(WebTuiIcons.shieldCheck, size: 56, color: WebTuiColors.primary),
        const SizedBox(height: WebTuiSpacing.md),
        Text(
          totp
              ? tr(
                  'Nhập mã 6 số từ ứng dụng xác thực',
                  'Enter the 6-digit code from your authenticator app',
                )
              : tr('Nhập mã khôi phục', 'Enter a recovery code'),
          textAlign: TextAlign.center,
          style: WebTuiTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.xs),
        Text(
          totp
              ? tr(
                  'Tài khoản đã bật xác thực hai lớp. Mở ứng dụng xác thực '
                      '(Google Authenticator, Microsoft Authenticator...) để lấy mã.',
                  'Your account uses two-factor verification. Open your '
                      'authenticator app to get the code.',
                )
              : tr(
                  'Mã khôi phục có dạng XXXXX-XXXXX, mỗi mã chỉ dùng được một lần.',
                  'A recovery code looks like XXXXX-XXXXX and works only once.',
                ),
          textAlign: TextAlign.center,
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textMuted,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.lg),
        TextField(
          key: const Key('login_mfa_code_field'),
          controller: codeController,
          enabled: !state.isSubmitting && !expired,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: totp ? TextInputType.number : TextInputType.text,
          textCapitalization: totp
              ? TextCapitalization.none
              : TextCapitalization.characters,
          textAlign: TextAlign.center,
          autofillHints: totp ? const [AutofillHints.oneTimeCode] : null,
          inputFormatters: totp
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          style: WebTuiTypography.titleMedium.copyWith(
            letterSpacing: totp ? 12 : 4,
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: totp ? '••••••' : 'XXXXX-XXXXX',
            border: const OutlineInputBorder(),
          ),
          onChanged: controller.updateCode,
          onSubmitted: (_) => controller.submit(),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          Text(
            errorMessage,
            key: const Key('login_mfa_error'),
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ] else ...[
          const SizedBox(height: WebTuiSpacing.sm),
          Text(
            tr(
              'Lượt đăng nhập còn hiệu lực ${_formatSeconds(secondsLeft)}',
              'This sign-in stays valid for ${_formatSeconds(secondsLeft)}',
            ),
            key: const Key('login_mfa_countdown'),
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textMuted,
            ),
          ),
        ],
        const SizedBox(height: WebTuiSpacing.lg),
        if (expired)
          FilledButton(
            key: const Key('login_mfa_restart_button'),
            onPressed: onBack,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: Text(tr('Đăng nhập lại', 'Sign in again')),
          )
        else
          FilledButton(
            key: const Key('login_mfa_submit_button'),
            onPressed: state.canSubmit ? controller.submit : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: state.isSubmitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Text(tr('Xác nhận', 'Confirm')),
          ),
        if (alternative != null && !expired) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          TextButton(
            key: const Key('login_mfa_switch_method'),
            onPressed: state.canSwitchMethod
                ? () => controller.selectMethod(alternative)
                : null,
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            child: Text(
              alternative == LoginMfaMethod.recoveryCode
                  ? tr('Dùng mã khôi phục', 'Use a recovery code')
                  : tr(
                      'Dùng mã từ ứng dụng xác thực',
                      'Use a code from your authenticator app',
                    ),
            ),
          ),
        ],
        if (challenge.methods.contains(LoginMfaMethod.passkey)) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          Text(
            tr(
              'Passkey chưa dùng được trên ứng dụng; hãy dùng mã ở trên hoặc đăng nhập trên web.',
              'Passkeys are not available in the app yet; use a code above or sign in on the web.',
            ),
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _PasskeyOnlyContent extends StatelessWidget {
  const _PasskeyOnlyContent({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        DecoratedBox(
          key: const Key('login_mfa_passkey_only'),
          decoration: BoxDecoration(
            color: WebTuiColors.surfaceElevated,
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            border: Border.all(color: WebTuiColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(WebTuiSpacing.lg),
            child: Column(
              children: [
                Icon(WebTuiIcons.key, size: 48, color: WebTuiColors.primary),
                const SizedBox(height: WebTuiSpacing.md),
                Text(
                  tr(
                    'Tài khoản chỉ bật passkey',
                    'This account only uses a passkey',
                  ),
                  textAlign: TextAlign.center,
                  style: WebTuiTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.xs),
                Text(
                  tr(
                    'Ứng dụng chưa hỗ trợ passkey. Hãy đăng nhập trên trình duyệt web, '
                        'rồi bật thêm mã từ ứng dụng xác thực (TOTP) để đăng nhập được trên điện thoại.',
                    'The app does not support passkeys yet. Sign in on the web, then '
                        'turn on authenticator app codes (TOTP) to sign in on your phone.',
                  ),
                  textAlign: TextAlign.center,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WebTuiSpacing.lg),
        FilledButton(
          key: const Key('login_mfa_restart_button'),
          onPressed: onBack,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: Text(tr('Quay lại đăng nhập', 'Back to sign-in')),
        ),
      ],
    );
  }
}

String _formatSeconds(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
