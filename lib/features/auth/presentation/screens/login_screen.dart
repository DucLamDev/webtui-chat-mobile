import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/flavor/app_config.dart';
import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/email_verification.dart';
import '../controllers/auth_flow_providers.dart';
import '../controllers/login_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    this.onLoginSuccess,
    this.onDeviceApprovalRequired,
    this.onEmailVerificationRequired,
    this.onMfaRequired,
    super.key,
  });

  final VoidCallback? onLoginSuccess;

  /// Phiên mới đang chờ máy tin cậy / quản trị duyệt (Lõi 2.3).
  final VoidCallback? onDeviceApprovalRequired;

  /// Máy chủ yêu cầu nhập mã xác minh email (Lõi 2.6).
  final ValueChanged<EmailVerificationTicket>? onEmailVerificationRequired;

  /// Tài khoản bật xác thực hai lớp; lượt chờ đã nằm trong
  /// `pendingLoginMfaChallengeProvider`.
  final VoidCallback? onMfaRequired;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    ref.listen<LoginState>(loginControllerProvider, (previous, next) {
      if (next.succeeded && previous?.succeeded != true) {
        ref.invalidate(authAccessTokenProvider);
        final onApproval = widget.onDeviceApprovalRequired;
        if (next.requiresDeviceApproval && onApproval != null) {
          onApproval();
        } else {
          widget.onLoginSuccess?.call();
        }
      }
      final ticket = next.emailVerification;
      if (ticket != null && previous?.emailVerification != ticket) {
        ref.read(loginControllerProvider.notifier).clearEmailVerification();
        widget.onEmailVerificationRequired?.call(ticket);
      }
      final challenge = next.mfaChallenge;
      if (challenge != null && previous?.mfaChallenge != challenge) {
        ref.read(loginControllerProvider.notifier).clearMfaChallenge();
        ref.read(pendingLoginMfaIdentifierProvider.notifier).state =
            next.mfaIdentifier;
        ref.read(pendingLoginMfaChallengeProvider.notifier).state = challenge;
        widget.onMfaRequired?.call();
      }
    });

    final state = ref.watch(loginControllerProvider);
    final controller = ref.read(loginControllerProvider.notifier);
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthBackground()),
          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.035, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _AuthLayout(
                key: ValueKey(
                  state.serverConnected ? state.mode : 'server-selection',
                ),
                state: state,
                controller: controller,
                content: !state.serverConnected
                    ? _ServerContent(state: state, controller: controller)
                    : state.isLogin
                    ? _LoginContent(state: state, controller: controller)
                    : _RegisterContent(
                        state: state,
                        controller: controller,
                        legalLinksConfigured: config.hasPublicLegalUrls,
                        onOpenTerms: !_isHttpsUrl(config.termsUrl)
                            ? null
                            : () => _openLegalDocument(
                                context,
                                config.termsUrl,
                                tr('Điều khoản sử dụng', 'Terms of Use'),
                              ),
                        onOpenPrivacy: !_isHttpsUrl(config.privacyPolicyUrl)
                            ? null
                            : () => _openLegalDocument(
                                context,
                                config.privacyPolicyUrl,
                                tr(
                                  'Chính sách quyền riêng tư',
                                  'Privacy Policy',
                                ),
                              ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLegalDocument(
    BuildContext context,
    String url,
    String label,
  ) async {
    final opened = await ref.read(externalUrlLauncherProvider).open(url);
    if (context.mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Không mở được $label.', 'Could not open $label.')),
        ),
      );
    }
  }
}

class _ServerContent extends StatelessWidget {
  const _ServerContent({required this.state, required this.controller});

