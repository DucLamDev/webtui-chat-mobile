/// Nội dung mã QR đăng nhập máy tính (Lõi 2.2):
/// `vpsttt-login:v1?d=<domain>&c=<challenge_id>&s=<secret>`.
///
/// Dữ liệu QR là đầu vào không tin cậy: chỉ nhận đúng tiền tố, đúng ba khoá,
/// không lặp, không khoá lạ, ký tự trong tập cho phép. `challengeId` đi vào
/// đường dẫn API nên chặn mọi ký tự ngoài `[A-Za-z0-9_-]`.
final class QrLoginPayload {
  const QrLoginPayload._({
    required this.domain,
    required this.challengeId,
    required this.secret,
  });

  static const prefix = 'vpsttt-login:v1?';
  static const _maxLength = 1024;
  static final _domainPattern = RegExp(
    r'^(?=.{1,253}(?::\d{1,5})?$)'
    r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?'
    r'(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*'
    r'(?::(\d{1,5}))?$',
  );
  static final _challengePattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');
  static final _secretPattern = RegExp(r'^[A-Za-z0-9._~-]{16,512}$');

  /// Tên miền máy chủ (chữ thường, có thể kèm `:port`).
  final String domain;
  final String challengeId;
  final String secret;

  /// Phần host của [domain] (bỏ cổng).
  String get host {
    final index = domain.indexOf(':');
    return index < 0 ? domain : domain.substring(0, index);
  }

  /// Cổng ghi trong mã (null khi không ghi).
  int? get port {
    final index = domain.indexOf(':');
    return index < 0 ? null : int.tryParse(domain.substring(index + 1));
  }

  /// Trả null khi [raw] không phải mã đăng nhập hợp lệ.
  static QrLoginPayload? tryParse(String raw) {
    final value = raw.trim();
    if (value.length > _maxLength || !value.startsWith(prefix)) {
      return null;
    }
    final query = value.substring(prefix.length);
    if (query.isEmpty || query.contains('#')) {
      return null;
    }
    final fields = <String, String>{};
    for (final part in query.split('&')) {
      final separator = part.indexOf('=');
      if (separator <= 0) {
        return null;
      }
      final key = part.substring(0, separator);
      final String decoded;
      try {
        decoded = Uri.decodeQueryComponent(part.substring(separator + 1));
      } on ArgumentError {
        return null;
      } on FormatException {
        return null;
      }
      if (!const {'d', 'c', 's'}.contains(key) || fields.containsKey(key)) {
        return null;
      }
      fields[key] = decoded;
    }
    final domain = fields['d']?.trim().toLowerCase() ?? '';
    final challengeId = fields['c'] ?? '';
    final secret = fields['s'] ?? '';
    final domainMatch = _domainPattern.firstMatch(domain);
    if (domainMatch == null ||
        !_challengePattern.hasMatch(challengeId) ||
        !_secretPattern.hasMatch(secret)) {
      return null;
    }
    final portText = domainMatch.group(1);
    if (portText != null) {
      final port = int.parse(portText);
      if (port < 1 || port > 65535) {
        return null;
      }
    }
    return QrLoginPayload._(
      domain: domain,
      challengeId: challengeId,
      secret: secret,
    );
  }

  /// Mã chỉ dùng được với đúng máy chủ đang đăng nhập (so host và cổng).
  bool belongsToServer(Uri serverOrigin) {
    final serverHost = serverOrigin.host.toLowerCase();
    if (serverHost.isEmpty || host != serverHost) {
      return false;
    }
    final codePort = port;
    if (codePort == null) {
      return true;
    }
    final serverPort = serverOrigin.hasPort
        ? serverOrigin.port
        : serverOrigin.scheme == 'http'
        ? 80
        : 443;
    return codePort == serverPort;
  }
}

/// Máy tính đang xin đăng nhập (trả về sau khi quét).
final class QrLoginRequester {
  const QrLoginRequester({
    this.deviceName,
    this.userAgent,
    this.ipAddress,
    this.createdAt,
  });

  final String? deviceName;
  final String? userAgent;
  final String? ipAddress;
  final DateTime? createdAt;
}

/// Kết quả `POST /auth/qr/challenges/{id}/scan`.
final class QrLoginScan {
  const QrLoginScan({
    required this.challengeId,
    required this.status,
    required this.requester,
    this.expiresAt,
  });

  final String challengeId;
  final String status;
  final DateTime? expiresAt;
  final QrLoginRequester requester;
}

/// Mã lỗi máy chủ của luồng QR.
abstract final class QrLoginErrorCode {
  static const notFound = 'QR_CHALLENGE_NOT_FOUND';
  static const taken = 'QR_CHALLENGE_TAKEN';
  static const expired = 'QR_CHALLENGE_EXPIRED';
  static const disabled = 'QR_LOGIN_DISABLED';
  static const rateLimited = 'RATE_LIMITED';
}
