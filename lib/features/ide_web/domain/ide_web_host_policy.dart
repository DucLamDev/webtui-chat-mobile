enum IdeWebUrlClass { internal, external, blocked }

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
