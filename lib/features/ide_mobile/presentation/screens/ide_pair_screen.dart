import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../conversations/presentation/screens/qr_scanner_screen.dart';
import '../../application/ide_pairing_service.dart';
import '../../domain/ide_pair_code.dart';

/// Câu lỗi dễ hiểu cho từng kết quả gắn máy.
String idePairOutcomeText(IdePairOutcome outcome) => switch (outcome) {
  IdePairOutcome.ok => tr('Đã gắn máy.', 'Paired.'),
  IdePairOutcome.rejected => tr(
    'IDE đã từ chối gắn máy này.',
    'The IDE rejected this phone.',
  ),
  IdePairOutcome.expired => tr(
    'Mã QR đã hết hạn. Hãy tạo mã mới trên máy tính.',
    'The QR code expired. Create a new one on your computer.',
  ),
  IdePairOutcome.invalid => tr(
    'Mã QR không đúng hoặc đã dùng. Hãy tạo mã mới trên máy tính.',
    'The QR code is wrong or already used. Create a new one.',
  ),
  IdePairOutcome.offline => tr(
    'IDE trên máy tính đang tắt hoặc mất mạng.',
    'The IDE on your computer is off or offline.',
  ),
  IdePairOutcome.rateLimited => tr(
    'Thử quá nhiều lần. Hãy chờ một lúc rồi quét lại.',
    'Too many attempts. Wait a moment and scan again.',
  ),
  IdePairOutcome.busy => tr(
    'Máy chủ đang bận, thử lại sau.',
    'The server is busy. Try again later.',
  ),
  IdePairOutcome.timedOut => tr(
    'Hết thời gian chờ. Hãy bấm Xác nhận trên IDE ngay sau khi quét.',
    'Timed out. Press Confirm in the IDE right after scanning.',
  ),
  IdePairOutcome.noLockScreen => tr(
    'Hãy đặt khoá màn hình cho điện thoại để dùng IDE',
    'Set a screen lock on this phone to use the IDE',
  ),
  IdePairOutcome.biometricRequired => tr(
    'Máy này cần đăng ký vân tay hoặc khuôn mặt để dùng IDE.',
    'Enrol a fingerprint or face on this phone to use the IDE.',
  ),
  IdePairOutcome.unsupported => tr(
    'IDE cần Android 9 trở lên.',
    'The IDE needs Android 9 or newer.',
  ),
  IdePairOutcome.failed => tr(
    'Không gắn được máy. Hãy thử lại.',
    'Could not pair. Please try again.',
  ),
};

enum _Step { scan, wait, done, error }

/// `/ide/pair`: 1 quét mã, 2 chờ bấm Xác nhận trên IDE, 3 xong.
class IdePairScreen extends ConsumerStatefulWidget {
  const IdePairScreen({this.openScannerOnStart = true, super.key});

  /// Tắt trong test (không có camera).
  final bool openScannerOnStart;

  @override
  ConsumerState<IdePairScreen> createState() => _IdePairScreenState();
}

class _IdePairScreenState extends ConsumerState<IdePairScreen> {
  final _name = TextEditingController(text: tr('Điện thoại', 'Phone'));
  _Step _step = _Step.scan;
  bool _waiting = false;
  bool _noPush = false;
  String _error = '';
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    if (widget.openScannerOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _name.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          title: tr('Quét mã gắn IDE', 'Scan IDE pairing code'),
          hint: tr(
            'Hướng camera vào mã QR trong IDE trên máy tính.',
            'Point the camera at the QR code in the desktop IDE.',
          ),
        ),
      ),
    );
    if (!mounted || raw == null) return;
    final code = IdePairCode.tryParse(raw);
    if (code == null) {
      setState(() {
        _step = _Step.error;
        _error = tr(
          'Đây không phải mã gắn IDE. Hãy quét mã trong IDE trên máy tính.',
          'This is not an IDE pairing code. Scan the code in the desktop IDE.',
        );
      });
      return;
    }
    setState(() {
      _step = _Step.wait;
      _waiting = false;
      _noPush = false;
    });
    final outcome = await ref
        .read(idePairingServiceProvider)
        .pair(
          code: code,
          deviceName: _name.text,
          onWaiting: () {
            if (mounted) setState(() => _waiting = true);
          },
          isCancelled: () => _cancelled,
        );
    if (!mounted) return;
    if (outcome == IdePairOutcome.ok) {
      ref.invalidate(ideCredentialsProvider);
      setState(() {
        _noPush = ref.read(idePairingServiceProvider).lastPushLinked == false;
        _step = _Step.done;
      });
    } else {
      setState(() {
        _step = _Step.error;
        _error = idePairOutcomeText(outcome);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_step) {
      _Step.scan => _centered(
        icon: Icons.qr_code_scanner_rounded,
        title: tr('Bước 1: quét mã QR', 'Step 1: scan the QR code'),
        message: tr(
          'Mở IDE trên máy tính, chọn gắn điện thoại, rồi quét mã.',
          'Open the IDE on your computer, choose pair phone, then scan.',
        ),
        extra: [
          TextField(
            controller: _name,
            maxLength: IdePairingService.maxNameLength,
            decoration: InputDecoration(labelText: tr('Tên máy', 'Phone name')),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          FilledButton(
            onPressed: _scan,
            child: Text(tr('Quét mã', 'Scan code')),
          ),
        ],
      ),
      _Step.wait => WebTuiLoadingState(
        message: _waiting
            ? tr(
                'Bước 2: mở IDE trên máy tính và bấm Xác nhận.',
                'Step 2: open the desktop IDE and press Confirm.',
              )
            : tr('Đang gửi yêu cầu...', 'Sending request...'),
      ),
      _Step.done => _centered(
        icon: Icons.verified_rounded,
        title: tr('Bước 3: đã gắn máy', 'Step 3: paired'),
        message: _noPush
            ? '${tr('Điện thoại đã được gắn với IDE.', 'This phone is now paired with the IDE.')}\n'
                  '${tr('Chưa bật thông báo IDE trên máy này — bật thông báo rồi gắn lại.', 'IDE notifications are not enabled on this phone. Turn notifications on, then pair again.')}'
            : tr(
                'Điện thoại đã được gắn với IDE.',
                'This phone is now paired with the IDE.',
              ),
        extra: [
          FilledButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/ide'),
            child: Text(tr('Xong', 'Done')),
          ),
        ],
      ),
      _Step.error => WebTuiErrorState(
        title: tr('Chưa gắn được', 'Could not pair'),
        message: _error,
        onRetry: () => setState(() => _step = _Step.scan),
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Gắn máy với IDE', 'Pair with IDE')),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _centered({
    required IconData icon,
    required String title,
    required String message,
    required List<Widget> extra,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WebTuiSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: WebTuiColors.textMuted),
            const SizedBox(height: WebTuiSpacing.md),
            Text(title, style: WebTuiTypography.titleMedium),
            const SizedBox(height: WebTuiSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: WebTuiTypography.bodyMedium.copyWith(
                color: WebTuiColors.textSecondary,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            ...extra,
          ],
        ),
      ),
    );
  }
}
