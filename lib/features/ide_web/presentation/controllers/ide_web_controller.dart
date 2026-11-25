import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/logging/redacting_logger.dart';
import '../../../../core/media/exclusive_media_playback.dart';
import '../../../../core/platform/external_url_launcher.dart';
import '../../../../core/result/result.dart';
import '../../application/ide_web_bridge_dispatcher.dart';
import '../../application/ide_web_callback_inbox.dart';
import '../../application/ide_web_device_keys.dart';
import '../../application/ide_web_mic_guard.dart';
import '../../application/ide_web_prompter.dart';
import '../../application/ide_web_providers.dart';
import '../../application/ide_web_rate_limiter.dart';
import '../../application/ide_web_session_cleaner.dart';
import '../../application/ide_web_use_cases.dart';
import '../../application/ide_web_view.dart';
import '../../application/ide_web_view_session.dart';
import '../../domain/ide_web_failure.dart';
import '../../domain/ide_web_host_policy.dart';
import '../../domain/ide_web_launch.dart';
import '../../domain/ide_web_ports.dart';

sealed class IdeWebState {
  const IdeWebState();
}

final class IdeWebLoading extends IdeWebState {
  const IdeWebLoading();
}

final class IdeWebWaitingBrowser extends IdeWebState {
  const IdeWebWaitingBrowser();
}

final class IdeWebReady extends IdeWebState {
  const IdeWebReady(this.session);

  final IdeWebViewSession session;
}

final class IdeWebUnavailable extends IdeWebState {
  const IdeWebUnavailable({this.rateLimited = false});

  final bool rateLimited;
}

final class IdeWebDisabled extends IdeWebState {
  const IdeWebDisabled();
}

final class IdeWebNotAllowed extends IdeWebState {
  const IdeWebNotAllowed();
}

final class IdeWebExpired extends IdeWebState {
  const IdeWebExpired();
}

final class IdeWebViewTooOld extends IdeWebState {
  const IdeWebViewTooOld();
}

/// Màn phải đóng (người dùng huỷ, phiên chat kết thúc).
final class IdeWebClosed extends IdeWebState {
  const IdeWebClosed();
}

/// Mọi thứ màn IDE cần, gom một chỗ để test thay được từng phần.
final class IdeWebControllerDeps {
  const IdeWebControllerDeps({
    required this.start,
    required this.complete,
    required this.cancel,
    required this.sessions,
    required this.cleaner,
    required this.inbox,
    required this.browser,
    required this.keys,
    required this.newFileSaver,
    required this.micPermission,
    required this.limiter,
    required this.viewFactory,
    required this.policy,
    required this.appInfo,
    required this.launcher,
    required this.logger,
  });

  final StartIdeWebUseCase start;
  final CompleteIdeWebUseCase complete;
  final CancelIdeWebUseCase cancel;
  final IdeWebSessionReader sessions;
  final IdeWebSessionCleaner cleaner;
  final IdeWebCallbackInbox inbox;
  final IdeWebBrowser browser;
  final IdeWebDeviceKeys keys;
  final IdeWebFileSaver Function() newFileSaver;
  final IdeWebMicPermission micPermission;
  final IdeWebRateLimiter limiter;
  final IdeWebViewFactory viewFactory;
  final IdeWebHostPolicy? Function() policy;
  final IdeWebAppInfo appInfo;
  final ExternalUrlLauncher launcher;
  final RedactingLogger logger;
}

