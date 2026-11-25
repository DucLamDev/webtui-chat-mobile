import 'dart:typed_data';

import '../../../core/result/result.dart';
import 'ide_web_device_key.dart';
import 'ide_web_file.dart';
import 'ide_web_launch.dart';
import 'ide_web_owner.dart';

abstract interface class IdeWebRepository {
  Future<Result<IdeWebLaunch>> launch(IdeWebLaunchRequest request);

  Future<Result<IdeWebEntry>> complete({
    required String launchId,
    required String code,
    required String state,
    required String codeVerifier,
  });

  Future<Result<void>> cancel(String launchId);

  Future<Result<void>> endCurrentSession();
}

/// Lượt đang chờ trình duyệt (mỗi máy một lượt).
abstract interface class IdeWebPendingStore {
  Future<PendingIdeWebLaunch?> read();

  Future<void> write(PendingIdeWebLaunch launch);

  Future<void> clear();
}

/// Siêu dữ liệu khoá của một người; đổi người thì bản ghi cũ bị xoá cùng khoá.
abstract interface class IdeWebKeyMetadataStore {
  Future<IdeWebKeyRecord?> read();

  Future<void> write(IdeWebKeyRecord record);

  Future<void> clear();
}

final class IdeWebKeyRecord {
  const IdeWebKeyRecord({required this.ownerDigest, required this.keys});

  final String ownerDigest;
  final List<IdeWebDeviceKey> keys;
}

/// Lỗi chip khoá: `cancelled | not_enrolled | key_missing | key_invalid |
/// unsupported | failed`.
final class IdeWebKeyException implements Exception {
  const IdeWebKeyException(this.code);

  final String code;

  @override
  String toString() => 'IdeWebKeyException($code)';
}

final class IdeWebCreatedKey {
  const IdeWebCreatedKey({required this.publicKey, required this.hardware});

  /// SPKI DER base64url không đệm.
  final String publicKey;

  /// `strongbox | tee | secure_enclave`.
  final String hardware;
}

/// Sinh trắc mạnh của máy, loại duy nhất khoá sinh trắc chấp nhận.
final class IdeWebBiometricState {
  const IdeWebBiometricState({
    required this.available,
    required this.enrolled,
    required this.strong,
  });

  static const none = IdeWebBiometricState(
    available: false,
    enrolled: false,
    strong: false,
  );

  /// Máy có cảm biến dùng được.
  final bool available;

  /// Đã đăng ký vân tay / khuôn mặt.
  final bool enrolled;

  /// Cảm biến thuộc loại mạnh.
  final bool strong;
}

/// Chip khoá của máy (gọi kênh native).
abstract interface class IdeWebKeyChip {
  Future<IdeWebCreatedKey> create(IdeWebKeyPurpose purpose, String alias);

  /// Chữ ký ECDSA DER trên SHA-256([data]).
  Future<Uint8List> sign(
    IdeWebKeyPurpose purpose,
    String alias,
    Uint8List data,
  );

  Future<bool> isUsable(IdeWebKeyPurpose purpose, String alias);

  Future<void> delete(IdeWebKeyPurpose purpose, String alias);

  Future<IdeWebBiometricState> biometricState();
}

/// Trình duyệt hệ thống.
sealed class IdeWebBrowserResult {
  const IdeWebBrowserResult();
}

/// iOS: phiên đăng nhập trả thẳng callback.
final class IdeWebBrowserCallback extends IdeWebBrowserResult {
  const IdeWebBrowserCallback(this.uri);

  final Uri uri;
}

/// Android: kết quả về sau bằng deep link.
final class IdeWebBrowserOpened extends IdeWebBrowserResult {
  const IdeWebBrowserOpened();
}

final class IdeWebBrowserCancelled extends IdeWebBrowserResult {
  const IdeWebBrowserCancelled();
}

final class IdeWebBrowserFailed extends IdeWebBrowserResult {
  const IdeWebBrowserFailed();
}

abstract interface class IdeWebBrowser {
  Future<IdeWebBrowserResult> authenticate(Uri url, {required String scheme});
}

enum IdeWebFileSaveResult { saved, cancelled, failed }

/// Lưu tệp vào chỗ người dùng lấy được; tệp tạm xoá ở [disposeTemp].
abstract interface class IdeWebFileSaver {
  Future<IdeWebFileSaveResult> save(
    IdeWebFile file, {
    required Future<bool> Function() confirmOpen,
  });

  Future<void> disposeTemp();
}

/// Xoá cookie, bộ nhớ, cache, IndexedDB, service worker của WebView.
abstract interface class IdeWebDataCleaner {
  Future<void> clearAll();
}

/// Ghi nhớ bền: WebView đang giữ dữ liệu của ai, hay đang chờ xoá.
abstract interface class IdeWebDataMarkerStore {
  Future<IdeWebDataMarker?> read();

  Future<void> write(IdeWebDataMarker marker);

  Future<void> clear();
}

final class IdeWebDataMarker {
  const IdeWebDataMarker.usedBy(String this.ownerDigest) : needsClear = false;
  const IdeWebDataMarker.needsClear() : ownerDigest = null, needsClear = true;

  final String? ownerDigest;
  final bool needsClear;

  bool isUsedBy(IdeWebOwner owner) => ownerDigest == owner.digest;
}

/// Quyền micro của hệ điều hành (chỉ xin khi trang gọi và app đã đồng ý).
abstract interface class IdeWebMicPermission {
  Future<bool> request();
}
