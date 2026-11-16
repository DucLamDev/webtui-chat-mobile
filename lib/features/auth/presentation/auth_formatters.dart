/// Định dạng hiển thị dùng chung cho các màn phiên / thiết bị / QR.
library;

import '../../../l10n/app_strings.dart';

String _two(int value) => value.toString().padLeft(2, '0');

/// `14:05 · 09/11/2026` theo giờ máy.
String formatAuthDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)} · '
      '${_two(local.day)}/${_two(local.month)}/${local.year}';
}

/// "Hoạt động lần cuối": vừa xong / N phút trước / N giờ trước / ngày giờ.
String formatLastActive(DateTime value, DateTime now) {
  final difference = now.toUtc().difference(value.toUtc());
  if (difference.inSeconds < 60) {
    return tr('vừa xong', 'just now');
  }
  if (difference.inMinutes < 60) {
    return tr(
      '${difference.inMinutes} phút trước',
      '${difference.inMinutes} min ago',
    );
  }
  if (difference.inHours < 24) {
    return tr('${difference.inHours} giờ trước', '${difference.inHours} h ago');
  }
  return formatAuthDateTime(value);
}

/// Thời gian còn lại dạng `m:ss` (0:00 khi đã quá).
String formatCountdown(Duration remaining) {
  final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
  return '${seconds ~/ 60}:${_two(seconds % 60)}';
}

/// Tóm tắt User-Agent cho người đọc: "Chrome trên Windows".
String describeUserAgent(String? userAgent) {
  final value = userAgent?.trim() ?? '';
  if (value.isEmpty) {
    return tr('Trình duyệt không xác định', 'Unknown browser');
  }
  final lower = value.toLowerCase();
  final browser = lower.contains('edg/')
      ? 'Edge'
      : lower.contains('opr/') || lower.contains('opera')
      ? 'Opera'
      : lower.contains('firefox/')
      ? 'Firefox'
      : lower.contains('chrome/') || lower.contains('crios/')
      ? 'Chrome'
      : lower.contains('safari/')
      ? 'Safari'
      : null;
  final system = lower.contains('windows')
      ? 'Windows'
      : lower.contains('iphone') || lower.contains('ipad')
      ? 'iOS'
      : lower.contains('mac os') || lower.contains('macintosh')
      ? 'macOS'
      : lower.contains('android')
      ? 'Android'
      : lower.contains('linux')
      ? 'Linux'
      : null;
  if (browser != null && system != null) {
    return tr('$browser trên $system', '$browser on $system');
  }
  if (browser != null || system != null) {
    return browser ?? system!;
  }
  return value.length > 60 ? '${value.substring(0, 60)}…' : value;
}

/// Tên cách đăng nhập của một phiên.
String authMethodLabel(String? method) {
  return switch (method?.trim().toLowerCase()) {
    'password' => tr('Mật khẩu', 'Password'),
    'register' => tr('Đăng ký mới', 'New registration'),
    'oidc' => 'SSO',
    'qr' => tr('Mã QR', 'QR code'),
    'email_code' => tr('Mã email', 'Email code'),
    'invite' => tr('Lời mời', 'Invitation'),
    _ => '',
  };
}
