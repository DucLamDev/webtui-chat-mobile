import 'dart:convert';

/// Đọc claim `sub` (id người dùng) trong access token JWT đang giữ trên máy.
/// Chỉ dùng để so khớp cục bộ (vd. bỏ qua cuộc gọi do chính mình tạo), không
/// thay cho kiểm quyền ở máy chủ. Không phải JWT / thiếu `sub` → null.
String? accessTokenUserId(String? token) {
  final parts = token?.trim().split('.');
  if (parts == null || parts.length != 3 || parts[1].isEmpty) {
    return null;
  }
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is Map) {
      final sub = payload['sub'];
      if (sub is String && sub.trim().isNotEmpty) {
        return sub.trim();
      }
    }
  } on Object {
    return null;
  }
  return null;
}

/// Id người dùng đang đăng nhập: lấy từ phiên lưu sẵn trên máy (access
/// token), không cần mạng. Chỉ khi không đọc được mới hỏi máy chủ (hồ sơ).
final class ResolveCurrentUserIdUseCase {
  const ResolveCurrentUserIdUseCase({
    required Future<String?> Function() readAccessToken,
    Future<String?> Function()? loadProfileUserId,
  }) : _readAccessToken = readAccessToken,
       _loadProfileUserId = loadProfileUserId;

  final Future<String?> Function() _readAccessToken;
  final Future<String?> Function()? _loadProfileUserId;

  Future<String?> execute() async {
    try {
      final fromToken = accessTokenUserId(await _readAccessToken());
      if (fromToken != null) return fromToken;
    } on Object {
      // Kho token lỗi: thử hồ sơ bên dưới.
    }
    final loadProfile = _loadProfileUserId;
    if (loadProfile == null) return null;
    try {
      final id = (await loadProfile())?.trim() ?? '';
      return id.isEmpty ? null : id;
    } on Object {
      return null;
    }
  }
}
