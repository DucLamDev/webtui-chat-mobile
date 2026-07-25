Uri parseSelfHostedServerUri(String value) {
  var input = value.trim();
  if (!input.contains('://')) {
    input = 'https://$input';
  }

  final parsed = Uri.tryParse(input);
  if (parsed == null ||
      parsed.host.isEmpty ||
      parsed.userInfo.isNotEmpty ||
      parsed.path.replaceAll('/', '').isNotEmpty ||
      parsed.query.isNotEmpty ||
      parsed.fragment.isNotEmpty) {
    throw const FormatException('Địa chỉ server không hợp lệ.');
  }

  final isLocal =
      parsed.host == 'localhost' ||
      parsed.host == '127.0.0.1' ||
      parsed.host.endsWith('.localhost');
  if (parsed.scheme != 'https' && !(isLocal && parsed.scheme == 'http')) {
    throw const FormatException('Server public phải sử dụng HTTPS.');
  }

  return Uri(
    scheme: parsed.scheme,
    host: parsed.host,
    port: parsed.hasPort ? parsed.port : null,
  );
}
