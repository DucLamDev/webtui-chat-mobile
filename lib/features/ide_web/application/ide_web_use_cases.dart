import 'dart:async';

import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../../../l10n/app_strings.dart';
import '../../auth/application/oidc_pkce.dart';
import '../../auth/domain/repositories/auth_token_repository.dart';
import '../domain/ide_web_device_key.dart';
import '../domain/ide_web_failure.dart';
import '../domain/ide_web_host_policy.dart';
import '../domain/ide_web_launch.dart';
import '../domain/ide_web_owner.dart';
import '../domain/ide_web_ports.dart';
import 'ide_web_device_keys.dart';
import 'ide_web_serial.dart';

/// Phiên chat + người tại một thời điểm.
final class IdeWebSessionSnapshot {
  const IdeWebSessionSnapshot({required this.guard, required this.owner});

  final AuthTokenMutationGuard guard;
  final IdeWebOwner owner;
}

/// Đọc và kiểm lại phiên chat đang dùng.
final class IdeWebSessionReader {
  const IdeWebSessionReader({
    required AuthTokenRepository tokens,
    required Future<String?> Function() currentUserId,
  }) : _tokens = tokens,
       _currentUserId = currentUserId;

  final AuthTokenRepository _tokens;
  final Future<String?> Function() _currentUserId;

  Future<IdeWebSessionSnapshot?> capture() async {
    final guard = await _tokens.captureMutationGuard();
    if (guard == null) return null;
    final userId = (await _currentUserId())?.trim() ?? '';
    if (userId.isEmpty || !await _tokens.isMutationGuardCurrent(guard)) {
      return null;
    }
    return IdeWebSessionSnapshot(
      guard: guard,
      owner: IdeWebOwner(scopeId: guard.instanceScopeId, userId: userId),
    );
  }

  Future<bool> isCurrent(IdeWebSessionSnapshot session) async {
    if (!await _tokens.isMutationGuardCurrent(session.guard)) return false;
    final token = await _tokens.readAccessTokenIfCurrent(session.guard);
    return token?.trim().isNotEmpty ?? false;
  }
}

sealed class IdeWebStart {
  const IdeWebStart();
}

final class IdeWebStartBrowser extends IdeWebStart {
  const IdeWebStartBrowser(this.url);

  final Uri url;
}

final class IdeWebStartView extends IdeWebStart {
  const IdeWebStartView({required this.entry, required this.session});

  final IdeWebEntry entry;
  final IdeWebSessionSnapshot session;
}

Failure _unavailable() => Failure(
  kind: FailureKind.server,
  code: 'IDE_WEB_UNAVAILABLE',
  message: tr(
    'Chưa kết nối được VPSTTT IDE.',
    'Could not connect to VPSTTT IDE.',
  ),
);

Failure _cancelled() => Failure(
  kind: FailureKind.cancelled,
  code: ideWebLaunchCancelledCode,
  message: tr('Đã huỷ.', 'Cancelled.'),
);

Failure _expired() => Failure(
  kind: FailureKind.unauthorized,
  code: 'IDE_WEB_LAUNCH_EXPIRED',
  message: tr('Phiên đã hết hạn.', 'The session has expired.'),
);

/// Mở một lượt: PKCE, gọi máy chủ, kiểm địa chỉ, ghi lượt chờ.
final class StartIdeWebUseCase {
  StartIdeWebUseCase({
    required IdeWebRepository repository,
    required IdeWebPendingStore pending,
    required IdeWebSessionReader sessions,
    required IdeWebDeviceKeys keys,
    required IdeWebHostPolicy? Function() policy,
    required String platform,
    required String appVersion,
    DateTime Function()? clock,
  }) : _repository = repository,
       _pending = pending,
       _sessions = sessions,
       _keys = keys,
       _policy = policy,
       _platform = platform,
       _appVersion = appVersion,
       _clock = clock ?? DateTime.now;

  final IdeWebRepository _repository;
  final IdeWebPendingStore _pending;
  final IdeWebSessionReader _sessions;
  final IdeWebDeviceKeys _keys;
  final IdeWebHostPolicy? Function() _policy;
  final String _platform;
  final String _appVersion;
  final DateTime Function() _clock;
  int _generation = 0;

  /// Bỏ lượt đang gọi máy chủ (người dùng huỷ / đóng màn).
  void abandon() => _generation++;