  final LoginState state;
  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(child: _BrandLogo(size: 94)),
        const SizedBox(height: 22),
        _AuthTitle(
          center: true,
          title: tr('Kết nối tới máy chủ', 'Connect to a server'),
          subtitle: tr(
            'Nhập domain của tổ chức. Ứng dụng sẽ kiểm tra kết nối trước khi đăng nhập.',
            'Enter your organization domain. The app will check the connection before you sign in.',
          ),
        ),
        if (state.noticeMessage case final notice?) ...[
          _AuthNotice(message: notice),
          const SizedBox(height: 16),
        ] else
          const SizedBox(height: 18),
        KeyedSubtree(
          // Dựng lại ô khi được điền sẵn tên miền (mở từ lời mời).
          key: ValueKey('server-prefill-${state.prefillRevision}'),
          child: _AuthTextField(
            fieldKey: const Key('server_domain_field'),
            initialValue: state.domain,
            label: tr('Địa chỉ máy chủ', 'Server address'),
            hint: 'chat.example.com',
            icon: Icons.dns_outlined,
            enabled: !state.isLoading,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onChanged: controller.updateDomain,
            onSubmitted: (_) => controller.connectServer(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr(
            'Bạn có thể nhập domain hoặc URL HTTPS đầy đủ.',
            'You can enter a domain or a full HTTPS URL.',
          ),
          textAlign: TextAlign.center,
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textSecondary,
          ),
        ),
        if (state.recentServers.isNotEmpty) ...[
          const SizedBox(height: 24),
          _DividerLabel(tr('Máy chủ gần đây', 'Recent servers')),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final server in state.recentServers)
                ActionChip(
                  avatar: const Icon(Icons.dns_rounded, size: 18),
                  label: Text(server.name),
                  onPressed: state.isLoading
                      ? null
                      : () => controller.selectRecentServer(server),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AuthLayout extends StatelessWidget {
  const _AuthLayout({
    required this.state,
    required this.controller,
    required this.content,
    super.key,
  });

  final LoginState state;
  final LoginController controller;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: content,
              ),
            ),
          ),
        ),
        _AuthFooter(state: state, controller: controller),
      ],
    );
  }
}

class _LoginContent extends StatelessWidget {
  const _LoginContent({required this.state, required this.controller});

  final LoginState state;
  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final hasAlternativeSignIn = state.oidcProviders.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          child: _BrandLogo(
            size: 94,
            imageUrl: state.logoUrl,
            name: state.serverName,
          ),
        ),
        const SizedBox(height: 18),
        _AuthTitle(
          center: true,
          title: tr('Chào mừng trở lại', 'Welcome back'),
          subtitle: tr(
            'Đăng nhập vào ${state.serverName ?? 'tổ chức của bạn'}',
            'Sign in to ${state.serverName ?? 'your organization'}',
          ),
        ),
        const SizedBox(height: 12),
        _SelectedServerBar(
          domain: state.domain,
          onChange: state.isLoading ? null : controller.changeServer,
        ),
        if (state.noticeMessage case final notice?) ...[
          const SizedBox(height: 16),
          _AuthNotice(message: notice),
        ],
        const SizedBox(height: 24),
        KeyedSubtree(
          // Dựng lại ô khi điền sẵn email / username đăng nhập gần nhất.
          key: ValueKey('identifier-prefill-${state.prefillRevision}'),
          child: _AuthTextField(
            fieldKey: const Key('login_identifier_field'),
            initialValue: state.identifier,
            label: tr('Email hoặc username', 'Email or username'),
            hint: 'duclamdev',
            icon: Icons.alternate_email_rounded,
            enabled: !state.isLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: controller.updateIdentifier,
          ),
        ),
        const SizedBox(height: 16),
        _AuthTextField(
          fieldKey: const Key('login_password_field'),
          initialValue: state.password,
          label: tr('Mật khẩu', 'Password'),
          hint: tr('Nhập mật khẩu', 'Enter your password'),
          icon: Icons.lock_outline_rounded,
          enabled: !state.isLoading,
          obscureText: !state.showPassword,
          textInputAction: TextInputAction.done,
          trailing: IconButton(
            tooltip: state.showPassword
                ? tr('Ẩn mật khẩu', 'Hide password')
                : tr('Hiện mật khẩu', 'Show password'),
            onPressed: controller.togglePasswordVisibility,
            icon: Icon(
              state.showPassword
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_outlined,
            ),
          ),
          onChanged: controller.updatePassword,
          onSubmitted: (_) => controller.submit(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Checkbox(
              value: state.remember,
              onChanged: state.isLoading
                  ? null
                  : (value) => controller.updateRemember(value ?? true),
              visualDensity: VisualDensity.compact,
            ),
            Flexible(
              child: Text(
                tr('Ghi nhớ đăng nhập', 'Remember me'),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              key: const Key('forgot_password_button'),
              onPressed: state.isLoading
                  ? null
                  : () => _showPasswordRecoveryGuidance(context, state),
              child: Text(tr('Quên mật khẩu?', 'Forgot password?')),
            ),
          ],
        ),
        if (hasAlternativeSignIn) ...[
          const SizedBox(height: 24),
          _DividerLabel(tr('Hoặc tiếp tục với', 'Or continue with')),
          const SizedBox(height: 18),
        ],
        for (final provider in state.oidcProviders) ...[
          if (provider != state.oidcProviders.first) const SizedBox(height: 12),
          _SocialButton(
            label: tr(
              'Đăng nhập bằng ${provider.name}',
              'Sign in with ${provider.name}',
            ),
            icon: const Icon(Icons.corporate_fare_rounded, size: 21),
            loading: state.loadingOidcProviderId == provider.id,
            onPressed: state.isLoading
                ? null
                : () => controller.loginWithOidc(provider),
          ),
        ],
      ],
    );
  }
}

