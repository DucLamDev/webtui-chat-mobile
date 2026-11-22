import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/privacy/background_privacy.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/ide_device_security.dart';
import '../../domain/ide_server_access.dart';
import 'ide_wb.dart';

/// Bọc mọi màn `/ide*`:
///  - máy chủ chat báo không được dùng IDE: hiện màn khoá, không dựng màn con
///    (không hiện dữ liệu, không nối IDE);
///  - hỏi vân tay / khoá màn hình, nhớ 5 phút sau khi app ra nền;
///  - chặn chụp màn hình (Android) và che khi quay / chiếu màn hình (iOS) từ
///    lúc vào tới lúc rời; màn con đẩy lên trên vẫn được che;
///  - app quay lại thì ẩn nội dung tới khi kiểm xong thời gian ở nền; ở nền
///    quá lâu thì nội dung IDE bị xoá khỏi bộ nhớ ([ideMemoryEpochProvider]).
class IdeAccessGate extends ConsumerStatefulWidget {
  const IdeAccessGate({
    required this.child,
    this.privacy = const BackgroundPrivacyController(),
    super.key,
  });

  final Widget child;
  final BackgroundPrivacyController privacy;

  @override
  ConsumerState<IdeAccessGate> createState() => _IdeAccessGateState();
}

enum _Gate { asking, open, noLock, failed }

class _IdeAccessGateState extends ConsumerState<IdeAccessGate>
    with WidgetsBindingObserver {
  _Gate _gate = _Gate.asking;

  /// Đang kiểm thời gian ở nền: nội dung đã mở được giữ nhưng không hiện.
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.privacy.acquireSecureScreen());
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.privacy.releaseSecureScreen());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(ideAccessControllerProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      final check = controller.onForeground();
      if (_gate == _Gate.open && controller.resuming) {
        setState(() => _checking = true);
      }
      _checkResume(check);
    }
  }

  Future<void> _checkResume(Future<bool> stillUnlocked) async {
    final ok = await stillUnlocked;
    if (!mounted) return;
    if (_checking) setState(() => _checking = false);
    if (ok || _gate != _Gate.open) return;
    setState(() => _gate = _Gate.asking);
    await _ask();
  }

  Future<void> _ask() async {
    // Máy chủ chat báo không được dùng IDE thì không hỏi vân tay.
    await ref.read(ideServerStatusProvider.future);
    if (!mounted || ref.read(ideAccessLockProvider) != null) return;
    final result = await ref
        .read(ideAccessControllerProvider)
        .ensureUnlocked(
          tr(
            'Xác nhận để mở IDE trên điện thoại',
            'Confirm to open the IDE on this phone',
          ),
        );
    if (!mounted) return;
    switch (result) {
      case DeviceOwnerAuthResult.ok:
        setState(() => _gate = _Gate.open);
      case DeviceOwnerAuthResult.cancelled:
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      case DeviceOwnerAuthResult.notEnrolled:
        setState(() => _gate = _Gate.noLock);
      case DeviceOwnerAuthResult.unavailable:
        setState(() => _gate = _Gate.failed);
    }
  }

  void _retryAccess() {
    ref.read(ideAccessDeniedReasonProvider.notifier).state = null;
    ref.invalidate(ideServerStatusProvider);
    setState(() => _gate = _Gate.asking);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ask();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(ideAccessLockProvider);
    final epoch = ref.watch(ideMemoryEpochProvider);
    if (lock != null) {
      // Đang mở IDE mà máy chủ vừa chặn: dừng kết nối, không chờ hết hạn.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.exists(ideConnectionProvider)) {
          unawaited(ref.read(ideConnectionProvider).stop());
        }
      });
      return IdeWbTheme(
        child: Scaffold(
          appBar: AppBar(),
          body: _AccessLocked(
            key: const Key('ide_access_locked'),
            message: ideAccessDeniedText(lock),
            onRetry: _retryAccess,
          ),
        ),
      );
    }
    // Mọi màn IDE (và bảng trượt / hộp thoại mở từ đó) theo chủ đề IDE web.
    return IdeWbTheme(
      child: switch (_gate) {
        // Khoá theo lần xoá bộ nhớ: nội dung cũ không sống sang lần mở sau.
        _Gate.open => Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: _checking,
              child: TickerMode(
                enabled: !_checking,
                child: KeyedSubtree(
                  key: ValueKey<int>(epoch),
                  child: widget.child,
                ),
              ),
            ),
            if (_checking) const ColoredBox(color: Colors.black),
          ],
        ),
        _Gate.asking => Scaffold(
          body: WebTuiLoadingState(
            message: tr('Đang xác nhận...', 'Confirming...'),
          ),
        ),
        _Gate.noLock => Scaffold(
          appBar: AppBar(),
          body: WebTuiEmptyState(
            title: tr('Chưa đặt khoá màn hình', 'No screen lock'),
            message: tr(
              'Hãy đặt khoá màn hình cho điện thoại để dùng IDE',
              'Set a screen lock on this phone to use the IDE',
            ),
            icon: Icons.lock_outline_rounded,
          ),
        ),
        _Gate.failed => Scaffold(
          appBar: AppBar(),
          body: WebTuiErrorState(
            title: tr('Không xác nhận được', 'Could not confirm'),
            message: tr(
              'Thiết bị chưa sẵn sàng xác thực. Thử lại sau.',
              'The device is not ready to authenticate. Try again later.',
            ),
            onRetry: () {
              setState(() => _gate = _Gate.asking);
              _ask();
            },
          ),
        ),
      },
    );
  }
}

/// Màn khoá khi máy chủ chat chưa cho tài khoản dùng IDE.
class _AccessLocked extends StatelessWidget {
  const _AccessLocked({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WebTuiSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 40, color: IdeWb.text2),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              tr('Chưa dùng được IDE', 'The IDE is not available'),
              textAlign: TextAlign.center,
              style: IdeType.titleMedium,
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: IdeType.bodyMedium.copyWith(color: IdeWb.text),
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(tr('Thử lại', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }
}
