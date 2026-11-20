import 'dart:async';

import '../data/ide_device_key_store.dart';
import '../data/ide_pair_api.dart';
import '../domain/ide_device_credentials.dart';
import '../domain/ide_device_security.dart';
import '../domain/ide_pair_code.dart';

enum IdePairOutcome {
  ok,
  rejected,
  expired,
  invalid,
  offline,
  rateLimited,
  timedOut,
  noLockScreen,
  biometricRequired,
  unsupported,
  failed,
}

/// Gắn máy: sinh khoá Ed25519 + khoá xác nhận, `POST pair`, hỏi `GET pair/{id}`
/// 2 s/lần tối đa 2 phút, lưu khoá khi IDE bấm Xác nhận.
final class IdePairingService {
  IdePairingService({
    required IdePairApi api,
    required IdeDeviceKeyStore keys,
    required IdeDeviceSecurity security,
    required Future<String?> Function() currentUserId,
    required String serverScopeId,
    void Function()? onPaired,
    String? Function()? sessionToken,
    this.pollEvery = const Duration(seconds: 2),
    this.maxWait = const Duration(minutes: 2),
  }) : _api = api,
       _keys = keys,
       _security = security,
       _currentUserId = currentUserId,
       _serverScopeId = serverScopeId,
       _onPaired = onPaired,
       _sessionToken = sessionToken;

  /// Mẫu mã máy IDE cấp (khớp máy chủ chat, header `X-IDE-Device`).
  static final devicePattern = RegExp(r'^d_[A-Za-z0-9_-]{8,64}$');

  final IdePairApi _api;
  final IdeDeviceKeyStore _keys;
  final IdeDeviceSecurity _security;
  final Future<String?> Function() _currentUserId;
  final String _serverScopeId;

  /// Gọi khi đã lưu bản ghi gắn mới (kể cả khi màn gắn máy đã đóng).
  final void Function()? _onPaired;

  /// Token phiên chat hiện tại: đổi giữa chừng (đăng xuất / người khác đăng
  /// nhập) thì không lưu kết quả gắn.
  final String? Function()? _sessionToken;
  final Duration pollEvery;
  final Duration maxWait;

  static const maxNameLength = 60;

  /// [onWaiting] gọi khi đã gửi yêu cầu, đang chờ bấm Xác nhận trên máy tính.
  /// [isCancelled] để màn hình dừng vòng hỏi.
  Future<IdePairOutcome> pair({
    required IdePairCode code,
    required String deviceName,
    void Function()? onWaiting,
    bool Function()? isCancelled,
  }) async {
    final name = deviceName.trim().isEmpty ? 'Điện thoại' : deviceName.trim();
    final clipped = name.runes.length > maxNameLength
        ? String.fromCharCodes(name.runes.take(maxNameLength))
        : name;
    final session = _sessionToken?.call();
    final userId = await _currentUserId();
    if (userId == null || userId.isEmpty) return IdePairOutcome.failed;

    final String seed;
    final String pubkey;
    try {
      seed = await IdeDeviceKeyStore.newSeed();
      pubkey = await IdeDeviceKeyStore.publicKeyBase64(seed);
    } on Object {
      return IdePairOutcome.failed;
    }
    final alias = IdeDeviceCredentials.newStepKeyAlias(code.instanceId);
    String stepPubkey;
    try {
      stepPubkey = await _security.createStepKey(alias);
    } on StepKeyException catch (error) {
      await _deleteKey(alias);
      return switch (error.code) {
        'notEnrolled' => IdePairOutcome.noLockScreen,
        'biometricRequired' => IdePairOutcome.biometricRequired,
        'unsupported' => IdePairOutcome.unsupported,
        _ => IdePairOutcome.failed,
      };
    }

    IdePairOutcome outcome;
    try {
      outcome = await _register(
        code: code,
        userId: userId,
        session: session,
        seed: seed,
        pubkey: pubkey,
        alias: alias,
        stepPubkey: stepPubkey,
        deviceName: clipped,
        onWaiting: onWaiting,
        isCancelled: isCancelled,
      );
    } on Object {
      // Kho bảo mật từ chối ghi...: không để màn gắn quay mãi.
      outcome = IdePairOutcome.failed;
    }
    // Gắn hỏng: bỏ khoá vừa tạo, giữ nguyên khoá của lần gắn đang dùng.
    if (outcome != IdePairOutcome.ok) await _deleteKey(alias);
    return outcome;
  }

