/// Mã lỗi của bước xác thực hai lớp khi đăng nhập.
abstract final class LoginMfaErrorCode {
  /// Đăng nhập (mật khẩu, SSO, xác minh email) cần thêm bước xác thực hai lớp.
  static const required = 'MFA_REQUIRED';
  static const invalidCode = 'MFA_INVALID_CODE';
  static const challengeExpired = 'MFA_CHALLENGE_EXPIRED';
  static const tooManyAttempts = 'MFA_TOO_MANY_ATTEMPTS';
  static const methodNotAvailable = 'MFA_METHOD_NOT_AVAILABLE';

  /// Mã nội bộ của app: cách xác thực này chưa dùng được trên ứng dụng.
  static const methodUnsupported = 'MFA_METHOD_UNSUPPORTED';
}

enum LoginMfaMethod {
  totp('totp'),
  recoveryCode('recovery_code'),
  passkey('passkey');

  const LoginMfaMethod(this.apiValue);

  final String apiValue;

  /// App nhập được mã cho cách này (passkey cần WebAuthn, ứng dụng chưa có).
  bool get supportedInApp => this != LoginMfaMethod.passkey;

  static LoginMfaMethod? fromApi(Object? value) {
    final text = value?.toString().trim().toLowerCase();
    for (final method in values) {
      if (method.apiValue == text) return method;
    }
    return null;
  }
}

/// Lượt chờ bước xác thực hai lớp sau `MFA_REQUIRED`.
///
/// `mfaToken` chỉ giữ trong bộ nhớ của lượt này: không ghi đĩa, không đưa vào
/// đường dẫn điều hướng, không log.
final class LoginMfaChallenge {
  const LoginMfaChallenge({
    required this.mfaToken,
    required this.methods,
    required this.expiresAt,
    required this.instanceScopeId,
    this.remember = true,
  });

  /// Đọc `error.details` của lỗi `MFA_REQUIRED`. Thiếu token hoặc không có cách
  /// xác thực nào thì trả null.
  static LoginMfaChallenge? fromDetails(
    Map<String, Object?> details, {
    required String instanceScopeId,
    required bool remember,
    required DateTime now,
  }) {
    final token = details['mfa_token']?.toString().trim() ?? '';
    if (token.isEmpty || token.length > 512 || instanceScopeId.isEmpty) {
      return null;
    }
    final rawMethods = details['methods'];
    final methods = <LoginMfaMethod>[];
    if (rawMethods is List) {
      for (final value in rawMethods) {
        final method = LoginMfaMethod.fromApi(value);
        if (method != null && !methods.contains(method)) methods.add(method);
      }
    }
    if (methods.isEmpty) return null;
    final rawExpires = details['expires_in'];
    final parsed = rawExpires is num
        ? rawExpires.toInt()
        : int.tryParse('${rawExpires ?? ''}');
    // Máy chủ cấp 5 phút; giá trị lạ thì dùng mặc định để không giữ lượt quá lâu.
    final seconds = parsed == null || parsed <= 0 || parsed > 900
        ? 300
        : parsed;
    return LoginMfaChallenge(
      mfaToken: token,
      methods: List.unmodifiable(methods),
      expiresAt: now.toUtc().add(Duration(seconds: seconds)),
      instanceScopeId: instanceScopeId,
      remember: remember,
    );
  }

  final String mfaToken;
  final List<LoginMfaMethod> methods;
  final DateTime expiresAt;

  /// Máy chủ đang hoạt động lúc nhận lượt này; đổi máy chủ thì lượt mất hiệu lực.
  final String instanceScopeId;

  /// Giữ đúng lựa chọn "Ghi nhớ đăng nhập" của bước trước.
  final bool remember;

  /// Các cách nhập được trên app, theo thứ tự ưu tiên.
  List<LoginMfaMethod> get usableMethods => [
    for (final method in const [
      LoginMfaMethod.totp,
      LoginMfaMethod.recoveryCode,
    ])
      if (methods.contains(method)) method,
  ];

  bool get onlyPasskey =>
      usableMethods.isEmpty && methods.contains(LoginMfaMethod.passkey);

  int secondsLeft(DateTime now) {
    final left = expiresAt.difference(now.toUtc());
    if (left.isNegative) return 0;
    return (left.inMilliseconds / 1000).ceil();
  }

  bool isExpired(DateTime now) => secondsLeft(now) <= 0;

  @override
  String toString() => 'LoginMfaChallenge(<redacted>)';
}
