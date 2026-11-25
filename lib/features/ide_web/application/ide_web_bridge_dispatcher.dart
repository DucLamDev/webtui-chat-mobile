import 'dart:async';
import 'dart:collection';

import '../../../l10n/app_strings.dart';
import '../domain/ide_web_bridge_protocol.dart';
import '../domain/ide_web_device_key.dart';
import '../domain/ide_web_file.dart';
import '../domain/ide_web_launch.dart';
import '../domain/ide_web_owner.dart';
import '../domain/ide_web_ports.dart';
import 'ide_web_device_keys.dart';
import 'ide_web_prompter.dart';
import 'ide_web_rate_limiter.dart';

final class IdeWebAppInfo {
  const IdeWebAppInfo({
    required this.appVersion,
    required this.platform,
    required this.osVersion,
  });

  final String appVersion;
  final String platform;
  final String osVersion;
}

/// Bộ điều phối cầu nối v1 (thuần Dart): danh sách hàm cố định, kiểm từng bước,
/// giới hạn tần suất, một việc ghi / ký một lúc, bỏ kết quả của trang cũ. Nhật
/// ký chỉ có tên hàm và mã lỗi.
final class IdeWebBridgeDispatcher {
  IdeWebBridgeDispatcher({
    required this.owner,
    required this.origin,
    required IdeWebAppInfo appInfo,
    required IdeWebDeviceKeys keys,
    required IdeWebFileSaver files,
    required IdeWebPrompter prompter,
    required IdeWebRateLimiter limiter,
    required bool Function() isActive,
    required Future<bool> Function() isSessionCurrent,
    void Function(String method, String code)? log,
  }) : _appInfo = appInfo,
       _keys = keys,
       _files = files,
       _prompter = prompter,
       _limiter = limiter,
       _isActive = isActive,
       _isSessionCurrent = isSessionCurrent,
       _log = log;

  /// Việc ghi / ký chờ tối đa (không tính việc đang chạy).
  static const maxQueued = 8;

  final IdeWebOwner owner;
  final String origin;
  final IdeWebAppInfo _appInfo;
  final IdeWebDeviceKeys _keys;
  final IdeWebFileSaver _files;
  final IdeWebPrompter _prompter;
  final IdeWebRateLimiter _limiter;

  /// Màn đang hiện, app ở trước, không bị lớp khoá che.
  final bool Function() _isActive;

  /// Phiên chat lúc mở màn còn hiệu lực.
  final Future<bool> Function() _isSessionCurrent;
  final void Function(String method, String code)? _log;

  final _usedIds = <String>{};
  final _queue = Queue<Completer<bool>>();
  bool _running = false;
  int _epoch = 0;
  bool _closed = false;

  /// Khung chính chuyển trang: huỷ mọi việc đang chờ, bỏ kết quả đang chạy.
  void onNavigation() {
    _epoch++;
    _usedIds.clear();
    _cancelQueue();
    _prompter.dismiss();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _epoch++;
    _cancelQueue();
  }

  void _cancelQueue() {
    while (_queue.isNotEmpty) {
      _queue.removeFirst().complete(false);
    }
  }

  /// Luôn trả một phong bì cho lớp native; trang đã đổi / màn đã đóng: `cancelled`.
  Future<String> handle({
    required String raw,
    required bool isMainFrame,
    required String messageOrigin,
  }) async {
    if (_closed) return _cancelledReply(peekBridgeRequestId(raw));
    if (!isMainFrame ||
        (messageOrigin != origin && messageOrigin != '$origin:443')) {
      return _error(
        peekBridgeRequestId(raw),
        null,
        BridgeErrorCode.forbiddenOrigin,
      );
    }
    if (!_limiter.allow(
      'message',
      limit: 240,
      window: const Duration(minutes: 1),
    )) {
      return _error(
        peekBridgeRequestId(raw),
        null,
        BridgeErrorCode.rateLimited,
      );
    }
    final epoch = _epoch;
    final parsed = parseBridgeRequest(raw, claimId: _usedIds.add);
    final request = parsed.request;
    if (request == null) {
      return _error(parsed.id ?? peekBridgeRequestId(raw), null, parsed.error!);
    }
    bool current() => !_closed && epoch == _epoch;
    try {
      final result = await _execute(request, current);
      if (!current()) return _cancelledReply(request.id);
      _log?.call(request.method.value, 'ok');
      return encodeBridgeResult(request.id, result);
    } on BridgeException catch (error) {
      if (!current()) return _cancelledReply(request.id);
      return _error(request.id, request.method, error.code);
    } on IdeWebKeyException catch (error) {
      if (!current()) return _cancelledReply(request.id);
      return _error(request.id, request.method, _keyError(error.code));
    } on Object {
      if (!current()) return _cancelledReply(request.id);
      return _error(request.id, request.method, BridgeErrorCode.failed);
    }
  }

