import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../controllers/login_controller.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({this.onLoginSuccess, super.key});

  final VoidCallback? onLoginSuccess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<LoginState>(loginControllerProvider, (previous, next) {
      if (next.succeeded && previous?.succeeded != true) {
        onLoginSuccess?.call();
      }
    });

    final state = ref.watch(loginControllerProvider);
    final controller = ref.read(loginControllerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
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
                key: ValueKey(state.mode),
                state: state,
                controller: controller,
                content: state.isLogin
                    ? _LoginContent(state: state, controller: controller)
                    : _RegisterContent(state: state, controller: controller),
              ),
            ),
          ),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(child: _BrandLogo(size: 94)),
        const SizedBox(height: 18),
        const _AuthTitle(
          center: true,
          title: 'Chào mừng trở lại',
          subtitle: 'Đăng nhập vào server chat của công ty bạn',
        ),
        const SizedBox(height: 30),
        _AuthTextField(
          fieldKey: const Key('login_domain_field'),
          initialValue: state.domain,
          label: 'Địa chỉ server',
          hint: 'chat.example.com',
          icon: Icons.dns_outlined,
          enabled: !state.isLoading,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          onChanged: controller.updateDomain,
        ),
        const SizedBox(height: 16),
        _AuthTextField(
          fieldKey: const Key('login_identifier_field'),
          initialValue: state.identifier,
          label: 'Email hoặc username',
          hint: 'duclamdev',
          icon: Icons.alternate_email_rounded,
          enabled: !state.isLoading,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          onChanged: controller.updateIdentifier,
        ),
        const SizedBox(height: 16),
        _AuthTextField(
          fieldKey: const Key('login_password_field'),
          initialValue: state.password,
          label: 'Mật khẩu',
          hint: 'Nhập mật khẩu',
          icon: Icons.lock_outline_rounded,
          enabled: !state.isLoading,
          obscureText: !state.showPassword,
          textInputAction: TextInputAction.done,
          trailing: IconButton(
            tooltip: state.showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
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
                'Ghi nhớ đăng nhập',
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: state.isLoading ? null : () {},
              child: const Text('Quên mật khẩu?'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _DividerLabel('Hoặc tiếp tục với'),
        const SizedBox(height: 18),
        _SocialButton(
          label: 'Đăng nhập bằng Google',
          icon: const _GoogleLogo(),
          loading: state.isGoogleLoading,
          onPressed: state.isLoading ? null : controller.loginWithGoogle,
        ),
      ],
    );
  }
}

class _RegisterContent extends StatelessWidget {
  const _RegisterContent({required this.state, required this.controller});

