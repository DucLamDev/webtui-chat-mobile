import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/privacy/background_privacy.dart';
import '../../../../core/security/active_call_tracker.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../auth/presentation/widgets/app_lock_gate.dart';
import '../../application/ide_web_access.dart';
import '../../application/ide_web_mic_guard.dart';
import '../../application/ide_web_prompter.dart';
import '../../application/ide_web_providers.dart';
import '../controllers/ide_web_controller.dart';
import '../widgets/ide_web_back_button.dart';
import '../widgets/ide_web_prompt_sheet.dart';
import '../widgets/ide_web_state_view.dart';
import '../widgets/ide_web_top_bar.dart';

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

  /// Người dùng đã quay lại app: từ đây màn không còn báo "đang hiện" (trang
  /// đang giữ ngầm không được nhận lại quyền micro / hỏi trong lúc màn đóng).
  bool _left = false;

  /// Phải đóng nhưng màn khác (cuộc gọi...) đang đè lên: đợi màn đó rời đi.
  bool _closeWhenCurrent = false;

  /// Bảng hỏi đang mở (tối đa một).
  ModalBottomSheetRoute<bool>? _dialog;

  /// Màn nhúng hiện nội dung dự án, câu trả lời AI và tệp kết quả: trong lúc
  /// màn đang hiện thì chặn chụp / quay (Android) và che khi quay (iPhone).
  static const _privacy = BackgroundPrivacyController();
  bool _secureHeld = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _resumed = !_isBackground(lifecycle);
    _controller = ref.read(ideWebControllerProvider.notifier)
      ..attachPrompter(this);
    // Vào lại trang đang giữ thì khung đầu đã có nội dung IDE: chặn chụp ngay.
    _holdSecureScreen(true);
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
    if (_closeWhenCurrent && _routeCurrent) {
      _closeWhenCurrent = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.detachPrompter(this);
    _holdSecureScreen(false);
    super.dispose();
  }

  void _holdSecureScreen(bool hold) {
    if (hold == _secureHeld) return;
    _secureHeld = hold;
    unawaited(
      hold ? _privacy.acquireSecureScreen() : _privacy.releaseSecureScreen(),
    );
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
    // Hộp xác nhận của chính màn này không tính là rời màn, trừ khi màn khác
    // đè lên cả hộp.
    final visible = !_left && (_routeCurrent || (_dialog?.isCurrent ?? false));
    _holdSecureScreen(visible);
    _controller.updateStatus(
      IdeWebScreenStatus(
        visible: visible,
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
    final route = ideWebPromptRoute(
      context: context,
      prompt: prompt,
      host: ref.read(ideWebHostPolicyProvider)?.host ?? '',
      onVisibilityChanged: _scheduleStatus,
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
    dismiss();
    if (ModalRoute.of(context)?.isCurrent == false) {
      // `pop` gỡ màn trên cùng, có thể là màn cuộc gọi.
      _closeWhenCurrent = true;
      return;
    }
    _popping = true;
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
    if (mounted) await _leave();
  }

  /// Quay lại app: trang IDE đang hiện thì giữ sống (lần sau vào khỏi đăng
  /// nhập), chưa có trang thì huỷ lượt; trạng thái `IdeWebClosed` tự đóng màn.
  Future<void> _leave() async {
    if (_left) return;
    _left = true;
    if (await _controller.leave()) _pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<IdeWebState>(ideWebControllerProvider, (_, next) {
      if (next is! IdeWebClosed) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pop());
    });
    ref.listen<Set<String>>(activeCallTrackerProvider, (_, _) => _pushStatus());
    // Mất quyền / phiên chat: provider của bộ điều khiển tự canh (cả khi trang
    // đang giữ mà không có màn).
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
        // Trang IDE hiện thì bỏ thanh trên cho trang tràn màn; nút quay lại nổi
        // ở góc dưới trái.
        appBar: state is IdeWebReady
            ? null
            : IdeWebTopBar(onClose: () => unawaited(_leave())),
        body: SafeArea(
          child: switch (state) {
            // Lớp khoá đang che: gỡ khung native khỏi cây (trang vẫn sống).
            IdeWebReady() when _locked => const SizedBox.expand(),
            IdeWebReady(:final session) => Stack(
              children: [
                Positioned.fill(
                  child: KeyedSubtree(
                    key: const Key('ide_web_view'),
                    child: session.view.build(),
                  ),
                ),
                PositionedDirectional(
                  start: 12,
                  bottom: 12,
                  child: IdeWebBackButton(
                    onPressed: () => unawaited(_leave()),
                    capturing: session.capturing,
                    // Bàn phím mở: nút không che ô nhập của IDE (Back vẫn
                    // dùng được); chỉ báo thu vẫn hiện.
                    showBack: MediaQuery.viewInsetsOf(context).bottom == 0,
                  ),
                ),
              ],
            ),
            _ => IdeWebStateView(
              state: state,
              onRetry: () => unawaited(_controller.open()),
              onClose: () => unawaited(_leave()),
            ),
          },
        ),
      ),
    );
  }
}
