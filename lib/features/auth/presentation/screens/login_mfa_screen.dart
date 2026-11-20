import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../workspace/presentation/screens/workspace_selector_screen.dart';
import '../../application/use_cases/login_mfa_use_cases.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/login_mfa.dart';
import '../controllers/auth_flow_providers.dart';
import '../controllers/login_mfa_controller.dart';
import '../widgets/login_mfa_method_sheet.dart';
import '../widgets/otp_code_field.dart';
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
  final _focusNode = FocusNode();
  Timer? _clockTimer;

  /// Nhắc tại chỗ khi bấm "Xác minh" lúc mã chưa đủ (không gọi máy chủ).
  String? _formatHint;

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
    _focusNode.dispose();
    super.dispose();
  }

  void _backToLogin() {
    ref.read(pendingLoginMfaChallengeProvider.notifier).state = null;
    ref.read(pendingLoginMfaIdentifierProvider.notifier).state = null;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/login');
    }
  }

  void _onVerified(AuthSession session) {
    ref.read(pendingLoginMfaChallengeProvider.notifier).state = null;
    ref.read(pendingLoginMfaIdentifierProvider.notifier).state = null;
    ref.invalidate(authAccessTokenProvider);
    if (session.isPendingApproval) {
      context.go(deviceApprovalPendingPath);
    } else {
      context.go(workspacePickerAfterLoginPath);
    }
  }

  void _focusCodeLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onCodeChanged(String value) {
    if (_formatHint != null) setState(() => _formatHint = null);
    ref.read(loginMfaControllerProvider.notifier).updateCode(value);
  }

  void _submit() {
    final state = ref.read(loginMfaControllerProvider);
    if (state.isSubmitting) return;
    final method = state.method;
    if (method != null && !loginMfaCodeReady(method, state.code)) {
      setState(() {
        _formatHint = method == LoginMfaMethod.totp
            ? tr('Nhập đủ 6 số.', 'Enter all 6 digits.')
            : tr(
                'Mã khôi phục có dạng XXXXX-XXXXX.',
                'A recovery code looks like XXXXX-XXXXX.',
              );
      });
      _focusNode.requestFocus();
      return;
    }
    unawaited(ref.read(loginMfaControllerProvider.notifier).submit());
  }

  Future<void> _chooseAnotherMethod(LoginMfaChallenge challenge) async {
    final state = ref.read(loginMfaControllerProvider);
    final picked = await showLoginMfaMethodSheet(
      context,
      methods: loginMfaMethodChoices(challenge),
      current: state.method,
    );
    if (!mounted || picked == null) return;
    setState(() => _formatHint = null);
    ref.read(loginMfaControllerProvider.notifier).selectMethod(picked);
    _focusCodeLater();
  }

  Future<void> _openWebLogin(Uri uri) async {
    final opened = await ref
        .read(externalUrlLauncherProvider)
        .open(uri.toString());
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Không mở được trình duyệt. Hãy mở ${uri.host} trên trình duyệt.',
            'Could not open a browser. Open ${uri.host} in your browser.',
          ),
        ),
      ),
    );
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
      final failedNow =
          previous?.isSubmitting == true &&
          !next.isSubmitting &&
          next.errorMessage != null;
      if (failedNow) {
        unawaited(HapticFeedback.mediumImpact());
        if (!next.mustRestart) _focusCodeLater();
      }
    });
    final state = ref.watch(loginMfaControllerProvider);
    final controller = ref.read(loginMfaControllerProvider.notifier);
    final identifier = ref.watch(pendingLoginMfaIdentifierProvider);
    final challenge = state.challenge;
    final secondsLeft = controller.secondsLeft();

    final Widget body;
    if (challenge == null) {
      body = _MfaFrame(
        children: [
          _Title(tr('Lượt xác thực không còn', 'This verification is gone')),
          _Lead(
            tr(
              'Hãy đăng nhập lại để nhận lượt xác thực mới.',
              'Sign in again to start a new verification.',
            ),
          ),
          const SizedBox(height: WebTuiSpacing.xxl),
          _PrimaryButton(
            buttonKey: const Key('login_mfa_restart_button'),
            label: tr('Đăng nhập lại', 'Sign in again'),
            onPressed: _backToLogin,
          ),
        ],
      );
    } else {
      final account = _AccountChip(
        identifier: identifier,
        onChange: state.isSubmitting ? null : _backToLogin,
      );
      if (challenge.onlyPasskey) {
        body = _PasskeyOnlyView(
          account: account,
          webLoginUri: _webLoginUri(ref.watch(activeServerUriProvider)),
          onOpenWeb: _openWebLogin,
          onBack: _backToLogin,
        );
      } else if (secondsLeft <= 0 ||
          (state.mustRestart &&
              state.failureCode == LoginMfaErrorCode.challengeExpired)) {
        body = _RestartView(
          key: const Key('login_mfa_expired'),
          account: account,
          title: tr(
            'Lượt xác minh đã hết hạn',
            'This verification has expired',
          ),
          message: tr(
            'Mỗi lượt xác minh chỉ có 5 phút để bảo vệ tài khoản. Hãy đăng nhập lại.',
            'Each verification lasts only 5 minutes to protect your account. Please sign in again.',
          ),
          onRestart: _backToLogin,
        );
      } else if (state.mustRestart) {
        body = _RestartView(
          account: account,
          title: tr('Cần đăng nhập lại', 'Sign in again'),
          message:
              state.errorMessage ??
              tr(
                'Lượt xác minh đã kết thúc. Hãy đăng nhập lại.',
                'This verification has ended. Please sign in again.',
              ),
          onRestart: _backToLogin,
        );
      } else {
        body = _CodeView(
          account: account,
          state: state,
          challenge: challenge,
          codeController: _codeController,
          focusNode: _focusNode,
          secondsLeft: secondsLeft,
          formatHint: _formatHint,
          onChanged: _onCodeChanged,
          onSubmit: _submit,
          onOtherWays: () => _chooseAnotherMethod(challenge),
        );
      }
    }

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: WebTuiColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          key: const Key('login_mfa_back_button'),
          tooltip: tr('Quay lại', 'Back'),
          onPressed: _backToLogin,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(top: false, child: body),
    );
  }
}

