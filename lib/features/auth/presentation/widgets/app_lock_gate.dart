import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../core/security/active_call_tracker.dart';
import '../../domain/entities/app_lock_timeout_policy.dart';

/// Lớp khoá ứng dụng (lõi 3.1).
///
/// Lớp khoá là một lớp PHỦ nằm trên router: nội dung bên dưới (màn gọi, phòng
/// chat đang mở, chữ đang soạn) vẫn được giữ nguyên, chỉ bị che và chặn chạm.
/// Ứng dụng tự khoá khi không chạm vào app quá N phút hoặc chạy nền quá N phút
/// (N = `effectiveAppLockMinutesProvider`), và KHÔNG khoá khi đang có cuộc gọi.
/// Trạng thái `inactive` (kéo thanh thông báo, trình chuyển ứng dụng, cuộc gọi
/// hệ thống hiện lên) không làm khoá.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({
    required this.child,
    required this.protectSession,
    this.clock,
    this.idleCheckInterval = const Duration(seconds: 15),
    super.key,
  });

  final Widget child;
  final bool protectSession;

  /// Đồng hồ thay thế cho test.
  @visibleForTesting
  final DateTime Function()? clock;

  /// Chu kỳ kiểm tra không dùng.
  @visibleForTesting
  final Duration idleCheckInterval;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  final _pinController = TextEditingController();
  bool _locked = true;
  bool _busy = false;
  bool _biometricAttempted = false;
  int _failedAttempts = 0;
  DateTime? _blockedUntil;
  Timer? _blockTimer;
  Timer? _idleTimer;
  String? _errorMessage;
  late DateTime _lastInteraction;
  DateTime? _backgroundedAt;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastInteraction = _now();
    _idleTimer = Timer.periodic(widget.idleCheckInterval, (_) => _checkIdle());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blockTimer?.cancel();
    _idleTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.protectSession) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _backgroundedAt ??= _now();
      case AppLifecycleState.inactive:
        // Kéo thanh thông báo, trình chuyển ứng dụng, cuộc gọi hệ thống: không khoá.
        break;
      case AppLifecycleState.resumed:
        final backgroundedAt = _backgroundedAt;
        _backgroundedAt = null;
        if (backgroundedAt != null && _hasExpiredSince(backgroundedAt)) {
          _lock();
        } else {
          _markInteraction();
        }
    }
  }

  bool get _lockEnabled =>
      ref.read(isAppLockEnabledProvider).valueOrNull == true;

  bool get _inCall => ref.read(activeCallTrackerProvider).isNotEmpty;

  bool _hasExpiredSince(DateTime since) {
    return AppLockTimeoutPolicy.hasExpired(
      since: since,
      now: _now(),
      minutes: ref.read(effectiveAppLockMinutesProvider),
    );
  }

  void _markInteraction() {
    _lastInteraction = _now();
  }

  void _checkIdle() {
    if (!mounted ||
        !widget.protectSession ||
        _locked ||
        _backgroundedAt != null ||
        !_lockEnabled) {
      return;
    }
    if (_inCall) {
      _markInteraction();
      return;
    }
    if (_hasExpiredSince(_lastInteraction)) {
      _lock();
    }
  }

  void _lock() {
    if (!mounted || !_lockEnabled || _inCall || _locked) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _locked = true;
      _biometricAttempted = false;
      _errorMessage = null;
      _pinController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Set<String>>(activeCallTrackerProvider, (previous, next) {
      if (next.isEmpty && (previous?.isNotEmpty ?? false)) {
        // Vừa kết thúc cuộc gọi: tính lại thời gian không dùng từ lúc này.
        _markInteraction();
      }
    });
    ref.listen<AsyncValue<bool>>(isAppLockEnabledProvider, (previous, next) {
      if (previous?.valueOrNull == false && next.valueOrNull == true) {
        // Người dùng vừa bật khoá trong cài đặt: không khoá ngay trước mặt họ.
        setState(() => _locked = false);
        _markInteraction();
      }
    });
    if (!widget.protectSession) {
      return widget.child;
    }
    final enabled = ref.watch(isAppLockEnabledProvider);
    final value = enabled.valueOrNull;
    final Widget? overlay;
    if (value == null && enabled.hasError) {
      overlay = _lockErrorView();
    } else if (value == null) {
      overlay = const ColoredBox(
        color: Color(0xFFF6FAFF),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (value && _locked) {
      overlay = _lockedView(context);
    } else {
      overlay = null;
    }
    final obscured = overlay != null;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _markInteraction(),
      child: Stack(
        fit: StackFit.expand,
        textDirection: TextDirection.ltr,
        children: [
          // Nội dung luôn được giữ trong cây widget (không gỡ màn gọi / phòng chat).
          ExcludeSemantics(
            excluding: obscured,
            child: AbsorbPointer(absorbing: obscured, child: widget.child),
          ),
          if (overlay != null) Positioned.fill(child: overlay),
        ],
      ),
    );
  }

  Widget _lockedView(BuildContext context) {
    if (!_biometricAttempted && !_busy) {
      _biometricAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
    final blockedSeconds = _remainingBlockSeconds();
    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 58),
                    const SizedBox(height: 18),
                    Text(
                      'WebTUI Chat đã khóa',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Nhập mã PIN hoặc dùng sinh trắc học để tiếp tục.',
                      textAlign: TextAlign.center,
                    ),
                    if (ref.watch(activeCallTrackerProvider).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Cuộc gọi vẫn đang diễn ra. Mở khóa để quay lại cuộc gọi.',
                        key: Key('app_lock_active_call_notice'),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('app_lock_pin_field'),
                      controller: _pinController,
                      autofocus: true,
                      enabled: !_busy && blockedSeconds == 0,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.password],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(12),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Mã PIN',
                        prefixIcon: Icon(Icons.pin_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _unlockWithPin(),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (blockedSeconds > 0) ...[
                      const SizedBox(height: 12),
                      Text('Thử lại sau $blockedSeconds giây.'),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const Key('app_lock_unlock_button'),
                      onPressed: _busy || blockedSeconds > 0
                          ? null
                          : _unlockWithPin,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: const Text('Mở khóa'),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _busy ? null : _tryBiometric,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Dùng sinh trắc học'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lockErrorView() {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => ref.invalidate(isAppLockEnabledProvider),
          child: const Text('Thử đọc lại khóa ứng dụng'),
        ),
      ),
    );
  }

  Future<void> _tryBiometric() async {
    if (!mounted || _busy) {
      return;
    }
    final biometrics = ref.read(biometricAuthServiceProvider);
    if (!await biometrics.isAvailable()) {
      return;
    }
    if (mounted) {
      setState(() => _busy = true);
    }
    final authenticated = await biometrics.authenticate();
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (authenticated) {
        _locked = false;
        _errorMessage = null;
        _failedAttempts = 0;
        _lastInteraction = _now();
      }
    });
  }

  Future<void> _unlockWithPin() async {
    if (_busy || _remainingBlockSeconds() > 0) {
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    final result = await ref
        .read(unlockAppUseCaseProvider)
        .execute(_pinController.text);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Success<void>():
        setState(() {
          _busy = false;
          _locked = false;
          _lastInteraction = _now();
          _failedAttempts = 0;
          _blockedUntil = null;
          _blockTimer?.cancel();
          _blockTimer = null;
          _errorMessage = null;
          _pinController.clear();
        });
      case FailureResult<void>(failure: final failure):
        _failedAttempts += 1;
        if (_failedAttempts >= 5) {
          _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
          _failedAttempts = 0;
          _startBlockTimer();
        }
        setState(() {
          _busy = false;
          _errorMessage = failure.message;
          _pinController.clear();
        });
    }
  }

  int _remainingBlockSeconds() {
    final until = _blockedUntil;
    if (until == null) {
      return 0;
    }
    final remainingMilliseconds = until
        .difference(DateTime.now())
        .inMilliseconds;
    if (remainingMilliseconds <= 0) {
      return 0;
    }
    return (remainingMilliseconds / Duration.millisecondsPerSecond).ceil();
  }

  void _startBlockTimer() {
    _blockTimer?.cancel();
    final until = _blockedUntil;
    if (until == null) {
      return;
    }
    final remaining = until.difference(DateTime.now());
    _blockTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _blockedUntil = null;
        _blockTimer = null;
        _errorMessage = null;
      });
    });
  }
}