Future<void> _showPasswordRecoveryGuidance(
  BuildContext context,
  LoginState state,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => WebTuiDialog(
      title: tr('Khôi phục mật khẩu', 'Reset password'),
      icon: WebTuiIcons.key,
      message: tr(
        'Tài khoản được quản lý bởi máy chủ ${state.serverName ?? state.domain}. '
            'Hãy liên hệ quản trị viên của tổ chức để đặt lại mật khẩu. Nếu tổ chức '
            'dùng SSO/OIDC, bạn có thể quay lại và chọn nhà cung cấp đăng nhập tương ứng.',
        'Your account is managed by server ${state.serverName ?? state.domain}. '
            'Contact your organization administrator to reset your password. If your '
            'organization uses SSO/OIDC, you can go back and choose the matching sign-in provider.',
      ),
      actions: [
        WebTuiDialogAction(
          label: tr('Đã hiểu', 'Got it'),
          primary: true,
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ],
    ),
  );
}

class _RegisterContent extends StatelessWidget {
  const _RegisterContent({
    required this.state,
    required this.controller,
    required this.legalLinksConfigured,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

  final LoginState state;
  final LoginController controller;
  final bool legalLinksConfigured;
  final VoidCallback? onOpenTerms;
  final VoidCallback? onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    final legalReady = state.legalDocumentsStatus == LegalDocumentsStatus.ready;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _BackButton(onPressed: controller.showLogin),
            const Spacer(),
            _BrandLogo(
              size: 48,
              imageUrl: state.logoUrl,
              name: state.serverName,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _RegisterMark(imageUrl: state.logoUrl, name: state.serverName),
        const SizedBox(height: 16),
        _AuthTitle(
          center: true,
          title: tr('Tạo tài khoản mới', 'Create a new account'),
          subtitle: tr(
            'Tài khoản được tạo tại ${state.serverName ?? 'tổ chức'}',
            'Your account will be created at ${state.serverName ?? 'the organization'}',
          ),
        ),
        const SizedBox(height: 10),
        _SelectedServerBar(
          domain: state.domain,
          onChange: state.isLoading ? null : controller.changeServer,
        ),
        const SizedBox(height: 24),
        _AuthTextField(
          fieldKey: const Key('register_display_name_field'),
          initialValue: state.displayName,
          label: tr('Họ và tên', 'Full name'),
          hint: tr('Nguyễn Văn A', 'Jane Doe'),
          icon: Icons.badge_outlined,
          enabled: !state.isLoading,
          textInputAction: TextInputAction.next,
          onChanged: controller.updateDisplayName,
        ),
        const SizedBox(height: 14),
        _AuthTextField(
          fieldKey: const Key('register_email_field'),
          initialValue: state.email,
          label: 'Email',
          hint: 'you@example.com',
          icon: Icons.alternate_email_rounded,
          enabled: !state.isLoading,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: controller.updateEmail,
        ),
        const SizedBox(height: 14),
        _AuthTextField(
          fieldKey: const Key('register_username_field'),
          initialValue: state.username,
          label: tr('Tên đăng nhập', 'Username'),
          hint: tr(
            'Ví dụ: duclam24 (không cần ký tự đặc biệt)',
            'Example: jane24 (no special characters needed)',
          ),
          icon: Icons.person_outline_rounded,
          enabled: !state.isLoading,
          textInputAction: TextInputAction.next,
          onChanged: controller.updateUsername,
        ),
        const SizedBox(height: 14),
        KeyedSubtree(
          key: ValueKey('invite-prefill-${state.prefillRevision}'),
          child: _AuthTextField(
            fieldKey: const Key('register_invite_token_field'),
            initialValue: state.inviteToken,
            label: tr('Mã lời mời', 'Invite code'),
            hint: tr(
              'Nhập mã nếu server yêu cầu',
              'Enter the code if the server requires it',
            ),
            icon: Icons.key_rounded,
            enabled: !state.isLoading,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            onChanged: controller.updateInviteToken,
          ),
        ),
        const SizedBox(height: 14),
        _AuthTextField(
          fieldKey: const Key('register_password_field'),
          initialValue: state.password,
          label: tr('Mật khẩu', 'Password'),
          hint: tr('Tối thiểu 8 ký tự', 'At least 8 characters'),
          icon: Icons.lock_outline_rounded,
          enabled: !state.isLoading,
          obscureText: !state.showPassword,
          textInputAction: TextInputAction.next,
          trailing: IconButton(
            tooltip: state.showPassword
                ? tr('Ẩn mật khẩu', 'Hide password')
                : tr('Hiện mật khẩu', 'Show password'),
            onPressed: controller.togglePasswordVisibility,
            icon: Icon(
              state.showPassword
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_outlined,
            ),
          ),
          onChanged: controller.updatePassword,
        ),
        const SizedBox(height: 14),
        _AuthTextField(
          fieldKey: const Key('register_confirm_password_field'),
          initialValue: state.confirmPassword,
          label: tr('Xác nhận mật khẩu', 'Confirm password'),
          hint: tr('Nhập lại mật khẩu', 'Re-enter your password'),
          icon: Icons.verified_user_outlined,
          enabled: !state.isLoading,
          obscureText: !state.showConfirmPassword,
          textInputAction: TextInputAction.done,
          trailing: IconButton(
            tooltip: state.showConfirmPassword
                ? tr('Ẩn mật khẩu', 'Hide password')
                : tr('Hiện mật khẩu', 'Show password'),
            onPressed: controller.toggleConfirmPasswordVisibility,
            icon: Icon(
              state.showConfirmPassword
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_outlined,
            ),
          ),
          onChanged: controller.updateConfirmPassword,
          onSubmitted: (_) => controller.submit(),
        ),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: BoxDecoration(
            color:
                legalLinksConfigured &&
                    state.legalDocumentsStatus != LegalDocumentsStatus.error
                ? WebTuiColors.primarySoft
                : _AuthWarn.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  legalLinksConfigured &&
                      state.legalDocumentsStatus != LegalDocumentsStatus.error
                  ? WebTuiColors.border
                  : _AuthWarn.border,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      key: const Key('register_legal_acceptance_checkbox'),
                      value: state.legalAccepted,
                      onChanged:
                          state.isLoading ||
                              !legalLinksConfigured ||
                              !legalReady
                          ? null
                          : (value) => controller.updateLegalAcceptance(
                              value ?? false,
                            ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          tr(
                            'Tôi đã đọc và đồng ý với Điều khoản sử dụng và Chính sách quyền riêng tư.',
                            'I have read and agree to the Terms of Use and Privacy Policy.',
                          ),
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: WebTuiColors.textPrimary,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      key: const Key('register_terms_link'),
                      onPressed: onOpenTerms,
                      icon: const Icon(Icons.gavel_outlined, size: 16),
                      label: Text(tr('Điều khoản sử dụng', 'Terms of Use')),
                    ),
                    TextButton.icon(
                      key: const Key('register_privacy_link'),
                      onPressed: onOpenPrivacy,
                      icon: const Icon(Icons.policy_outlined, size: 16),
                      label: Text(tr('Chính sách riêng tư', 'Privacy Policy')),
                    ),
                  ],
                ),
                if (!legalLinksConfigured)
                  Text(
                    tr(
                      'Bản dựng chưa cấu hình đủ hai URL HTTPS. Đăng ký được tạm khóa để bảo vệ sự đồng ý của người dùng.',
                      'This build does not have both HTTPS URLs configured. Registration is locked to protect user consent.',
                    ),
                    textAlign: TextAlign.center,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: _AuthWarn.icon,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (state.legalDocumentsStatus ==
                        LegalDocumentsStatus.loading ||
                    state.legalDocumentsStatus == LegalDocumentsStatus.idle)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          tr(
                            'Đang xác minh phiên bản điều khoản từ máy chủ...',
                            'Checking the terms version with the server...',
                          ),
                          key: Key('register_legal_versions_loading'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                else if (state.legalDocumentsStatus ==
                    LegalDocumentsStatus.error)
                  Column(
                    children: [
                      Text(
                        state.legalDocumentsError ??
                            tr(
                              'Không tải được phiên bản tài liệu pháp lý.',
                              'Could not load the legal document versions.',
                            ),
                        key: const Key('register_legal_versions_error'),
                        textAlign: TextAlign.center,
                        style: WebTuiTypography.bodySmall.copyWith(
                          color: _AuthWarn.icon,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton.icon(
                        key: const Key('register_legal_versions_retry'),
                        onPressed: state.isLoading
                            ? null
                            : controller.refreshLegalDocumentVersions,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          tr('Thử tải lại điều khoản', 'Reload terms'),
                        ),
                      ),
                    ],
                  )
                else if (state.legalDocumentVersions case final versions?)
                  Text(
                    tr(
                      'Phiên bản Điều khoản: ${versions.termsVersion} · '
                          'Quyền riêng tư: ${versions.privacyVersion}',
                      'Terms version: ${versions.termsVersion} · '
                          'Privacy: ${versions.privacyVersion}',
                    ),
                    key: const Key('register_legal_versions_ready'),
                    textAlign: TextAlign.center,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

bool _isHttpsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

class _AuthFooter extends StatelessWidget {
  const _AuthFooter({required this.state, required this.controller});

  final LoginState state;
  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.surface.withValues(alpha: 0.97),
        border: Border(top: BorderSide(color: WebTuiColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AuthStatus(state: state),
                _SubmitButton(
                  key: Key(
                    !state.serverConnected
                        ? 'server_connect_button'
                        : state.isLogin
                        ? 'login_submit_button'
                        : 'register_submit_button',
                  ),
                  enabled: state.serverConnected
                      ? state.canSubmit
                      : state.canConnectServer,
                  loading: state.isLoading,
                  icon: !state.serverConnected
                      ? Icons.arrow_forward_rounded
                      : state.isLogin
                      ? Icons.login_rounded
                      : Icons.person_add_alt_1_rounded,
                  loadingLabel: !state.serverConnected
                      ? tr('Đang kiểm tra máy chủ...', 'Checking server...')
                      : state.isLogin
                      ? tr('Đang đăng nhập...', 'Signing in...')
                      : tr('Đang đăng ký...', 'Signing up...'),
                  label: !state.serverConnected
                      ? tr('Kết nối', 'Connect')
                      : state.isLogin
                      ? tr('Đăng nhập', 'Sign in')
                      : tr('Tạo tài khoản', 'Create account'),
                  onPressed: state.serverConnected
                      ? controller.submit
                      : controller.connectServer,
                ),
                if (state.serverConnected)
                  _ModeSwitch(
                    leading: state.isLogin
                        ? tr('Chưa có tài khoản?', 'Do not have an account?')
                        : tr('Đã có tài khoản?', 'Already have an account?'),
                    action: state.isLogin
                        ? tr('Đăng ký ngay', 'Sign up now')
                        : tr('Đăng nhập ngay', 'Sign in now'),
                    onPressed: state.isLoading
                        ? null
                        : state.isLogin
                        ? controller.showRegister
                        : controller.showLogin,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AuthBackgroundPainter(
        base: WebTuiColors.background,
        topBand: WebTuiColors.primarySoft,
        bottomBand: WebTuiColors.chipBackground,
        accent: WebTuiColors.accentGreen.withValues(alpha: 0.14),
      ),
    );
  }
}

/// Màu cảnh báo (vàng hổ phách) của màn auth, đổi theo chế độ sáng / tối.
final class _AuthWarn {
  const _AuthWarn._();

  static bool get _dark => WebTuiColors.brightness == Brightness.dark;
  static Color get surface =>
      _dark ? const Color(0xFF3A2E14) : const Color(0xFFFFF4E5);
  static Color get border =>
      _dark ? const Color(0xFF6B5320) : const Color(0xFFF2C97D);
  static Color get icon =>
      _dark ? const Color(0xFFEDB04A) : const Color(0xFF8A5A00);
  static Color get text =>
      _dark ? const Color(0xFFF4D9A0) : const Color(0xFF5C3D00);
}

class _AuthBackgroundPainter extends CustomPainter {
  const _AuthBackgroundPainter({
    required this.base,
    required this.topBand,
    required this.bottomBand,
    required this.accent,
  });

  final Color base;
  final Color topBand;
  final Color bottomBand;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = base;
    canvas.drawRect(Offset.zero & size, paint);

    paint.color = topBand;
    final topPath = Path()
      ..moveTo(size.width * 0.5, 0)
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.02,
        size.width * 0.92,
        size.height * 0.14,
        size.width,
        size.height * 0.3,
      )
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(topPath, paint);

    paint.color = bottomBand;
    final bottomPath = Path()
      ..moveTo(0, size.height * 0.87)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.81,
        size.width * 0.43,
        size.height,
        size.width * 0.65,
        size.height * 0.92,
      )
      ..cubicTo(
        size.width * 0.8,
        size.height * 0.86,
        size.width * 0.9,
        size.height * 0.75,
        size.width,
        size.height * 0.73,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(bottomPath, paint);

    paint.color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-52, size.height * 0.18, 90, 210),
        const Radius.circular(42),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AuthBackgroundPainter old) =>
      old.base != base ||
      old.topBand != topBand ||
      old.bottomBand != bottomBand ||
      old.accent != accent;
}

class _AuthTitle extends StatelessWidget {
  const _AuthTitle({
    required this.title,
    required this.subtitle,
    this.center = false,
  });

  final String title;
  final String subtitle;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: WebTuiTypography.titleLarge.copyWith(
            color: WebTuiColors.textPrimary,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: WebTuiTypography.bodyMedium.copyWith(
            color: WebTuiColors.textSecondary,
            fontSize: 15,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({this.size = 76, this.imageUrl, this.name});

  final double size;
  final String? imageUrl;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: SizedBox.square(dimension: size, child: _logoContent(context)),
    );
  }

  Widget _logoContent(BuildContext context) {
    final url = imageUrl?.trim();
    final organization = name?.trim();
    if (url != null && url.isNotEmpty) {
      return WebTuiBoundedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        maxBytes: webTuiMaxBrandImageBytes,
        allowPublicRequest: true,
        semanticLabel: organization,
        fallback: _organizationFallback(organization),
      );
    }
    if (organization != null && organization.isNotEmpty) {
      return _organizationFallback(organization);
    }
    return Image.asset(
      'assets/branding/logo_webtui.png',
      fit: BoxFit.contain,
      semanticLabel: tr('Ứng dụng chat', 'Chat app'),
    );
  }

  Widget _organizationFallback(String? organization) {
    final label = (organization == null || organization.isEmpty)
        ? 'O'
        : organization
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part.characters.first)
              .join()
              .toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1476FF), Color(0xFF0752C9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.34,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _RegisterMark extends StatelessWidget {
  const _RegisterMark({this.imageUrl, this.name});

  final String? imageUrl;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 150,
            height: 88,
            decoration: BoxDecoration(
              color: WebTuiColors.primarySoft,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: WebTuiColors.border),
            ),
          ),
          _BrandLogo(size: 84, imageUrl: imageUrl, name: name),
          const Positioned(
            right: 86,
            top: 10,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFFFB020),
              size: 20,
            ),
          ),
          Positioned(
            left: 82,
            bottom: 10,
            child: Icon(
              Icons.chat_bubble_rounded,
              color: WebTuiColors.primary,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tr('Quay lại', 'Back'),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: WebTuiColors.surface,
        foregroundColor: WebTuiColors.textPrimary,
        side: BorderSide(color: WebTuiColors.border),
      ),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }
}

class _SelectedServerBar extends StatelessWidget {
  const _SelectedServerBar({required this.domain, required this.onChange});