/// Trang đăng nhập web của máy chủ đang dùng (chỉ http/https).
Uri? _webLoginUri(Uri apiBase) {
  if ((apiBase.scheme != 'https' && apiBase.scheme != 'http') ||
      apiBase.host.isEmpty) {
    return null;
  }
  return Uri.parse('${apiBase.origin}/');
}

/// Khung chung: một cột canh trái, cuộn được khi bàn phím mở, dòng trợ giúp
/// (nếu có) nằm sát đáy.
class _MfaFrame extends StatelessWidget {
  const _MfaFrame({
    required this.children,
    this.account,
    this.footer,
    super.key,
  });

  final Widget? account;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(
      WebTuiSpacing.xxl,
      WebTuiSpacing.xs,
      WebTuiSpacing.xxl,
      WebTuiSpacing.xxl,
    );
    // Không dùng SliverFillRemaining: nó đo kích thước nội tại, không chạy được
    // với LayoutBuilder của ô mã. Cột tối thiểu cao bằng màn để đẩy dòng trợ
    // giúp xuống đáy, vẫn cuộn được khi bàn phím mở.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              minHeight: (constraints.maxHeight - padding.vertical).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (account case final account?) ...[
                      account,
                      const SizedBox(height: WebTuiSpacing.xxl),
                    ],
                    ...children,
                  ],
                ),
                if (footer case final footer?)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.xxl),
                    child: footer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeView extends StatelessWidget {
  const _CodeView({
    required this.account,
    required this.state,
    required this.challenge,
    required this.codeController,
    required this.focusNode,
    required this.secondsLeft,
    required this.formatHint,
    required this.onChanged,
    required this.onSubmit,
    required this.onOtherWays,
  });

  final Widget account;
  final LoginMfaState state;
  final LoginMfaChallenge challenge;
  final TextEditingController codeController;
  final FocusNode focusNode;
  final int secondsLeft;
  final String? formatHint;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onOtherWays;

  @override
  Widget build(BuildContext context) {
    final totp = (state.method ?? LoginMfaMethod.totp) == LoginMfaMethod.totp;
    final error = state.errorMessage ?? formatHint;
    final hasOtherWays = loginMfaMethodChoices(challenge).length > 1;

    return _MfaFrame(
      account: account,
      footer: Text(
        tr(
          'Mất cả điện thoại và mã khôi phục? Liên hệ quản trị viên của tổ chức.',
          'Lost both your phone and recovery codes? Contact your organization administrator.',
        ),
        key: const Key('login_mfa_help'),
        style: WebTuiTypography.bodySmall.copyWith(
          color: WebTuiColors.textSecondary,
          height: 1.45,
        ),
      ),
      children: [
        _Title(
          totp
              ? tr('Nhập mã xác thực', 'Enter verification code')
              : tr('Nhập mã khôi phục', 'Enter a recovery code'),
        ),
        _Lead(
          totp
              ? tr(
                  'Mở ứng dụng xác thực (Google Authenticator, Microsoft '
                      'Authenticator…) và nhập mã 6 số.',
                  'Open your authenticator app (Google Authenticator, '
                      'Microsoft Authenticator…) and enter the 6-digit code.',
                )
              : tr(
                  'Mỗi mã khôi phục chỉ dùng được một lần.',
                  'Each recovery code works only once.',
                ),
        ),
        const SizedBox(height: WebTuiSpacing.xxl),
        if (totp)
          OtpCodeField(
            key: const ValueKey('login_mfa_otp'),
            fieldKey: const Key('login_mfa_code_field'),
            controller: codeController,
            focusNode: focusNode,
            enabled: !state.isSubmitting,
            autofocus: true,
            hasError: error != null,
            semanticLabel: tr('Mã xác thực 6 số', '6-digit verification code'),
            onChanged: onChanged,
            onCompleted: (_) => onSubmit(),
          )
        else
          _RecoveryCodeField(
            controller: codeController,
            focusNode: focusNode,
            enabled: !state.isSubmitting,
            hasError: error != null,
            onChanged: onChanged,
            onSubmitted: onSubmit,
          ),
        const SizedBox(height: WebTuiSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: error != null
              ? _StatusLine(
                  key: const Key('login_mfa_error'),
                  icon: WebTuiIcons.warning,
                  text: error,
                  color: Theme.of(context).colorScheme.error,
                  liveRegion: true,
                )
              : shouldShowLoginMfaCountdown(secondsLeft)
              ? _StatusLine(
                  key: const Key('login_mfa_countdown'),
                  text: tr(
                    'Còn ${_formatSeconds(secondsLeft)} để nhập mã',
                    '${_formatSeconds(secondsLeft)} left to enter the code',
                  ),
                  color: WebTuiColors.textSecondary,
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: WebTuiSpacing.lg),
        _PrimaryButton(
          buttonKey: const Key('login_mfa_submit_button'),
          label: tr('Xác minh', 'Verify'),
          loadingLabel: tr('Đang xác minh…', 'Verifying…'),
          loading: state.isSubmitting,
          onPressed: onSubmit,
        ),
        if (hasOtherWays) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          TextButton(
            key: const Key('login_mfa_switch_method'),
            onPressed: state.isSubmitting ? null : onOtherWays,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              textStyle: _buttonTextStyle(context, size: 15),
            ),
            child: Text(tr('Thử cách khác', 'Try another way')),
          ),
        ],
      ],
    );
  }
}

