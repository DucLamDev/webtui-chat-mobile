/// Loại địa chỉ: trong màn nhúng, trang đăng nhập / tải tệp của IDE (mở bằng
/// trình duyệt hệ thống), trang ngoài (hỏi), hay chặn.
enum IdeWebUrlClass { internal, authFlow, download, external, blocked }

/// Xử lý một lần điều hướng: cho đi, chặn, chặn rồi hỏi mở ngoài app, chặn rồi
/// mở trang đăng nhập IDE / tải tệp bằng trình duyệt hệ thống (không hỏi).
enum IdeWebNavigation { allow, block, askExternal, openAuth, openDownload }

const _authPrefix = '/appchat/auth/';
const _downloadPrefix = '/appchat/download/';

/// Địa chỉ nào được ở trong WebView: đúng `https://ide.<chat>` cổng 443. Trang
/// đăng nhập / tải tệp nằm trên tên miền riêng của IDE ([authOrigin]).
final class IdeWebHostPolicy {
  IdeWebHostPolicy(Uri baseUri, [Uri? authBaseUri])
    : host = baseUri.host.toLowerCase(),
      origin = 'https://${baseUri.host.toLowerCase()}',
      authHost = authBaseUri?.host.toLowerCase(),
      authOrigin = authBaseUri == null
          ? null
          : 'https://${authBaseUri.host.toLowerCase()}',
      assert(baseUri.scheme == 'https' && baseUri.host.isNotEmpty),
      assert(
        authBaseUri == null ||
            (authBaseUri.scheme == 'https' && authBaseUri.host.isNotEmpty),
      ),
      assert(
        authBaseUri == null ||
            baseUri.host.toLowerCase() != authBaseUri.host.toLowerCase(),
        'Tên miền đăng nhập phải khác tên miền nhúng',
      );

  final String host;

  /// Không có dấu `/` cuối (dùng trong chuỗi ký và cho lớp native).
  final String origin;

  /// Host đăng nhập của IDE (`runtime.ide_web_auth_base_url`); `null` ở chế độ
  /// đăng nhập trong WebView (máy chủ không trả địa chỉ này): khi đó không có
  /// lớp [IdeWebUrlClass.authFlow], đường tải tệp nằm ngay trên host nhúng.
  final String? authHost;
  final String? authOrigin;

  Uri get homeUri => Uri.parse('$origin/appchat/');

  /// Phân loại [uri] đã phân tích. `Uri` của Dart tự gỡ `..` nên khi có chuỗi
  /// gốc hãy dùng [classifyText] để chặn cả đường dẫn đã bị chuẩn hoá.
  IdeWebUrlClass classify(Uri uri) => _classify(uri, rawPathSafe: true);

  IdeWebUrlClass classifyText(String? url) {
    final text = url ?? '';
    final uri = Uri.tryParse(text);
    return uri == null
        ? IdeWebUrlClass.blocked
        : _classify(uri, rawPathSafe: ideWebRawPathIsSafe(text));
  }

