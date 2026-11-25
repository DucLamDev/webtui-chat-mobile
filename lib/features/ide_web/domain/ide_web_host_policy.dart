enum IdeWebUrlClass { internal, external, blocked }

/// Xử lý một lần điều hướng: cho đi, chặn, hoặc chặn rồi hỏi mở ngoài app.
enum IdeWebNavigation { allow, block, askExternal }

/// Địa chỉ nào được ở trong WebView: đúng `https://ide.<chat>` cổng 443.
final class IdeWebHostPolicy {
  IdeWebHostPolicy(Uri baseUri)
    : host = baseUri.host.toLowerCase(),
      origin = 'https://${baseUri.host.toLowerCase()}',
      assert(baseUri.scheme == 'https' && baseUri.host.isNotEmpty);

  final String host;

  /// Không có dấu `/` cuối (dùng trong chuỗi ký và cho lớp native).
  final String origin;

  Uri get homeUri => Uri.parse('$origin/appchat/');

  IdeWebUrlClass classify(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return IdeWebUrlClass.blocked;
    }
    if (uri.host.toLowerCase() == host) {
      return uri.port == 443 ? IdeWebUrlClass.internal : IdeWebUrlClass.blocked;
    }
    return IdeWebUrlClass.external;
  }

  IdeWebUrlClass classifyText(String? url) {
    final uri = Uri.tryParse(url ?? '');
    return uri == null ? IdeWebUrlClass.blocked : classify(uri);
  }

  bool isInternalText(String? url) =>
      classifyText(url) == IdeWebUrlClass.internal;

  /// Khung phụ ra ngoài địa chỉ IDE luôn bị chặn (Android: gói không báo khung
  /// phụ; IDE phải gửi CSP `frame-src 'none'`). [newWindowAsSubframe]: iOS báo
  /// liên kết mở cửa sổ mới (`target=_blank`) như khung phụ vì không có khung
  /// đích, nên cũng hỏi mở ngoài app. [blankExpected]: app đang tự tải trang trống.
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
    return kind == IdeWebUrlClass.external &&
            (isMainFrame || newWindowAsSubframe)
        ? IdeWebNavigation.askExternal
        : IdeWebNavigation.block;
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

  /// `browser_url` máy chủ trả: vé một lần ở phần `#` (không gửi lên máy chủ).
  bool isBrowserUrl(Uri uri) =>
      classify(uri) == IdeWebUrlClass.internal &&
      uri.path == '/_appchat/start' &&
      !uri.hasQuery;
}
