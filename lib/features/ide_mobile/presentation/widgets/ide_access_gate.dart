import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/ide_device_security.dart';

/// Hỏi vân tay / khoá màn hình khi vào `/ide*`; nhớ 5 phút sau khi app ra nền.
class IdeAccessGate extends ConsumerStatefulWidget {
  const IdeAccessGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<IdeAccessGate> createState() => _IdeAccessGateState();
}

enum _Gate { asking, open, noLock, failed }

class _IdeAccessGateState extends ConsumerState<IdeAccessGate>
    with WidgetsBindingObserver {
  _Gate _gate = _Gate.asking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(ideAccessControllerProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      _checkResume(controller.onForeground());
    }
  }

  Future<void> _checkResume(Future<bool> stillUnlocked) async {
    final ok = await stillUnlocked;
    if (!mounted || ok || _gate != _Gate.open) return;
    setState(() => _gate = _Gate.asking);
    await _ask();
  }

  Future<void> _ask() async {
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

  @override
  Widget build(BuildContext context) {
    return switch (_gate) {
      _Gate.open => widget.child,
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
    };
  }
}