  Future<Result<IdeWebStart>> execute() async {
    final generation = ++_generation;
    final policy = _policy();
    if (policy == null) {
      return FailureResult(
        Failure(
          kind: FailureKind.forbidden,
          code: 'IDE_WEB_DISABLED',
          message: tr('VPSTTT IDE đang tắt.', 'VPSTTT IDE is turned off.'),
        ),
      );
    }
    try {
      final session = await _sessions.capture();
      if (session == null) return FailureResult(_expired());
      final pkce = generateOidcPkcePair();
      final result = await _repository.launch(
        IdeWebLaunchRequest(
          platform: _platform,
          appVersion: _appVersion,
          codeChallenge: pkce.challenge,
          possessionKeyId: await _hint(
            session.owner,
            IdeWebKeyPurpose.possession,
          ),
          biometricKeyId: await _hint(
            session.owner,
            IdeWebKeyPurpose.biometric,
          ),
        ),
      );
      if (result case FailureResult(:final failure)) {
        return FailureResult(
          generation == _generation ? failure : _cancelled(),
        );
      }
      final launch = (result as Success<IdeWebLaunch>).value;
      if (generation != _generation || !await _sessions.isCurrent(session)) {
        unawaited(_repository.cancel(launch.launchId));
        return FailureResult(_cancelled());
      }
      switch (launch) {
        case IdeWebDirectLaunch(:final entry):
          if (!policy.isEnterUrl(entry.enterUrl)) {
            unawaited(_repository.cancel(launch.launchId));
            return FailureResult(_unavailable());
          }
          // Giữ lượt để nhận callback nâng quyền (PIN / 2FA trên trình duyệt).
          await _pending.write(
            PendingIdeWebLaunch(
              launchId: launch.launchId,
              state: launch.state,
              codeVerifier: pkce.verifier,
              scopeId: session.owner.scopeId,
              userId: session.owner.userId,
              expiresAt: launch.launchExpiresAt.toUtc(),
              elevation: true,
            ),
          );
          if (generation != _generation) {
            await _pending.clear();
            return FailureResult(_cancelled());
          }
          return Success(IdeWebStartView(entry: entry, session: session));
        case IdeWebBrowserLaunch():
          if (!policy.isBrowserUrl(launch.browserUrl)) {
            unawaited(_repository.cancel(launch.launchId));
            return FailureResult(_unavailable());
          }
          final localLimit = _clock().toUtc().add(ideWebLaunchTtl);
          await _pending.write(
            PendingIdeWebLaunch(
              launchId: launch.launchId,
              state: launch.state,
              codeVerifier: pkce.verifier,
              scopeId: session.owner.scopeId,
              userId: session.owner.userId,
              // Giờ máy có thể lệch: không dùng hạn máy chủ để cắt sớm hơn.
              expiresAt: localLimit,
            ),
          );
          if (generation != _generation) {
            await _pending.clear();
            unawaited(_repository.cancel(launch.launchId));
            return FailureResult(_cancelled());
          }
          return Success(IdeWebStartBrowser(launch.browserUrl));
      }
    } on Object {
      return FailureResult(
        generation == _generation ? _unavailable() : _cancelled(),
      );
    }
  }

  /// Gợi ý mã khoá không được làm hỏng việc mở.
  Future<String?> _hint(IdeWebOwner owner, IdeWebKeyPurpose purpose) async {
    try {
      return await _keys.hint(owner, purpose);
    } on Object {
      return null;
    }
  }
}

sealed class IdeWebCompletion {
  const IdeWebCompletion();
}

/// Callback lạ / lặp: bỏ êm.
final class IdeWebCallbackIgnored extends IdeWebCompletion {
  const IdeWebCallbackIgnored();
}

final class IdeWebCompleted extends IdeWebCompletion {
  const IdeWebCompleted({required this.entry, required this.session});

  final IdeWebEntry entry;
  final IdeWebSessionSnapshot session;
}

final class IdeWebCompletionFailed extends IdeWebCompletion {
  const IdeWebCompletionFailed(this.failure);

  final Failure failure;
}

/// Đổi callback lấy dữ liệu mở WebView. Bản ghi chờ bị xoá TRƯỚC khi gọi máy
/// chủ nên mã chỉ dùng một lần, kể cả khi hệ điều hành phát callback hai lần.
/// Thành công thì ghi lại lượt (chỉ để nâng quyền sau đó, máy chủ nhận tối đa
/// 3 lần); mã đã dùng được nhớ trong bộ nhớ để callback lặp bị bỏ êm.
final class CompleteIdeWebUseCase {
  CompleteIdeWebUseCase({
    required IdeWebRepository repository,
    required IdeWebPendingStore pending,
    required IdeWebSessionReader sessions,
    required IdeWebHostPolicy? Function() policy,
    DateTime Function()? clock,
  }) : _repository = repository,
       _pending = pending,
       _sessions = sessions,
       _policy = policy,
       _clock = clock ?? DateTime.now;

  final IdeWebRepository _repository;
  final IdeWebPendingStore _pending;
  final IdeWebSessionReader _sessions;
  final IdeWebHostPolicy? Function() _policy;
  final DateTime Function() _clock;
  final _serial = IdeWebSerial();
  final _usedCodes = <String>[];