class _RecoveryCodeField extends StatelessWidget {
  const _RecoveryCodeField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(WebTuiRadii.md),
      borderSide: BorderSide(color: color, width: width),
    );
    return TextField(
      key: const Key('login_mfa_code_field'),
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      inputFormatters: const [_RecoveryCodeFormatter()],
      style: WebTuiTypography.titleLarge.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 3,
        color: WebTuiColors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        hintText: 'XXXXX-XXXXX',
        hintStyle: WebTuiTypography.titleLarge.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          letterSpacing: 3,
          color: WebTuiColors.textMuted,
        ),
        filled: true,
        fillColor: WebTuiColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.lg,
          vertical: WebTuiSpacing.lg,
        ),
        border: border(WebTuiColors.border, 1.2),
        enabledBorder: border(hasError ? errorColor : WebTuiColors.border, 1.2),
        focusedBorder: border(hasError ? errorColor : WebTuiColors.primary, 2),
        disabledBorder: border(WebTuiColors.border, 1.2),
      ),
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _RecoveryCodeFormatter extends TextInputFormatter {
  const _RecoveryCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = formatRecoveryCodeInput(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _RestartView extends StatelessWidget {
  const _RestartView({
    required this.account,
    required this.title,
    required this.message,
    required this.onRestart,
    super.key,
  });

  final Widget account;
  final String title;
  final String message;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return _MfaFrame(
      account: account,
      children: [
        _Title(title),
        _Lead(message, key: const Key('login_mfa_restart_message')),
        const SizedBox(height: WebTuiSpacing.xxl),
        _PrimaryButton(
          buttonKey: const Key('login_mfa_restart_button'),
          label: tr('Đăng nhập lại', 'Sign in again'),
          onPressed: onRestart,
        ),
      ],
    );
  }
}

class _PasskeyOnlyView extends StatelessWidget {
  const _PasskeyOnlyView({
    required this.account,
    required this.webLoginUri,
    required this.onOpenWeb,
    required this.onBack,
  });

  final Widget account;
  final Uri? webLoginUri;
  final ValueChanged<Uri> onOpenWeb;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final uri = webLoginUri;
    return _MfaFrame(
      key: const Key('login_mfa_passkey_only'),
      account: account,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Icon(
            WebTuiIcons.fingerprint,
            size: 32,
            color: WebTuiColors.primary,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.lg),
        _Title(tr('Tài khoản này dùng passkey', 'This account uses a passkey')),
        _Lead(
          tr(
            'Ứng dụng điện thoại chưa hỗ trợ passkey. Hãy đăng nhập trên trình '
                'duyệt, rồi bật thêm ứng dụng xác thực trong Cài đặt › Bảo mật '
                'để đăng nhập được trên điện thoại.',
            'The mobile app does not support passkeys yet. Sign in in a browser, '
                'then turn on an authenticator app in Settings › Security to '
                'sign in on your phone.',
          ),
        ),
        const SizedBox(height: WebTuiSpacing.xxl),
        if (uri != null) ...[
          _PrimaryButton(
            buttonKey: const Key('login_mfa_open_web_button'),
            label: tr(
              'Mở trang đăng nhập trên trình duyệt',
              'Open sign-in page in browser',
            ),
            onPressed: () => onOpenWeb(uri),
          ),
          const SizedBox(height: WebTuiSpacing.md),
        ],
        SizedBox(
          height: 52,
          child: OutlinedButton(
            key: const Key('login_mfa_restart_button'),
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              backgroundColor: WebTuiColors.surface,
              textStyle: _buttonTextStyle(context),
            ),
            child: Text(tr('Quay lại', 'Back')),
          ),
        ),
      ],
    );
  }
}

