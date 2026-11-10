import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../workspace/presentation/screens/workspace_selector_screen.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/email_verification.dart';
import '../controllers/email_verification_controller.dart';
import 'device_approval_pending_screen.dart';

const emailVerificationPath = '/verify-email';

String emailVerificationLocation(EmailVerificationTicket ticket) {
  return Uri(
    path: emailVerificationPath,
    queryParameters: ticket.toQuery(),
  ).toString();
}

/// Nhập mã 6 số gửi qua email (Lõi 2.6).
class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({required this.ticket, super.key});

  /// null khi đường dẫn thiếu / sai `vid`.
  final EmailVerificationTicket? ticket;

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
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

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    if (ticket == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Xác minh email')),
        body: SafeArea(
          child: WebTuiErrorState(
            title: 'Không mở được phiên xác minh',
            message: 'Hãy đăng ký hoặc đăng nhập lại để nhận mã mới.',
            onRetry: () => context.go('/login'),
          ),
        ),
      );
    }
    final provider = emailVerificationControllerProvider(ticket);
    ref.listen<EmailVerificationState>(provider, (previous, next) {
      final session = next.verifiedSession;
      if (session != null && previous?.verifiedSession == null) {
        _onVerified(session);
      }
      if (next.code.isEmpty && _codeController.text.isNotEmpty) {
        _codeController.clear();
      }
    });
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final secondsLeft = controller.resendSecondsLeft();

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Quay lại',
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              context.go('/login');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Xác minh email'),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              size: 56,
              color: WebTuiColors.primary,
            ),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              'Nhập mã 6 số đã gửi tới '
              '${state.ticket.emailHint ?? 'email của bạn'}',
              textAlign: TextAlign.center,
              style: WebTuiTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              'Mã có hiệu lực 15 phút. Kiểm tra cả thư mục spam nếu chưa thấy.',
              textAlign: TextAlign.center,
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            TextField(
              key: const Key('email_code_field'),
              controller: _codeController,
              enabled: !state.isVerifying && !state.mustResend,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: WebTuiTypography.titleMedium.copyWith(
                letterSpacing: 12,
                fontWeight: FontWeight.w800,
              ),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••••',
                border: OutlineInputBorder(),
              ),
              onChanged: controller.updateCode,
              onSubmitted: (_) => controller.submit(),
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: WebTuiSpacing.sm),
              Text(
                state.errorMessage!,
                key: const Key('email_code_error'),
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (state.infoMessage != null) ...[
              const SizedBox(height: WebTuiSpacing.sm),
              Text(
                state.infoMessage!,
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.accentGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: WebTuiSpacing.lg),
            FilledButton(
              key: const Key('email_code_submit_button'),
              onPressed: state.canSubmit ? controller.submit : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: state.isVerifying
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Text('Xác minh'),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            TextButton(
              key: const Key('email_code_resend_button'),
              onPressed: state.isResending || secondsLeft > 0
                  ? null
                  : controller.resend,
              child: Text(
                secondsLeft > 0
                    ? 'Gửi lại mã sau ${secondsLeft}s'
                    : state.isResending
                    ? 'Đang gửi lại mã...'
                    : 'Gửi lại mã',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onVerified(AuthSession session) {
    ref.invalidate(authAccessTokenProvider);
    if (session.isPendingApproval) {
      context.go(deviceApprovalPendingPath);
    } else {
      context.go(workspacePickerAfterLoginPath);
    }
  }
}
