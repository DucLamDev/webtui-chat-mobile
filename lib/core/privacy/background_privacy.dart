import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/tokens/webtui_colors.dart';
import '../../design_system/tokens/webtui_spacing.dart';
import '../../design_system/tokens/webtui_typography.dart';

final class BackgroundPrivacyController {
  const BackgroundPrivacyController();

  static const _channel = MethodChannel('webtui/privacy');

  Future<void> setSecureScreen(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecureScreen', enabled);
    } on MissingPluginException {
      // Desktop/web test runners do not provide the mobile privacy channel.
    }
  }
}

class PrivacyGuard extends StatefulWidget {
  const PrivacyGuard({
    required this.child,
    this.controller = const BackgroundPrivacyController(),
    super.key,
  });

  final Widget child;
  final BackgroundPrivacyController controller;

  @override
  State<PrivacyGuard> createState() => _PrivacyGuardState();
}

class _PrivacyGuardState extends State<PrivacyGuard>
    with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.setSecureScreen(true);
  }

  @override
  void dispose() {
    widget.controller.setSecureScreen(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shouldObscure =
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;
    if (_obscured != shouldObscure && mounted) {
      setState(() => _obscured = shouldObscure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: !_obscured,
          child: AnimatedOpacity(
            opacity: _obscured ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: const _PrivacyCover(),
          ),
        ),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTuiColors.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: WebTuiColors.primary,
              size: 32,
            ),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              'WebTui đang bảo vệ nội dung',
              style: WebTuiTypography.bodyMedium.copyWith(
                color: WebTuiColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
