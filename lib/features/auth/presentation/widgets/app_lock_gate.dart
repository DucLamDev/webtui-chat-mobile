import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({
    required this.child,
    required this.protectSession,
    super.key,
  });

  final Widget child;
  final bool protectSession;

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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blockTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.protectSession) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (ref.read(isAppLockEnabledProvider).valueOrNull == true && mounted) {
        setState(() {
          _locked = true;
          _biometricAttempted = false;
          _pinController.clear();
        });
      }
      return;
    }
    if (state == AppLifecycleState.resumed &&
        ref.read(isAppLockEnabledProvider).valueOrNull == true &&
        mounted) {
      setState(() {
        _locked = true;
        _biometricAttempted = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.protectSession) {
      return widget.child;
    }
    final enabled = ref.watch(isAppLockEnabledProvider);
    return switch (enabled) {
      AsyncData(value: false) => widget.child,
      AsyncData(value: true) when !_locked => widget.child,
      AsyncData(value: true) => _lockedView(context),
      AsyncError() => _lockErrorView(),
      _ => const ColoredBox(
        color: Color(0xFFF6FAFF),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
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
                      'WebTui Chat đã khóa',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Nhập mã PIN hoặc dùng sinh trắc học để tiếp tục.',
                      textAlign: TextAlign.center,
                    ),
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