  final LoginState state;
  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _BackButton(onPressed: controller.showLogin),
            const Spacer(),
            const _BrandLogo(size: 48),
          ],
        ),
        const SizedBox(height: 14),
        const _RegisterMark(),
        const SizedBox(height: 16),
        const _AuthTitle(
          center: true,
          title: 'Tạo tài khoản mới',
          subtitle: 'Tài khoản được tạo trên server đã chọn',
        ),
        const SizedBox(height: 24),
        _AuthTextField(
          fieldKey: const Key('register_display_name_field'),
          initialValue: state.displayName,
          label: 'Họ và tên',
          hint: 'Nguyễn Văn A',
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
          label: 'Username',
          hint: 'yourusername',
          icon: Icons.person_outline_rounded,
          enabled: !state.isLoading,
          textInputAction: TextInputAction.next,
          onChanged: controller.updateUsername,
        ),
        const SizedBox(height: 14),
        _AuthTextField(
          fieldKey: const Key('register_domain_field'),
          initialValue: state.domain,
          label: 'Địa chỉ server',
          hint: 'chat.example.com',
          icon: Icons.language_rounded,
          enabled: !state.isLoading,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          onChanged: controller.updateDomain,
        ),
        const SizedBox(height: 14),
        _AuthTextField(
          fieldKey: const Key('register_password_field'),
          initialValue: state.password,
          label: 'Mật khẩu',
          hint: 'Tối thiểu 8 ký tự',
          icon: Icons.lock_outline_rounded,
          enabled: !state.isLoading,
          obscureText: !state.showPassword,
          textInputAction: TextInputAction.next,
          trailing: IconButton(
            tooltip: state.showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
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
          label: 'Xác nhận mật khẩu',
          hint: 'Nhập lại mật khẩu',
          icon: Icons.verified_user_outlined,
          enabled: !state.isLoading,
          obscureText: !state.showConfirmPassword,
          textInputAction: TextInputAction.done,
          trailing: IconButton(
            tooltip: state.showConfirmPassword
                ? 'Ẩn mật khẩu'
                : 'Hiện mật khẩu',
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
        Text.rich(
          TextSpan(
            text: 'Khi đăng ký, bạn đồng ý với ',
            children: [
              TextSpan(text: 'Điều khoản sử dụng', style: _linkStyle),
              const TextSpan(text: ' và '),
              TextSpan(text: 'Chính sách bảo mật', style: _linkStyle),
              const TextSpan(text: ' của WebTui.'),
            ],
          ),
          textAlign: TextAlign.center,
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textMuted,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _AuthFooter extends StatelessWidget {
  const _AuthFooter({required this.state, required this.controller});

  final LoginState state;
  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        border: const Border(top: BorderSide(color: Color(0xFFE3EBF5))),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF23466F).withValues(alpha: 0.08),
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
                    state.isLogin
                        ? 'login_submit_button'
                        : 'register_submit_button',
                  ),
                  enabled: state.canSubmit,
                  loading: state.isLoading && !state.isGoogleLoading,
                  icon: state.isLogin
                      ? Icons.login_rounded
                      : Icons.person_add_alt_1_rounded,
                  loadingLabel: state.isLogin
                      ? 'Đang đăng nhập...'
                      : 'Đang đăng ký...',
                  label: state.isLogin ? 'Đăng nhập' : 'Tạo tài khoản',
                  onPressed: controller.submit,
                ),
                _ModeSwitch(
                  leading: state.isLogin
                      ? 'Chưa có tài khoản?'
                      : 'Đã có tài khoản?',
                  action: state.isLogin ? 'Đăng ký ngay' : 'Đăng nhập ngay',
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
    return CustomPaint(painter: _AuthBackgroundPainter());
  }
}

class _AuthBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = const Color(0xFFF6FAFF);
    canvas.drawRect(Offset.zero & size, paint);

    paint.color = const Color(0xFFE5F1FF);
    final topBand = Path()
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
    canvas.drawPath(topBand, paint);

    paint.color = const Color(0xFFDCEEFF);
    final bottomBand = Path()
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
    canvas.drawPath(bottomBand, paint);

    paint.color = const Color(0xFFE7F7F1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-52, size.height * 0.18, 90, 210),
        const Radius.circular(42),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
            color: const Color(0xFF15213A),
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
            color: WebTuiColors.textMuted,
            fontSize: 15,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({this.size = 76});

  final double size;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          'assets/branding/logo_webtui.png',
          fit: BoxFit.contain,
          semanticLabel: 'WebTui',
        ),
      ),
    );
  }
}

class _RegisterMark extends StatelessWidget {
  const _RegisterMark();

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
              color: const Color(0xFFDCEBFF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFC4DCFF)),
            ),
          ),
          const _BrandLogo(size: 84),
          const Positioned(
            right: 86,
            top: 10,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFFFB020),
              size: 20,
            ),
          ),
          const Positioned(
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
      tooltip: 'Quay lại',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF15213A),
        side: const BorderSide(color: Color(0xFFE1E9F3)),
      ),
      icon: const Icon(Icons.arrow_back_rounded),
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
            color: const Color(0xFF263247),
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
              color: const Color(0xFF9AA5B7),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(icon, color: const Color(0xFF6C788B), size: 21),
            suffixIcon: trailing,
            filled: true,
            fillColor: Colors.white,
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
          disabledBackgroundColor: const Color(0xFFAECFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          textStyle: WebTuiTypography.bodyMedium.copyWith(
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        icon: loading
            ? const SizedBox.square(
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
          color: isError ? const Color(0xFFFFF1F1) : const Color(0xFFEAF8F1),
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
                          ? 'Đăng nhập thành công.'
                          : 'Đăng ký thành công.'),
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

class _DividerLabel extends StatelessWidget {
  const _DividerLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: WebTuiColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
            style: WebTuiTypography.bodySmall.copyWith(
              color: const Color(0xFF8C98AA),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Expanded(child: Divider(color: WebTuiColors.border)),
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
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1D2433),
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: WebTuiColors.border),
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
      label: Text(loading ? 'Đang mở Google...' : label),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.18;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.2 * math.pi, 0.72 * math.pi, false, paint);
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.52 * math.pi, 0.5 * math.pi, false, paint);
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 1.02 * math.pi, 0.42 * math.pi, false, paint);
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 1.44 * math.pi, 0.36 * math.pi, false, paint);

    paint
      ..color = const Color(0xFF4285F4)
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(size.width * 0.53, size.height * 0.52),
      Offset(size.width * 0.93, size.height * 0.52),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
            color: WebTuiColors.textMuted,
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

final _linkStyle = WebTuiTypography.bodySmall.copyWith(
  color: WebTuiColors.primary,
  fontWeight: FontWeight.w800,
);