  Future<Map<String, Object?>> _execute(
    BridgeRequest request,
    bool Function() current,
  ) {
    final p = request.params;
    switch (request.method) {
      case BridgeMethod.appInfo:
        _limit('read', 30, const Duration(minutes: 1));
        return Future.value({
          'bridge_version': ideWebBridgeVersion,
          'app_version': _appInfo.appVersion,
          'platform': _appInfo.platform,
          'os_version': _appInfo.osVersion,
          'methods': [for (final m in BridgeMethod.values) m.value],
        });
      case BridgeMethod.deviceStatus:
        _limit('read', 30, const Duration(minutes: 1));
        return _status();
      case BridgeMethod.deviceCreate:
        final purpose = IdeWebKeyPurpose.parse(p['purpose']);
        if (purpose == null || !isIdeWebChallenge(p['challenge']!)) {
          throw const BridgeException(BridgeErrorCode.badRequest);
        }
        _limit('create', 5, const Duration(hours: 1));
        return _exclusive(
          current,
          () => _create(purpose, p['challenge']!, current),
        );
      case BridgeMethod.deviceSign:
        if (!ideWebKeyIdPattern.hasMatch(p['key_id']!) ||
            !isIdeWebChallenge(p['challenge']!)) {
          throw const BridgeException(BridgeErrorCode.badRequest);
        }
        return _exclusive(
          current,
          () => _sign(p['key_id']!, p['challenge']!, current),
        );
      case BridgeMethod.deviceDelete:
        if (!ideWebKeyIdPattern.hasMatch(p['key_id']!)) {
          throw const BridgeException(BridgeErrorCode.badRequest);
        }
        _limit('delete', 10, const Duration(minutes: 1));
        return _exclusive(current, () => _delete(p['key_id']!, current));
      case BridgeMethod.fileSave:
        _limit('file', 10, const Duration(minutes: 1));
        final IdeWebFile file;
        try {
          file = IdeWebFile.fromBridge(
            name: p['name']!,
            mime: p['mime']!,
            dataBase64: p['data_base64']!,
          );
        } on IdeWebFileException catch (error) {
          throw BridgeException(switch (error.issue) {
            IdeWebFileIssue.malformed => BridgeErrorCode.badRequest,
            IdeWebFileIssue.blocked => BridgeErrorCode.unsupported,
            IdeWebFileIssue.tooLarge => BridgeErrorCode.tooLarge,
          });
        }
        return _exclusive(current, () => _saveFile(file, current));
      case BridgeMethod.appClose:
        // Màn đang bị che / khoá: trang không được đóng thay người dùng.
        if (!_isActive()) {
          throw const BridgeException(BridgeErrorCode.cancelled);
        }
        // Trả lời trang trước rồi mới đóng màn.
        Timer.run(_prompter.close);
        return Future.value(const {});
    }
  }

  Future<Map<String, Object?>> _status() async {
    await _requireSession();
    final keys = await _keys.status(owner);
    final biometric = await _keys.biometricState();
    return {
      'keys': [
        for (final item in keys)
          {
            'key_id': item.key.keyId,
            'purpose': item.key.purpose.apiValue,
            'created_at': item.key.createdAt.toUtc().toIso8601String(),
            'usable': item.usable,
          },
      ],
      'biometric': {
        'available': biometric.available,
        'enrolled': biometric.enrolled,
        'strong': biometric.strong,
      },
    };
  }

  Future<Map<String, Object?>> _create(
    IdeWebKeyPurpose purpose,
    String challenge,
    bool Function() current,
  ) async {
    await _confirm(IdeWebCreateKeyPrompt(purpose), current);
    await _requireSession();
    final key = await _keys.create(
      owner: owner,
      purpose: purpose,
      origin: origin,
      challenge: challenge,
      stillWanted: current,
    );
    if (!current()) {
      // Trang đã đổi, không ai nhận được khoá này.
      await _keys.delete(owner, key.keyId);
      throw const BridgeException(BridgeErrorCode.cancelled);
    }
    return {
      'key_id': key.keyId,
      'purpose': purpose.apiValue,
      'alg': 'ES256',
      'public_key': key.publicKey,
      'hardware': key.hardware,
      'proof': key.proof,
    };
  }

  Future<Map<String, Object?>> _sign(
    String keyId,
    String challenge,
    bool Function() current,
  ) async {
    await _requireSession();
    final key = await _keys.find(owner, keyId);
    if (key == null) throw const BridgeException(BridgeErrorCode.keyMissing);
    _limit('sign_${key.purpose.apiValue}', 10, const Duration(minutes: 1));
    if (!current()) throw const BridgeException(BridgeErrorCode.cancelled);
    final signature = await _keys.sign(
      owner: owner,
      keyId: keyId,
      origin: origin,
      challenge: challenge,
    );
    return {'signature': signature};
  }