/// Tài khoản đang xác minh (kiểu Google / Microsoft): chữ cái đầu + email /
/// username, nút "Đổi" quay về bước mật khẩu.
class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.identifier, required this.onChange});

  final String? identifier;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final value = identifier?.trim() ?? '';
    final label = value.isEmpty
        ? tr('Tài khoản công ty', 'Organization account')
        : value;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        key: const Key('login_mfa_account'),
        decoration: ShapeDecoration(
          color: WebTuiColors.surface,
          shape: StadiumBorder(side: BorderSide(color: WebTuiColors.border)),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 6, end: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: WebTuiColors.primarySoft,
                  foregroundColor: WebTuiColors.primary,
                  child: value.isEmpty
                      ? Icon(WebTuiIcons.workspace, size: 16)
                      : Text(
                          value.characters.first.toUpperCase(),
                          style: WebTuiTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: WebTuiColors.primary,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                key: const Key('login_mfa_change_account'),
                onPressed: onChange,
                style: TextButton.styleFrom(
                  textStyle: _buttonTextStyle(context, size: 14),
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: WebTuiSpacing.md,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  tr('Đổi', 'Change'),
                  semanticsLabel: tr('Đổi tài khoản', 'Change account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: WebTuiTypography.titleLarge.copyWith(
          color: WebTuiColors.textPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}

class _Lead extends StatelessWidget {
  const _Lead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
      child: Text(
        text,
        style: WebTuiTypography.bodyMedium.copyWith(
          color: WebTuiColors.textSecondary,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.45,
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.text,
    this.icon,
    required this.color,
    this.liveRegion = false,
    super.key,
  });

  final IconData? icon;
  final String text;
  final Color color;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: liveRegion,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon case final icon?) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              style: WebTuiTypography.bodySmall.copyWith(
                color: color,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.buttonKey,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
  });

  final Key buttonKey;
  final String label;
  final String? loadingLabel;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Nền primaryFill + chữ trắng đạt 4,5:1 ở cả nền sáng lẫn tối; lúc đang gửi
    // giữ nguyên màu (không xám đi như nút hỏng).
    return SizedBox(
      height: 52,
      child: FilledButton(
        key: buttonKey,
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: WebTuiColors.primaryFill,
          foregroundColor: WebTuiColors.textOnPrimary,
          disabledBackgroundColor: WebTuiColors.primaryFill,
          disabledForegroundColor: WebTuiColors.textOnPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          textStyle: _buttonTextStyle(context),
        ),
        child: loading
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: WebTuiColors.textOnPrimary,
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.md),
                  Text(loadingLabel ?? label),
                ],
              )
            : Text(label),
      ),
    );
  }
}

/// Chữ nút lấy từ textTheme của theme (đã có phông hệ thống của máy) thay vì
/// kiểu chữ trơn, để cùng phông với chữ còn lại trên màn.
TextStyle _buttonTextStyle(BuildContext context, {double size = 16}) {
  return (Theme.of(context).textTheme.bodyMedium ?? WebTuiTypography.bodyMedium)
      .copyWith(fontSize: size, fontWeight: FontWeight.w700, height: 1.2);
}

String _formatSeconds(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