  IdeWebUrlClass _classify(Uri uri, {required bool rawPathSafe}) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return IdeWebUrlClass.blocked;
    }
    final uriHost = uri.host.toLowerCase();
    if (uriHost == host) {
      if (uri.port != 443) return IdeWebUrlClass.blocked;
      // Không có host đăng nhập riêng: link tải tệp trên host nhúng vẫn mở
      // bằng trình duyệt hệ thống như link tải cũ.
      if (authHost == null &&
          !uri.hasFragment &&
          rawPathSafe &&
          ideWebPathIsSafe(uri.path) &&
          uri.path.startsWith(_downloadPrefix)) {
        return IdeWebUrlClass.download;
      }
      return IdeWebUrlClass.internal;
    }
    if (authHost != null &&
        uriHost == authHost &&
        uri.port == 443 &&
        !uri.hasFragment &&
        rawPathSafe &&
        ideWebPathIsSafe(uri.path)) {
      if (uri.path.startsWith(_authPrefix)) return IdeWebUrlClass.authFlow;
      if (uri.path.startsWith(_downloadPrefix)) return IdeWebUrlClass.download;
    }
    return IdeWebUrlClass.external;
  }

  bool isInternalText(String? url) =>
      classifyText(url) == IdeWebUrlClass.internal;

  /// Khung phụ ra ngoài địa chỉ IDE luôn bị chặn (Android: gói không báo khung
  /// phụ; IDE phải gửi CSP `frame-src 'none'`). [newWindowAsSubframe]: iOS báo
  /// liên kết mở cửa sổ mới (`target=_blank`) như khung phụ vì không có khung
  /// đích, nên xử lý như khung chính. [blankExpected]: app đang tự tải trang
  /// trống. Trang đăng nhập / tải tệp của IDE mở bằng trình duyệt, không hỏi.
  IdeWebNavigation navigation({
    required String url,
    required bool isMainFrame,
    required bool blankExpected,
    required bool newWindowAsSubframe,
  }) {
    final kind = classifyText(url);
    if (kind == IdeWebUrlClass.internal) return IdeWebNavigation.allow;
    if (isMainFrame && blankExpected && url == 'about:blank') {
      return IdeWebNavigation.allow;
    }
    if (!isMainFrame && !newWindowAsSubframe) return IdeWebNavigation.block;
    return switch (kind) {
      IdeWebUrlClass.authFlow => IdeWebNavigation.openAuth,
      IdeWebUrlClass.download => IdeWebNavigation.openDownload,
      IdeWebUrlClass.external => IdeWebNavigation.askExternal,
      IdeWebUrlClass.internal ||
      IdeWebUrlClass.blocked => IdeWebNavigation.block,
    };
  }

  /// Origin do lớp native báo (cổng mặc định 443 có thể được ghi ra).
  bool isAllowedOrigin(String value) =>
      value == origin || value == '$origin:443';

  /// `enter_url` máy chủ trả: đúng đường cố định, không mang gì trong URL.
  bool isEnterUrl(Uri uri) =>
      classify(uri) == IdeWebUrlClass.internal &&
      uri.path == '/_appchat/enter' &&
      !uri.hasQuery &&
      !uri.hasFragment;

  /// `browser_url` máy chủ trả: trang đăng nhập trên tên miền IDE, cổng 443,
  /// dưới `/appchat/auth/`, có thể có query, không fragment / tài khoản. Chuỗi
  /// gốc phải qua [ideWebRawPathIsSafe] trước khi thành `Uri` (lớp data làm).
  bool isBrowserUrl(Uri uri) => classify(uri) == IdeWebUrlClass.authFlow;
}

/// Đường dẫn trong chuỗi URL gốc (trước khi `Uri` gỡ `.` / `..`) an toàn.
/// Không có ký tự điều khiển, khoảng trắng, `\` ở bất cứ đâu trong chuỗi.
bool ideWebRawPathIsSafe(String raw) {
  for (final unit in raw.codeUnits) {
    if (unit <= 0x20 || unit == 0x7f || unit == 0x5c) return false;
  }
  final scheme = raw.indexOf('://');
  if (scheme < 0) return true;
  final rest = raw.substring(scheme + 3);
  final pathStart = rest.indexOf('/');
  final end = rest.indexOf(RegExp('[?#]'));
  if (pathStart < 0 || (end >= 0 && end < pathStart)) return true;
  return ideWebPathIsSafe(rest.substring(pathStart, end < 0 ? null : end));
}

final _segmentPattern = RegExp(r'^[A-Za-z0-9._~-]+$');

/// Đường dẫn chỉ gồm đoạn chữ / số / `._~-` phân cách bằng đúng một `/`: không
/// `//`, không đoạn `.` / `..`, không mã hoá `%` (chặn `%2e%2e`, `%2f`...).
bool ideWebPathIsSafe(String path) {
  if (!path.startsWith('/')) return false;
  final segments = path.substring(1).split('/');
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    // Chỉ đoạn cuối được rỗng (dấu `/` cuối).
    if (segment.isEmpty) {
      if (i == segments.length - 1) continue;
      return false;
    }
    if (segment == '.' ||
        segment == '..' ||
        !_segmentPattern.hasMatch(segment)) {
      return false;
    }
  }
  return true;
}