final ideWebControllerDepsProvider = Provider.autoDispose<IdeWebControllerDeps>(
  (ref) => IdeWebControllerDeps(
    start: ref.watch(startIdeWebUseCaseProvider),
    complete: ref.watch(completeIdeWebUseCaseProvider),
    cancel: ref.watch(cancelIdeWebUseCaseProvider),
    sessions: ref.watch(ideWebSessionReaderProvider),
    cleaner: ref.watch(ideWebSessionCleanerProvider),
    inbox: ref.watch(ideWebCallbackInboxProvider),
    browser: ref.watch(ideWebBrowserProvider),
    keys: ref.watch(ideWebDeviceKeysProvider),
    newFileSaver: ref.watch(ideWebFileSaverFactoryProvider),
    micPermission: ref.watch(ideWebMicPermissionProvider),
    limiter: ref.watch(ideWebRateLimiterProvider),
    viewFactory: ref.watch(ideWebViewFactoryProvider),
    policy: () => ref.read(ideWebHostPolicyProvider),
    appInfo: ref.watch(ideWebAppInfoProvider),
    launcher: ref.watch(externalUrlLauncherProvider),
    logger: ref.watch(redactingLoggerProvider),
  ),
);

final ideWebControllerProvider =
    StateNotifierProvider.autoDispose<IdeWebController, IdeWebState>(
      // `read`: làm mới discovery / mạng không được dựng lại màn đang mở.
      (ref) => IdeWebController(ref.read(ideWebControllerDepsProvider)),
    );

