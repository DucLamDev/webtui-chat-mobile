import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/security/active_call_tracker.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../l10n/app_strings.dart';
import '../../../auth/presentation/widgets/app_lock_gate.dart';
import '../../application/ide_web_access.dart';
import '../../application/ide_web_mic_guard.dart';
import '../../application/ide_web_prompter.dart';
import '../controllers/ide_web_controller.dart';
import '../widgets/ide_web_mic_chip.dart';
import '../widgets/ide_web_prompt_dialog.dart';
import '../widgets/ide_web_state_view.dart';

/// Màn VPSTTT IDE: các trạng thái mở và trang IDE nhúng. Màn tự kiểm lại quyền
/// (không tin việc ô có hiện hay không).
class IdeWebScreen extends ConsumerStatefulWidget {
  const IdeWebScreen({super.key});

  @override
  ConsumerState<IdeWebScreen> createState() => _IdeWebScreenState();
}

class _IdeWebScreenState extends ConsumerState<IdeWebScreen>
    with WidgetsBindingObserver
    implements IdeWebPrompter {
  late final IdeWebController _controller;
  bool _resumed = true;
  bool _locked = false;
  bool _routeCurrent = true;
  bool _popping = false;

  /// Hộp xác nhận đang mở (tối đa một).
  DialogRoute<bool>? _dialog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = !_isBackground(lifecycle);
    _controller = ref.read(ideWebControllerProvider.notifier)
      ..attachPrompter(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pushStatus();
      unawaited(_controller.begin());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locked = AppLockScope.isObscured(context);
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _scheduleStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.detachPrompter(this);
    super.dispose();
  }

  // `inactive` một mình (hộp sinh trắc, thanh thông báo) không phải xuống nền.
  static bool _isBackground(AppLifecycleState? state) =>
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isBackground(state)) {
      _resumed = false;
    } else if (state == AppLifecycleState.resumed) {
      _resumed = true;
    } else {
      return;
    }
    _pushStatus();
  }

  void _scheduleStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pushStatus();
    });
  }

  void _pushStatus() {
    _controller.updateStatus(
      IdeWebScreenStatus(
        // Hộp xác nhận của chính màn này không tính là rời màn.
        visible: _routeCurrent || _dialog != null,
        resumed: _resumed,
        locked: _locked,
        inCall: ref.read(activeCallTrackerProvider).isNotEmpty,
      ),
    );
  }

  @override
  Future<bool> confirm(IdeWebPrompt prompt) async {
    if (!mounted || _dialog != null) return false;
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      builder: (_) => IdeWebPromptDialog(prompt: prompt),
    );
    _dialog = route;
    try {
      return await navigator.push(route) ?? false;
    } finally {
      if (identical(_dialog, route)) _dialog = null;
      if (mounted) _scheduleStatus();
    }
  }

  @override
  void dismiss() {
    final route = _dialog;
    if (route == null || !route.isActive) return;
    route.navigator?.removeRoute(route);
  }

  @override
  void close() => _pop();

  void _pop() {
    if (!mounted || _popping) return;
    _popping = true;
    dismiss();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      // Màn mở thẳng (không có màn trước): về trang chủ.
      context.go('/');
    }
  }

  Future<void> _onBack() async {
    if (ref.read(ideWebControllerProvider) is IdeWebReady &&
        await _controller.goBack()) {
      return;
    }
    if (mounted) unawaited(_controller.cancel());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<IdeWebState>(ideWebControllerProvider, (_, next) {
      if (next is! IdeWebClosed) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pop());
    });
    ref.listen<Set<String>>(activeCallTrackerProvider, (_, _) => _pushStatus());
    ref.listen<bool>(ideWebEnabledProvider, (_, enabled) {
      if (!enabled) unawaited(_controller.onAccessLost());
    });
    ref.listen<AsyncValue<String?>>(authAccessTokenProvider, (_, next) {
      if (next.hasValue && !next.isLoading && (next.value ?? '').isEmpty) {
        unawaited(_controller.cancel());
      }
    });
    final enabled = ref.watch(ideWebEnabledProvider);
    final current = ref.watch(ideWebControllerProvider);
    final state = enabled ? current : const IdeWebDisabled();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onBack());
      },
      child: Scaffold(
        backgroundColor: WebTuiColors.of(context).background,
        appBar: AppBar(
          leading: IconButton(
            key: const Key('ide_web_close'),
            tooltip: tr('Đóng', 'Close'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => unawaited(_controller.cancel()),
          ),
          title: const Text(
            'VPSTTT IDE',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (state case IdeWebReady(:final session))
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                    ),
                    child: IdeWebMicChip(capturing: session.capturing),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: switch (state) {
            // Lớp khoá đang che: gỡ khung native khỏi cây (trang vẫn sống).
            IdeWebReady() when _locked => const SizedBox.expand(),
            IdeWebReady(:final session) => KeyedSubtree(
              key: const Key('ide_web_view'),
              child: session.view.build(),
            ),
            _ => IdeWebStateView(
              state: state,
              onRetry: () => unawaited(_controller.open()),
              onClose: () => unawaited(_controller.cancel()),
            ),
          },
        ),
      ),
    );
  }
}
