/// Quyền dùng IDE do máy chủ chat báo (`access` trong `GET /ide/status`).
final class IdeServerAccess {
  const IdeServerAccess({required this.allowed, this.reason = ''});

  final bool allowed;

  /// `disabled | mfa_required | mfa_stale | email_unverified | unavailable`
  /// hoặc lý do khác (máy chủ mới hơn app).
  final String reason;
}

/// `GET /ide/status`. Máy chủ cũ chỉ trả `connected`: [enabled] và [access]
/// là `null`, app giữ hành vi cũ.
final class IdeServerStatus {
  const IdeServerStatus({required this.connected, this.enabled, this.access});

  final bool connected;
  final bool? enabled;
  final IdeServerAccess? access;

  /// Đọc phần `data` của `GET /ide/status`; trường sai kiểu coi như thiếu.
  factory IdeServerStatus.fromJson(Map<String, Object?> json) {
    final enabled = json['enabled'];
    final access = json['access'];
    IdeServerAccess? parsed;
    if (access is Map && access['allowed'] is bool) {
      final reason = access['reason'];
      parsed = IdeServerAccess(
        allowed: access['allowed']! as bool,
        reason: reason is String ? reason.trim() : '',
      );
    }
    return IdeServerStatus(
      connected: json['connected'] == true,
      enabled: enabled is bool ? enabled : null,
      access: parsed,
    );
  }

  /// Lý do máy chủ chặn IDE; `null` = không chặn hoặc máy chủ cũ không báo.
  String? get deniedReason {
    final a = access;
    if (a != null && !a.allowed) {
      return a.reason.isEmpty ? 'unavailable' : a.reason;
    }
    if (enabled == false) return 'disabled';
    return null;
  }
}

/// Mã lỗi máy chủ chat khi từ chối IDE (HTTP 403, `details.reason`).
const ideAccessDeniedCode = 'IDE_ACCESS_DENIED';

/// Lời giải thích trên màn khoá IDE theo lý do máy chủ trả.
String ideAccessDeniedText(String reason) => switch (reason) {
  'disabled' => 'IDE đang tạm tắt trên máy chủ này.',
  'mfa_required' =>
    'Bật xác thực 2 lớp cho tài khoản để dùng IDE trên điện thoại.',
  'mfa_stale' => 'Đăng nhập lại, có bước xác thực 2 lớp, để tiếp tục dùng IDE.',
  'email_unverified' => 'Xác minh email của tài khoản để dùng IDE.',
  _ => 'Chưa kiểm được quyền dùng IDE. Thử lại sau.',
};