/// Điều phối một lần mở màn IDE. Mọi bước bất đồng bộ mang số lượt [_run]: lượt
/// cũ về muộn bị bỏ.
final class IdeWebController extends StateNotifier<IdeWebState>
    implements IdeWebPrompter {
  IdeWebController(this._deps) : super(const IdeWebLoading()) {
    _unlisten = _deps.inbox.listen((uri) => unawaited(_complete(uri)));
    _unregister = _deps.cleaner.registerOpenView(_closeForCleanup);
  }

  final IdeWebControllerDeps _deps;
  late final void Function() _unlisten;
  late final void Function() _unregister;
  IdeWebPrompter? _prompter;
  IdeWebViewSession? _session;
  Timer? _waitingTimer;
  int _run = 0;
  bool _started = false;
  bool _completing = false;
  IdeWebScreenStatus _status = const IdeWebScreenStatus(
    visible: false,
    resumed: true,
    locked: false,
    inCall: false,
  );

  bool _isCurrent(int run) => mounted && run == _run;

  void attachPrompter(IdeWebPrompter prompter) => _prompter = prompter;

  void detachPrompter(IdeWebPrompter prompter) {
    if (identical(_prompter, prompter)) _prompter = null;
  }

  /// Lần đầu màn hiện: callback tới trước (app vừa được mở lại) thì hoàn tất
  /// lượt cũ, không thì mở lượt mới.
  Future<void> begin() async {
    if (_started) return;
    _started = true;
    final callback = _deps.inbox.take();
    if (callback == null || _deps.policy() == null) {
      await open();
      return;
    }
    final run = ++_run;
    if (!await _complete(callback) && _isCurrent(run)) await open();
  }

  /// Mở (lại) bằng một lượt mới; lượt đang chờ trình duyệt bị bỏ.
  Future<void> open() async {
    final run = ++_run;
    _waitingTimer?.cancel();
    if (_deps.policy() == null) {
      await _failWith(IdeWebFailureKind.disabled);
      return;
    }
    state = const IdeWebLoading();
    unawaited(ExclusiveMediaPlayback.pauseAll());
    await _closeSession();
    await _deps.cancel.execute();
    if (!_isCurrent(run)) return;
    final result = await _deps.start.execute();
    if (!_isCurrent(run)) return;
    switch (result) {
      case FailureResult(:final failure):
        _show(ideWebFailureKindOf(failure));
      case Success(value: IdeWebStartView(:final entry, :final session)):
        await _enter(run, entry, session);
      case Success(value: IdeWebStartBrowser(:final url)):
        await _openBrowser(run, url);
    }
  }

  Future<void> _openBrowser(int run, Uri url) async {
    state = const IdeWebWaitingBrowser();
    _waitingTimer = Timer(ideWebLaunchTtl, () {
      if (!_isCurrent(run) || state is! IdeWebWaitingBrowser) return;
      _run++;
      unawaited(_deps.cancel.execute());
      state = const IdeWebExpired();
    });
    final result = await _deps.browser.authenticate(
      url,
      scheme: ideWebCallbackScheme,
    );
    if (!_isCurrent(run)) return;
    switch (result) {
      case IdeWebBrowserOpened():
        break;
      case IdeWebBrowserCallback(:final uri):
        await _complete(uri);
      case IdeWebBrowserCancelled():
        await cancel();
      case IdeWebBrowserFailed():
        _run++;
        _waitingTimer?.cancel();
        state = const IdeWebUnavailable();
        await _deps.cancel.execute();
    }
  }

  /// `false` khi callback không thuộc lượt nào (bỏ êm), kể cả bản lặp của
  /// callback đang xử lý.
  Future<bool> _complete(Uri uri) async {
    if (!mounted || _completing) return false;
    _completing = true;
    final int run;
    final IdeWebCompletion completion;
    try {
      if (!await _deps.complete.matches(uri) || !mounted) return false;
      run = ++_run;
      _waitingTimer?.cancel();
      state = const IdeWebLoading();
      completion = await _deps.complete.execute(uri);
    } finally {
      _completing = false;
    }
    if (!_isCurrent(run)) return true;
    switch (completion) {
      case IdeWebCallbackIgnored():
        // Lượt đã bị dùng / bỏ giữa chừng.
        state = const IdeWebExpired();
      case IdeWebCompleted(:final entry, :final session):
        await _enter(run, entry, session);
      case IdeWebCompletionFailed(:final failure):
        _show(ideWebFailureKindOf(failure));
    }
    return true;
  }

  Future<void> _enter(
    int run,
    IdeWebEntry entry,
    IdeWebSessionSnapshot session,
  ) async {
    final policy = _deps.policy();
    if (policy == null) {
      await _failWith(IdeWebFailureKind.disabled);
      return;
    }
    await _closeSession();
    if (!_isCurrent(run)) return;
    // Còn dữ liệu người trước mà chưa xoá được thì không tạo WebView.
    if (!await _deps.cleaner.prepareFor(session.owner)) {
      if (_isCurrent(run)) _show(IdeWebFailureKind.unavailable);
      return;
    }
    if (!_isCurrent(run)) return;
    IdeWebViewSession? view;
    try {
      view = _newSession(run, policy, session);
      _session = view;
      final supported = await view.start(entry);
      if (!_isCurrent(run)) {
        await view.close();
        return;
      }
      if (!supported) {
        await _closeSession();
        if (_isCurrent(run)) _show(IdeWebFailureKind.webViewTooOld);
        return;
      }
      if (view.isClosed) return;
      state = IdeWebReady(view);
      await view.onStatusChanged();
    } on Object {
      await view?.close();
      if (identical(_session, view)) _session = null;
      if (_isCurrent(run)) _show(IdeWebFailureKind.unavailable);
    }
  }

  IdeWebViewSession _newSession(
    int run,
    IdeWebHostPolicy policy,
    IdeWebSessionSnapshot session,
  ) {
    final view = _deps.viewFactory(policy);
    final files = _deps.newFileSaver();
    return IdeWebViewSession(
      view: view,
      mic: IdeWebMicGuard(
        view: view,
        policy: policy,
        prompter: this,
        permission: _deps.micPermission,
        status: () => _status,
      ),
      dispatcher: IdeWebBridgeDispatcher(
        owner: session.owner,
        origin: policy.origin,
        appInfo: _deps.appInfo,
        keys: _deps.keys,
        files: files,
        prompter: this,
        limiter: _deps.limiter,
        isActive: () => mounted && _status.active,
        isSessionCurrent: () => _deps.sessions.isCurrent(session),
        // Chỉ tên hàm và mã: không tham số, thử thách, chữ ký.
        log: (method, code) => _deps.logger.debug('Cầu nối VPSTTT IDE', {
          'method': method,
          'code': code,
        }),
      ),
      prompter: this,
      disposeFiles: files.disposeTemp,
      openExternal: (uri) => _deps.launcher.open(uri.toString()),
      onFailed: (kind) {
        if (_isCurrent(run)) unawaited(_failWith(kind));
      },
      status: () => _status,
    );
  }

  /// Màn / app / lớp khoá / cuộc gọi đổi trạng thái.
  void updateStatus(IdeWebScreenStatus status) {
    final before = _status;
    _status = status;
    final session = _session;
    if (session == null) return;
    if (before.resumed && !status.resumed) unawaited(session.onAppBackground());
    if (!before.resumed && status.resumed) unawaited(session.onAppForeground());
    unawaited(session.onStatusChanged());
  }

  /// Máy chủ / discovery vừa tắt tính năng khi màn đang mở.
  Future<void> onAccessLost() => _failWith(IdeWebFailureKind.disabled);

  /// Đang ở trang con của IDE thì lùi một trang; `false` = nên đóng màn.
  Future<bool> goBack() async {
    try {
      return await _session?.view.goBack() ?? false;
    } on Object {
      return false;
    }
  }

  /// Người dùng huỷ hoặc đóng màn.
  Future<void> cancel() async {
    _run++;
    _deps.start.abandon();
    _waitingTimer?.cancel();
    if (mounted) state = const IdeWebClosed();
    await _closeSession();
    await _deps.cancel.execute();
  }

  Future<void> _failWith(IdeWebFailureKind kind) async {
    final run = ++_run;
    _deps.start.abandon();
    _waitingTimer?.cancel();
    final hadView = _session != null;
    _show(kind);
    await _closeSession();
    if (hadView &&
        (kind == IdeWebFailureKind.disabled ||
            kind == IdeWebFailureKind.notAllowed ||
            kind == IdeWebFailureKind.expired)) {
      await _deps.cleaner.clearAll();
      // Dọn xong vẫn giữ màn trạng thái đang hiện.
      if (_isCurrent(run)) _show(kind);
    }
  }

  void _show(IdeWebFailureKind kind) {
    if (!mounted) return;
    state = switch (kind) {
      IdeWebFailureKind.disabled => const IdeWebDisabled(),
      IdeWebFailureKind.notAllowed => const IdeWebNotAllowed(),
      IdeWebFailureKind.unavailable => const IdeWebUnavailable(),
      IdeWebFailureKind.rateLimited => const IdeWebUnavailable(
        rateLimited: true,
      ),
      IdeWebFailureKind.expired => const IdeWebExpired(),
      IdeWebFailureKind.webViewTooOld => const IdeWebViewTooOld(),
      IdeWebFailureKind.cancelled => const IdeWebClosed(),
    };
  }

  /// Phiên chat kết thúc: đóng ngay trước khi dữ liệu WebView bị xoá. Gọi lúc
  /// không còn WebView (màn lỗi) thì chỉ bỏ lượt đang chờ.
  Future<void> _closeForCleanup() async {
    if (!mounted) return;
    final pendingWork =
        _session != null ||
        state is IdeWebLoading ||
        state is IdeWebWaitingBrowser ||
        state is IdeWebReady;
    if (!pendingWork) return;
    _run++;
    _deps.start.abandon();
    _waitingTimer?.cancel();
    state = const IdeWebClosed();
    await _closeSession();
  }

  Future<void> _closeSession() async {
    final session = _session;
    _session = null;
    await session?.close();
  }

  @override
  Future<bool> confirm(IdeWebPrompt prompt) async {
    final prompter = _prompter;
    if (prompter == null || !mounted || !_status.active) return false;
    return prompter.confirm(prompt);
  }

  @override
  void dismiss() => _prompter?.dismiss();

  @override
  void close() => unawaited(cancel());

  @override
  void dispose() {
    final waiting = state is IdeWebLoading || state is IdeWebWaitingBrowser;
    _run++;
    _deps.start.abandon();
    _waitingTimer?.cancel();
    _unlisten();
    _unregister();
    _prompter = null;
    unawaited(_closeSession());
    if (waiting) unawaited(_deps.cancel.execute());
    super.dispose();
  }
}
