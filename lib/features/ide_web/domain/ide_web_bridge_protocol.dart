import 'dart:convert';

/// Mã lỗi cầu nối v1 (trang IDE đọc).
enum BridgeErrorCode {
  badRequest('bad_request'),
  unsupportedVersion('unsupported_version'),
  unknownMethod('unknown_method'),
  forbiddenOrigin('forbidden_origin'),
  busy('busy'),
  rateLimited('rate_limited'),
  cancelled('cancelled'),
  notEnrolled('not_enrolled'),
  keyMissing('key_missing'),
  keyInvalid('key_invalid'),
  unsupported('unsupported'),
  tooLarge('too_large'),
  failed('failed');

  const BridgeErrorCode(this.value);

  final String value;
}

final class BridgeException implements Exception {
  const BridgeException(this.code);

  final BridgeErrorCode code;

  @override
  String toString() => 'BridgeException(${code.value})';
}

enum BridgeMethod {
  appInfo('app.info', {}),
  deviceStatus('device.status', {}),
  deviceCreate('device.create', {'purpose', 'challenge'}),
  deviceSign('device.sign', {'key_id', 'challenge'}),
  deviceDelete('device.delete', {'key_id'}),
  fileSave('file.save', {'name', 'mime', 'data_base64'}),
  appClose('app.close', {});

  const BridgeMethod(this.value, this.params);

  final String value;

  /// Tập khoá bắt buộc và duy nhất của `params`; mọi giá trị là chuỗi.
  final Set<String> params;

  static BridgeMethod? parse(String value) {
    for (final method in values) {
      if (method.value == value) return method;
    }
    return null;
  }
}

/// Trần thân một yêu cầu (byte UTF-8).
const bridgeMaxBytes = 64 * 1024;
const bridgeMaxFileBytes = 14 * 1024 * 1024;

final class BridgeRequest {
  const BridgeRequest({
    required this.id,
    required this.method,
    required this.params,
  });

  final String id;
  final BridgeMethod method;
  final Map<String, String> params;

  @override
  String toString() => 'BridgeRequest(${method.value})';
}

/// Kết quả đọc yêu cầu: [request], hoặc [error] kèm [id] (nếu đã đọc được).
final class BridgeParseResult {
  const BridgeParseResult.ok(BridgeRequest this.request)
    : error = null,
      id = null;
  const BridgeParseResult.error(BridgeErrorCode this.error, {this.id})
    : request = null;

  final BridgeRequest? request;
  final BridgeErrorCode? error;
  final String? id;
}

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
const _envelopeKeys = {'v', 'id', 'method', 'params'};

/// Thứ tự kiểm cố định: kích thước, JSON, kiểu, phiên bản, `id` (kèm [idUsed]),
/// hàm, tham số. [claimId] được gọi đúng một lần khi `id` hợp lệ; trả `false`
/// nếu `id` đã dùng.
BridgeParseResult parseBridgeRequest(
  String raw, {
  required bool Function(String id) claimId,
}) {
  // Số đơn vị mã không bao giờ lớn hơn số byte UTF-8: chặn sớm, khỏi mã hoá.
  if (raw.length > bridgeMaxFileBytes) {
    return const BridgeParseResult.error(BridgeErrorCode.tooLarge);
  }
  final size = utf8.encode(raw).length;
  final isLarge = size > bridgeMaxBytes;
  if (size > bridgeMaxFileBytes || (isLarge && !raw.contains('file.save'))) {
    return const BridgeParseResult.error(BridgeErrorCode.tooLarge);
  }
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException {
    return const BridgeParseResult.error(BridgeErrorCode.badRequest);
  }
  if (json is! Map<String, dynamic> ||
      json.keys.any((key) => !_envelopeKeys.contains(key))) {
    return const BridgeParseResult.error(BridgeErrorCode.badRequest);
  }
  final rawId = json['id'];
  final id = rawId is String && _idPattern.hasMatch(rawId) ? rawId : null;
  final methodName = json['method'];
  final rawParams = json['params'];
  if (json['v'] is! int ||
      rawId is! String ||
      methodName is! String ||
      (rawParams != null && rawParams is! Map<String, dynamic>)) {
    return BridgeParseResult.error(BridgeErrorCode.badRequest, id: id);
  }
  if (isLarge && methodName != BridgeMethod.fileSave.value) {
    return BridgeParseResult.error(BridgeErrorCode.tooLarge, id: id);
  }
  if (json['v'] != 1) {
    return BridgeParseResult.error(BridgeErrorCode.unsupportedVersion, id: id);
  }
  if (id == null || !claimId(id)) {
    return BridgeParseResult.error(BridgeErrorCode.badRequest, id: id);
  }
  final method = BridgeMethod.parse(methodName);
  if (method == null) {
    return BridgeParseResult.error(BridgeErrorCode.unknownMethod, id: id);
  }
  final params = rawParams as Map<String, dynamic>? ?? const {};
  if (params.length != method.params.length ||
      method.params.any((key) => params[key] is! String)) {
    return BridgeParseResult.error(BridgeErrorCode.badRequest, id: id);
  }
  return BridgeParseResult.ok(
    BridgeRequest(
      id: id,
      method: method,
      params: {for (final key in method.params) key: params[key] as String},
    ),
  );
}

final _idField = RegExp(r'"id"\s*:\s*"([A-Za-z0-9_-]{1,64})"');

/// Đọc `id` từ phần đầu yêu cầu chưa đọc được (quá cỡ, hỏng, sai origin), chỉ để
/// câu trả lời lỗi mang đúng `id` của trang.
String? peekBridgeRequestId(String raw) => _idField
    .firstMatch(raw.length > 512 ? raw.substring(0, 512) : raw)
    ?.group(1);

String encodeBridgeResult(String id, Map<String, Object?> result) =>
    jsonEncode({'v': 1, 'id': id, 'ok': true, 'result': result});

String encodeBridgeError(String? id, BridgeErrorCode code, String message) =>
    jsonEncode({
      'v': 1,
      'id': id ?? '',
      'ok': false,
      'error': {'code': code.value, 'message': message},
    });

enum BridgeEvent {
  background('app.background'),
  foreground('app.foreground'),
  closing('session.closing');

  const BridgeEvent(this.value);

  final String value;
}

String encodeBridgeEvent(BridgeEvent event) =>
    jsonEncode({'v': 1, 'event': event.value, 'data': <String, Object?>{}});