  final String domain;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.primarySoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebTuiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        child: Row(
          children: [
            Icon(
              Icons.verified_rounded,
              color: WebTuiColors.accentGreen,
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                domain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: onChange,
              child: Text(tr('Đổi máy chủ', 'Change server')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.onChanged,
    this.initialValue,
    this.fieldKey,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.trailing,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;
  final String? initialValue;
  final Key? fieldKey;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? trailing;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: fieldKey,
          initialValue: initialValue,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          style: WebTuiTypography.bodyMedium.copyWith(
            color: WebTuiColors.textPrimary,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(icon, color: WebTuiColors.textSecondary, size: 21),
            suffixIcon: trailing,
            filled: true,
            fillColor: WebTuiColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            border: _fieldBorder(WebTuiColors.border),
            enabledBorder: _fieldBorder(WebTuiColors.border),
            focusedBorder: _fieldBorder(WebTuiColors.primary, width: 1.5),
            disabledBorder: _fieldBorder(WebTuiColors.border),
          ),
        ),
      ],
    );
  }
}

OutlineInputBorder _fieldBorder(Color color, {double width = 1.1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: width),
  );
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    super.key,
    required this.enabled,
    required this.loading,
    required this.icon,
    required this.label,
    required this.loadingLabel,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
  final IconData icon;
  final String label;
  final String loadingLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: WebTuiColors.primary,
          disabledBackgroundColor: WebTuiColors.primary.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          textStyle: WebTuiTypography.bodyMedium.copyWith(
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        icon: loading
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: WebTuiColors.textOnPrimary,
                ),
              )
            : Icon(icon, size: 21),
        label: Text(loading ? loadingLabel : label),
      ),
    );
  }
}