  Future<Map<String, Object?>> _delete(
    String keyId,
    bool Function() current,
  ) async {
    if (await _keys.find(owner, keyId) == null) {
      throw const BridgeException(BridgeErrorCode.keyMissing);
    }
    await _confirm(const IdeWebDeleteKeyPrompt(), current);
    await _requireSession();
    await _keys.delete(owner, keyId);
    return const {};
  }

  Future<Map<String, Object?>> _saveFile(
    IdeWebFile file,
    bool Function() current,
  ) async {
    await _confirm(
      IdeWebSaveFilePrompt(name: file.name, bytes: file.bytes.length),
      current,
    );
    await _requireSession();
    final result = await _files.save(
      file,
      confirmOpen: () async =>
          current() &&
          _isActive() &&
          await _prompter.confirm(IdeWebOpenSavedFilePrompt(file.name)),
    );
    return switch (result) {
      IdeWebFileSaveResult.saved => const {'saved': true},
      IdeWebFileSaveResult.cancelled => throw const BridgeException(
        BridgeErrorCode.cancelled,
      ),
      IdeWebFileSaveResult.failed => throw const BridgeException(
        BridgeErrorCode.failed,
      ),
    };
  }

  Future<void> _confirm(IdeWebPrompt prompt, bool Function() current) async {
    final agreed = await _prompter.confirm(prompt);
    if (!agreed || !current() || !_isActive()) {
      throw const BridgeException(BridgeErrorCode.cancelled);
    }
  }

  Future<void> _requireSession() async {
    if (!await _isSessionCurrent()) {
      throw const BridgeException(BridgeErrorCode.cancelled);
    }
  }

  void _limit(String key, int limit, Duration window) {
    if (!_limiter.allow(key, limit: limit, window: window)) {
      throw const BridgeException(BridgeErrorCode.rateLimited);
    }
  }

  /// Một việc ghi / ký một lúc, chờ tối đa [maxQueued].
  Future<T> _exclusive<T>(
    bool Function() current,
    Future<T> Function() action,
  ) async {
    if (_running) {
      if (_queue.length >= maxQueued) {
        throw const BridgeException(BridgeErrorCode.busy);
      }
      final turn = Completer<bool>();
      _queue.add(turn);
      if (!await turn.future) {
        throw const BridgeException(BridgeErrorCode.cancelled);
      }
    } else {
      _running = true;
    }
    try {
      if (!current() || !_isActive()) {
        throw const BridgeException(BridgeErrorCode.cancelled);
      }
      return await action();
    } finally {
      if (_queue.isEmpty) {
        _running = false;
      } else {
        // Giữ [_running]: lượt được trao thẳng cho việc kế tiếp.
        _queue.removeFirst().complete(true);
      }
    }
  }

  String _cancelledReply(String? id) =>
      _error(id, null, BridgeErrorCode.cancelled);

  String _error(String? id, BridgeMethod? method, BridgeErrorCode code) {
    _log?.call(method?.value ?? '-', code.value);
    return encodeBridgeError(id, code, _message(code));
  }

  static BridgeErrorCode _keyError(String code) {
    for (final value in BridgeErrorCode.values) {
      if (value.value == code) return value;
    }
    return BridgeErrorCode.failed;
  }

  static String _message(BridgeErrorCode code) => switch (code) {
    BridgeErrorCode.badRequest => tr(
      'Yêu cầu không đúng dạng.',
      'Malformed request.',
    ),
    BridgeErrorCode.unsupportedVersion => tr(
      'Phiên bản cầu nối không được hỗ trợ.',
      'Unsupported bridge version.',
    ),
    BridgeErrorCode.unknownMethod => tr(
      'Không có chức năng này.',
      'Unknown method.',
    ),
    BridgeErrorCode.forbiddenOrigin => tr(
      'Trang này không được phép.',
      'This page is not allowed.',
    ),
    BridgeErrorCode.busy => tr('Đang có việc khác.', 'Busy.'),
    BridgeErrorCode.rateLimited => tr(
      'Gọi quá nhiều lần, thử lại sau.',
      'Too many requests, try again later.',
    ),
    BridgeErrorCode.cancelled => tr('Đã huỷ.', 'Cancelled.'),
    BridgeErrorCode.notEnrolled => tr(
      'Máy chưa đặt vân tay hoặc khuôn mặt.',
      'No biometrics enrolled.',
    ),
    BridgeErrorCode.keyMissing => tr(
      'Không có khoá này trên máy.',
      'No such key on this device.',
    ),
    BridgeErrorCode.keyInvalid => tr(
      'Khoá đã mất hiệu lực, cần đăng ký lại.',
      'The key is no longer valid, register again.',
    ),
    BridgeErrorCode.unsupported => tr('Không hỗ trợ.', 'Not supported.'),
    BridgeErrorCode.tooLarge => tr('Dữ liệu quá lớn.', 'Too large.'),
    BridgeErrorCode.failed => tr('Chưa thực hiện được.', 'Failed.'),
  };
}
