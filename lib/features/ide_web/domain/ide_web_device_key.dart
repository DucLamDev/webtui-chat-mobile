import 'dart:convert';
import 'dart:typed_data';

import 'ide_web_owner.dart';

enum IdeWebKeyPurpose {
  possession('possession', 'p'),
  biometric('biometric', 'b');

  const IdeWebKeyPurpose(this.apiValue, this.aliasCode);

  final String apiValue;
  final String aliasCode;

  static IdeWebKeyPurpose? parse(Object? value) {
    for (final purpose in values) {
      if (purpose.apiValue == value) return purpose;
    }
    return null;
  }
}

/// Siêu dữ liệu một khoá trong chip (khoá riêng không bao giờ ra khỏi chip).
final class IdeWebDeviceKey {
  const IdeWebDeviceKey({
    required this.keyId,
    required this.purpose,
    required this.createdAt,
    this.ready = false,
    this.invalid = false,
  });

  static IdeWebDeviceKey? fromJson(Object? json) {
    if (json is! Map) return null;
    final keyId = json['key_id'];
    final purpose = IdeWebKeyPurpose.parse(json['purpose']);
    final createdAt = json['created_at'];
    final created = createdAt is String ? DateTime.tryParse(createdAt) : null;
    if (keyId is! String ||
        !ideWebKeyIdPattern.hasMatch(keyId) ||
        purpose == null ||
        created == null) {
      return null;
    }
    return IdeWebDeviceKey(
      keyId: keyId,
      purpose: purpose,
      createdAt: created,
      ready: json['ready'] == true,
      invalid: json['invalid'] == true,
    );
  }

  final String keyId;
  final IdeWebKeyPurpose purpose;
  final DateTime createdAt;

  /// Đã tạo và ký đăng ký xong (bản ghi được ghi TRƯỚC khi tạo khoá để lúc
  /// nào cũng tìm lại được khoá mà xoá).
  final bool ready;

  /// Máy báo khoá mất hiệu lực (thêm vân tay / khuôn mặt mới).
  final bool invalid;

  IdeWebDeviceKey copyWith({bool? ready, bool? invalid}) => IdeWebDeviceKey(
    keyId: keyId,
    purpose: purpose,
    createdAt: createdAt,
    ready: ready ?? this.ready,
    invalid: invalid ?? this.invalid,
  );

  Map<String, Object?> toJson() => {
    'key_id': keyId,
    'purpose': purpose.apiValue,
    'created_at': createdAt.toUtc().toIso8601String(),
    'ready': ready,
    'invalid': invalid,
  };
}

final ideWebKeyIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Tên khoá trong chip: gắn với máy chủ + người, trang IDE không bao giờ chọn.
String ideWebKeyAlias({
  required IdeWebOwner owner,
  required IdeWebKeyPurpose purpose,
  required String keyId,
}) => ideWebKeyAliasOfDigest(
  ownerDigest: owner.digest,
  purpose: purpose,
  keyId: keyId,
);

String ideWebKeyAliasOfDigest({
  required String ownerDigest,
  required IdeWebKeyPurpose purpose,
  required String keyId,
}) => 'ideweb.${purpose.aliasCode}.${ownerDigest.substring(0, 24)}.$keyId';

enum IdeWebSigningAction { sign, register }

/// Chuỗi ký do app tự dựng (chống ký hộ chuỗi tuỳ ý của trang).
String ideWebSigningString({
  required IdeWebSigningAction action,
  required IdeWebKeyPurpose purpose,
  required String origin,
  required String keyId,
  required String challenge,
}) => [
  'AppChat-IDE-v1:${action.name}',
  purpose.apiValue,
  origin,
  keyId,
  challenge,
].join('\n');

/// `challenge`: base64url không đệm, giải ra 32–64 byte, dạng chuẩn duy nhất.
bool isIdeWebChallenge(String value) {
  if (value.length < 43 ||
      value.length > 86 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    return false;
  }
  try {
    final bytes = base64Url.decode(base64Url.normalize(value));
    return bytes.length >= 32 &&
        bytes.length <= 64 &&
        ideWebBase64Url(bytes) == value;
  } on FormatException {
    return false;
  }
}

String ideWebBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List ideWebUtf8(String value) => Uint8List.fromList(utf8.encode(value));