  Future<IdePairOutcome> _register({
    required IdePairCode code,
    required String userId,
    required String? session,
    required String seed,
    required String pubkey,
    required String alias,
    required String stepPubkey,
    required String deviceName,
    void Function()? onWaiting,
    bool Function()? isCancelled,
  }) async {
    String pairId;
    try {
      pairId = await _api.requestPair(
        code: code.code,
        pubkey: pubkey,
        stepPubkey: stepPubkey,
        deviceName: deviceName,
      );
    } on IdePairException catch (error) {
      return _fromError(error);
    }
    onWaiting?.call();

    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) return IdePairOutcome.failed;
      try {
        final poll = await _api.poll(pairId);
        switch (poll.status) {
          case IdePairRemoteStatus.ok:
            final deviceId = poll.deviceId;
            if (deviceId == null || !devicePattern.hasMatch(deviceId)) {
              return IdePairOutcome.failed;
            }
            // Đăng xuất / đổi người trong lúc chờ: không lưu khoá cho phiên cũ.
            if (_sessionToken?.call() != session ||
                await _currentUserId() != userId) {
              return IdePairOutcome.failed;
            }
            final previous = await _keys.loadAny();
            await _keys.save(
              IdeDeviceCredentials(
                instanceId: code.instanceId,
                chatUserId: userId,
                deviceId: deviceId,
                seed: seed,
                serverScope: _serverScopeId,
                stepAlias: alias,
              ),
            );
            // Bản ghi cũ (một chỗ cất) đã bị thay: khoá xác nhận của nó vô dụng.
            final oldAlias = previous?.stepKeyAlias;
            if (oldAlias != null && oldAlias != alias) {
              await _deleteKey(oldAlias);
            }
            _onPaired?.call();
            return IdePairOutcome.ok;
          case IdePairRemoteStatus.rejected:
            return IdePairOutcome.rejected;
          case IdePairRemoteStatus.expired:
            return IdePairOutcome.expired;
          case IdePairRemoteStatus.invalid:
            return IdePairOutcome.invalid;
          case IdePairRemoteStatus.pending:
            break;
        }
      } on IdePairException catch (error) {
        // Lỗi mạng thoáng qua: hỏi tiếp tới hết hạn; lỗi rõ ràng thì dừng.
        if (error.kind != IdePairErrorKind.other) return _fromError(error);
      }
      await Future<void>.delayed(pollEvery);
    }
    return IdePairOutcome.timedOut;
  }

  /// IDE báo gỡ máy [deviceId]: xoá bản ghi và khoá xác nhận nếu bản ghi đang
  /// cất còn là máy đó (stream cũ đóng sau khi đã gắn lại thì giữ bản ghi mới).
  /// Trả `true` nếu đã xoá.
  Future<bool> forgetRevokedDevice(String deviceId) async {
    if (deviceId.isEmpty) return false;
    final stored = await _keys.loadAny();
    if (stored == null || stored.deviceId != deviceId) return false;
    await _keys.clear();
    await _deleteKey(stored.stepKeyAlias);
    return true;
  }

  Future<void> _deleteKey(String alias) async {
    try {
      await _security.deleteStepKey(alias);
    } on StepKeyException {
      // Không xoá được thì thôi: khoá không có bản ghi gắn nào trỏ tới.
    }
  }

  static IdePairOutcome _fromError(IdePairException error) =>
      switch (error.kind) {
        IdePairErrorKind.offline => IdePairOutcome.offline,
        IdePairErrorKind.rateLimited => IdePairOutcome.rateLimited,
        IdePairErrorKind.invalid => IdePairOutcome.invalid,
        IdePairErrorKind.other => IdePairOutcome.failed,
      };
}
