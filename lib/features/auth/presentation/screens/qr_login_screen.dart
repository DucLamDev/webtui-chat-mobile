import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../conversations/presentation/screens/qr_scanner_screen.dart';
import '../../domain/entities/qr_login.dart';
import '../auth_formatters.dart';
import '../controllers/qr_login_controller.dart';

/// Cài đặt → "Đăng nhập máy tính bằng QR".
class QrLoginScreen extends ConsumerStatefulWidget {
  const QrLoginScreen({this.openScannerOnStart = true, super.key});

  /// Tắt trong test (không có camera).
  final bool openScannerOnStart;

  @override
  ConsumerState<QrLoginScreen> createState() => _QrLoginScreenState();
}

class _QrLoginScreenState extends ConsumerState<QrLoginScreen> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    if (widget.openScannerOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final phase = ref.read(qrLoginControllerProvider).phase;
      if (mounted && phase == QrLoginPhase.confirm) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    if (!mounted) return;
    ref.read(qrLoginControllerProvider.notifier).reset();
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QrScannerScreen(
          title: 'Quét mã đăng nhập',
          hint: 'Hướng camera vào mã QR trên trang đăng nhập của máy tính.',
        ),
      ),
    );
    if (!mounted || raw == null) return;
    await ref.read(qrLoginControllerProvider.notifier).submitScannedValue(raw);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(qrLoginControllerProvider);
    final controller = ref.read(qrLoginControllerProvider.notifier);
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Quay lại',
          onPressed: () => _close(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Đăng nhập máy tính bằng QR'),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: switch (state.phase) {
          QrLoginPhase.idle => _IdleView(onScan: _scan),
          QrLoginPhase.checking => const WebTuiLoadingState(
            message: 'Đang kiểm tra mã QR...',
          ),
          QrLoginPhase.confirm || QrLoginPhase.deciding => _ConfirmView(
            scan: state.scan!,
            busy: state.phase == QrLoginPhase.deciding,
            onApprove: () => controller.decide(approve: true),
            onReject: () => controller.decide(approve: false),
          ),
          QrLoginPhase.approved => _ResultView(
            icon: Icons.verified_rounded,
            title: 'Đã đồng ý đăng nhập',
            message:
                'Máy tính sẽ tiếp tục đăng nhập. Tổ chức có thể yêu cầu '
                'duyệt thêm thiết bị này.',
            onDone: () => _close(context),
          ),
          QrLoginPhase.rejected => _ResultView(
            icon: Icons.block_rounded,
            title: 'Đã từ chối',
            message: 'Máy tính sẽ không được đăng nhập.',
            onDone: () => _close(context),
          ),
          QrLoginPhase.error => WebTuiErrorState(
            title: 'Không dùng được mã QR này',
            message: state.errorMessage ?? 'Vui lòng thử lại.',
            onRetry: _scan,
          ),
        },
      ),
    );
  }
}

void _close(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.go('/');
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.qr_code_scanner_rounded,
              size: 56,
              color: WebTuiColors.primary,
            ),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              'Mở trang đăng nhập trên máy tính, chọn đăng nhập bằng QR rồi '
              'quét mã bằng điện thoại này.',
              textAlign: TextAlign.center,
              style: WebTuiTypography.bodyMedium,
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            FilledButton.icon(
              key: const Key('qr_login_scan_button'),
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Quét mã'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmView extends StatelessWidget {
  const _ConfirmView({
    required this.scan,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final QrLoginScan scan;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final requester = scan.requester;
    final createdAt = requester.createdAt;
    final expiresAt = scan.expiresAt;
    final remaining = expiresAt?.difference(DateTime.now());
    final expired = remaining != null && remaining.inSeconds <= 0;
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        Text(
          'Đăng nhập trên máy tính này?',
          style: WebTuiTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.xs),
        Text(
          'Chỉ đồng ý nếu chính bạn đang đứng trước máy tính này. Máy tính sẽ '
          'đăng nhập bằng tài khoản của bạn.',
          style: WebTuiTypography.bodyMedium.copyWith(
            color: WebTuiColors.textSecondary,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.md),
        DecoratedBox(
          decoration: BoxDecoration(
            color: WebTuiColors.surface,
            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            border: Border.all(color: WebTuiColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(WebTuiSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(
                  label: 'Thiết bị',
                  value: requester.deviceName ?? 'Không xác định',
                ),
                _Line(
                  label: 'Trình duyệt',
                  value: describeUserAgent(requester.userAgent),
                ),
                _Line(
                  label: 'Địa chỉ IP',
                  value: requester.ipAddress ?? 'Không xác định',
                ),
                if (createdAt != null)
                  _Line(
                    label: 'Thời điểm',
                    value: formatAuthDateTime(createdAt),
                  ),
              ],
            ),
          ),
        ),
        if (remaining != null) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          Text(
            expired
                ? 'Mã đã hết hạn. Hãy tải mã mới trên máy tính rồi quét lại.'
                : 'Mã hết hạn sau ${formatCountdown(remaining)}',
            key: const Key('qr_login_countdown'),
            style: WebTuiTypography.bodySmall.copyWith(
              color: expired ? WebTuiColors.danger : WebTuiColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: WebTuiSpacing.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('qr_login_reject_button'),
                onPressed: busy || expired ? null : onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: WebTuiColors.danger,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Từ chối'),
              ),
            ),
            const SizedBox(width: WebTuiSpacing.md),
            Expanded(
              child: FilledButton(
                key: const Key('qr_login_approve_button'),
                onPressed: busy || expired ? null : onApprove,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Đồng ý'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: WebTuiTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.icon,
    required this.title,
    required this.message,
    required this.onDone,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: WebTuiColors.primary),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: WebTuiTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: WebTuiSpacing.lg),
            FilledButton(onPressed: onDone, child: const Text('Xong')),
          ],
        ),
      ),
    );
  }
}