class _AuthStatus extends StatelessWidget {
  const _AuthStatus({required this.state});

  final LoginState state;

  @override
  Widget build(BuildContext context) {
    final message = state.errorMessage;
    if (message == null && !state.succeeded) {
      return const SizedBox.shrink();
    }

    final isError = message != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isError
              ? WebTuiColors.danger.withValues(alpha: 0.12)
              : WebTuiColors.accentGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isError
                ? WebTuiColors.danger.withValues(alpha: 0.24)
                : WebTuiColors.accentGreen.withValues(alpha: 0.24),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: isError ? WebTuiColors.danger : WebTuiColors.accentGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message ??
                      (state.isLogin
                          ? tr(
                              'Đăng nhập thành công.',
                              'Signed in successfully.',
                            )
                          : tr(
                              'Đăng ký thành công.',
                              'Signed up successfully.',
                            )),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lý do vừa phải đăng nhập lại / thông báo lời mời (màu vàng, không phải lỗi).
class _AuthNotice extends StatelessWidget {
  const _AuthNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('login_notice'),
      decoration: BoxDecoration(
        color: _AuthWarn.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _AuthWarn.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: _AuthWarn.icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: _AuthWarn.text,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: WebTuiColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: WebTuiColors.border)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: WebTuiColors.surface,
        foregroundColor: WebTuiColors.textPrimary,
        minimumSize: const Size.fromHeight(54),
        side: BorderSide(color: WebTuiColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: WebTuiTypography.bodyMedium.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : icon,
      label: Text(loading ? tr('Đang mở...', 'Opening...') : label),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.leading,
    required this.action,
    required this.onPressed,
  });

  final String leading;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          leading,
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextButton(
          onPressed: onPressed,
          child: Text(
            action,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