  bool _wasUsed(String code) =>
      _usedCodes.any((used) => ideWebConstantTimeEquals(used, code));

  void _markUsed(String code) {
    if (_usedCodes.length >= 8) _usedCodes.removeAt(0);
    _usedCodes.add(code);
  }

  /// Callback này có thuộc lượt đang chờ không (không xoá gì).
  Future<bool> matches(Uri uri) async {
    try {
      final callback = parseIdeWebCallback(uri);
      if (callback == null) return false;
      final pending = await _pending.read();
      return pending != null &&
          !_wasUsed(callback.code) &&
          ideWebConstantTimeEquals(pending.state, callback.state);
    } on Object {
      return false;
    }
  }

  Future<IdeWebCompletion> execute(Uri uri) async {
    try {
      return await _execute(uri);
    } on Object {
      return IdeWebCompletionFailed(_unavailable());
    }
  }

  Future<IdeWebCompletion> _execute(Uri uri) async {
    final callback = parseIdeWebCallback(uri);
    if (callback == null) return const IdeWebCallbackIgnored();
    final pending = await _serial.run(() async {
      final stored = await _pending.read();
      if (stored == null ||
          _wasUsed(callback.code) ||
          !ideWebConstantTimeEquals(stored.state, callback.state)) {
        return null;
      }
      await _pending.clear();
      _markUsed(callback.code);
      return stored;
    });
    if (pending == null) return const IdeWebCallbackIgnored();
    if (!_clock().toUtc().isBefore(pending.expiresAt)) {
      unawaited(_repository.cancel(pending.launchId));
      return IdeWebCompletionFailed(_expired());
    }
    final policy = _policy();
    final session = await _sessions.capture();
    // Đổi người / máy chủ giữa chừng: bỏ lượt, không gửi gì thay người khác.
    if (policy == null ||
        session == null ||
        session.owner.scopeId != pending.scopeId ||
        session.owner.userId != pending.userId) {
      return IdeWebCompletionFailed(_expired());
    }
    final result = await _repository.complete(
      launchId: pending.launchId,
      code: callback.code,
      state: callback.state,
      codeVerifier: pending.codeVerifier,
    );
    if (!await _sessions.isCurrent(session)) {
      return IdeWebCompletionFailed(_cancelled());
    }
    switch (result) {
      case FailureResult(:final failure):
        return IdeWebCompletionFailed(failure);
      case Success(value: final entry):
        if (!policy.isEnterUrl(entry.enterUrl)) {
          return IdeWebCompletionFailed(_unavailable());
        }
        await _rearm(pending);
        return IdeWebCompleted(entry: entry, session: session);
    }
  }

  /// Ghi lại lượt để nhận callback nâng quyền sau (không ghi đè lượt mới hơn).
  /// Chỉ lượt mở thẳng màn nhúng mới nâng quyền được; lượt đăng nhập bằng
  /// trình duyệt máy chủ chỉ nhận complete một lần.
  Future<void> _rearm(PendingIdeWebLaunch pending) async {
    if (!pending.elevation) return;
    try {
      await _serial.run(() async {
        if (await _pending.read() != null) return;
        if (!_clock().toUtc().isBefore(pending.expiresAt)) return;
        await _pending.write(pending);
      });
    } on Object {
      // Không nâng quyền được nữa thì mở lại màn là lượt mới.
    }
  }
}

/// Bỏ lượt đang chờ: xoá bản ghi trên máy và báo máy chủ (lỗi bỏ qua).
final class CancelIdeWebUseCase {
  const CancelIdeWebUseCase({
    required IdeWebRepository repository,
    required IdeWebPendingStore pending,
  }) : _repository = repository,
       _pending = pending;

  final IdeWebRepository _repository;
  final IdeWebPendingStore _pending;

  Future<void> execute() async {
    try {
      final pending = await _pending.read();
      if (pending == null) return;
      await _pending.clear();
      // Lượt đã vào màn nhúng: đóng màn chỉ ngắt người xem.
      if (pending.elevation) return;
      await _repository.cancel(pending.launchId);
    } on Object {
      // Máy chủ tự hết hạn lượt.
    }
  }
}

/// Đăng xuất khi còn token: báo máy chủ thu hồi phiên IDE, chờ tối đa 3 giây.
final class EndIdeWebSessionUseCase {
  const EndIdeWebSessionUseCase(
    this._repository, {
    this.timeout = const Duration(seconds: 3),
  });

  final IdeWebRepository _repository;
  final Duration timeout;

  Future<void> execute() async {
    try {
      await _repository.endCurrentSession().timeout(timeout);
    } on Object {
      // Không cản đăng xuất; máy chủ tự thu hồi khi phiên chat mất.
    }
  }
}
