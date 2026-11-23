import 'package:flutter/foundation.dart';

import '../../l10n/app_strings.dart';

/// Giả lập bản phát hành / bản gỡ lỗi trong test (`null` = theo bản đang chạy).
@visibleForTesting
bool? debugReleaseNetworkPolicyOverride;

/// Bản phát hành: không coi `localhost` / `127.0.0.1` là máy chủ thử (không
/// nhận `http` / `ws` thường tới đó). Chỉ bản gỡ lỗi / chạy thử mới nhận.
bool get loopbackDevServerAllowed =>
    !(debugReleaseNetworkPolicyOverride ?? kReleaseMode);

/// Máy chủ thử trên chính máy (`localhost`, `127.0.0.1`, `*.localhost`), chỉ
/// đúng khi [loopbackDevServerAllowed]; bản phát hành luôn là `false`.
bool isLoopbackDevServerHost(String host) {
  if (!loopbackDevServerAllowed) return false;
  final h = host.toLowerCase();
  return h == 'localhost' || h == '127.0.0.1' || h.endsWith('.localhost');
}

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
    throw FormatException(
      tr('Địa chỉ server không hợp lệ.', 'Invalid server address.'),
    );
  }

  final isLocal = isLoopbackDevServerHost(parsed.host);
  if (parsed.scheme != 'https' && !(isLocal && parsed.scheme == 'http')) {
    throw FormatException(
      tr(
        'Server public phải sử dụng HTTPS.',
        'A public server must use HTTPS.',
      ),
    );
  }

  return Uri(
    scheme: parsed.scheme,
    host: parsed.host,
    port: parsed.hasPort ? parsed.port : null,
  );
}
