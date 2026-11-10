/// Phiên xác minh email (Lõi 2.6): sau đăng ký `202 verification_required`
/// hoặc đăng nhập gặp `403 EMAIL_VERIFICATION_REQUIRED`.
final class EmailVerificationTicket {
  const EmailVerificationTicket({
    required this.verificationId,
    this.emailHint,
    this.expiresAt,
    this.resendAvailableAt,
  });

  /// Đọc từ `verification{...}` hoặc `error.details`. Thiếu
  /// `verification_id` thì trả null (không thể xác minh).
  static EmailVerificationTicket? fromJson(Map<String, Object?> json) {
    final id = _text(json['verification_id']);
    if (id == null || !_verificationIdPattern.hasMatch(id)) {
      return null;
    }
    return EmailVerificationTicket(
      verificationId: id,
      emailHint: _text(json['email_hint']),
      expiresAt: _date(json['expires_at']),
      resendAvailableAt: _date(json['resend_available_at']),
    );
  }

  static final _verificationIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  final String verificationId;

  /// Email đã che bớt (vd. `l***@congty.vn`).
  final String? emailHint;
  final DateTime? expiresAt;
  final DateTime? resendAvailableAt;

  /// Hai phiếu cùng `verification_id` là cùng một phiên xác minh.
  @override
  bool operator ==(Object other) =>
      other is EmailVerificationTicket &&
      other.verificationId == verificationId;

  @override
  int get hashCode => verificationId.hashCode;

  /// Tham số đường dẫn của màn nhập mã (không chứa bí mật: chỉ id, email đã
  /// che và các mốc thời gian).
  Map<String, String> toQuery() {
    return {
      'vid': verificationId,
      'email': ?emailHint,
      if (expiresAt != null) 'expires': expiresAt!.toUtc().toIso8601String(),
      if (resendAvailableAt != null)
        'resend': resendAvailableAt!.toUtc().toIso8601String(),
    };
  }

  static EmailVerificationTicket? fromQuery(Map<String, String> query) {
    return fromJson({
      'verification_id': query['vid'],
      'email_hint': query['email'],
      'expires_at': query['expires'],
      'resend_available_at': query['resend'],
    });
  }

  EmailVerificationTicket copyWith({
    DateTime? expiresAt,
    DateTime? resendAvailableAt,
    String? emailHint,
  }) {
    return EmailVerificationTicket(
      verificationId: verificationId,
      emailHint: emailHint ?? this.emailHint,
      expiresAt: expiresAt ?? this.expiresAt,
      resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt,
    );
  }
}

/// Mã lỗi máy chủ của luồng email.
abstract final class EmailVerificationErrorCode {
  static const required = 'EMAIL_VERIFICATION_REQUIRED';
  static const codeInvalid = 'EMAIL_CODE_INVALID';
  static const codeLocked = 'EMAIL_CODE_LOCKED';
  static const codeExpired = 'EMAIL_CODE_EXPIRED';
  static const notFound = 'EMAIL_VERIFICATION_NOT_FOUND';
  static const resendTooSoon = 'EMAIL_RESEND_TOO_SOON';
  static const domainNotAllowed = 'EMAIL_DOMAIN_NOT_ALLOWED';
}

/// Đếm ngược nút "Gửi lại mã": tính số giây còn lại tới [availableAt], chặn
/// trong 0..[maxSeconds] để đồng hồ máy lệch không khoá nút quá lâu.
final class ResendCountdown {
  const ResendCountdown({this.availableAt, this.maxSeconds = 300});

  /// Sau `EMAIL_RESEND_TOO_SOON` (`details.retry_after_seconds`).
  factory ResendCountdown.after(
    int seconds, {
    required DateTime now,
    int maxSeconds = 300,
  }) {
    final clamped = seconds.clamp(0, maxSeconds);
    return ResendCountdown(
      availableAt: now.add(Duration(seconds: clamped)),
      maxSeconds: maxSeconds,
    );
  }

  final DateTime? availableAt;
  final int maxSeconds;

  int secondsLeft(DateTime now) {
    final target = availableAt;
    if (target == null) {
      return 0;
    }
    final millis = target.difference(now).inMilliseconds;
    if (millis <= 0) {
      return 0;
    }
    final seconds = (millis / 1000).ceil();
    return seconds > maxSeconds ? maxSeconds : seconds;
  }

  bool canResend(DateTime now) => secondsLeft(now) == 0;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _date(Object? value) {
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text)?.toUtc();
}
