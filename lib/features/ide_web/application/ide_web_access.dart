import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/foundation_providers.dart';

const ideWebRoutePath = '/ide-web';

/// IDE chỉ chạy trên Android và iOS (cần chip bảo mật + sinh trắc học).
bool ideSupportedPlatform([TargetPlatform? platform]) {
  if (kIsWeb) return false;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

/// Ô VPSTTT IDE (WebView) chỉ hiện trên Android / iOS, ở máy chủ nội bộ đã bật
/// tích hợp với địa chỉ nhúng và địa chỉ đăng nhập hợp lệ. Máy chủ vẫn kiểm quyền ở mọi API.
final ideWebEnabledProvider = Provider<bool>((ref) {
  if (!ideSupportedPlatform()) return false;
  return ref.watch(activeServerDiscoveryProvider)?.ideWebEnabled ?? false;
});

/// Địa chỉ `https://ide.<chat>` đã kiểm; `null` khi tắt.
final ideWebBaseUriProvider = Provider<Uri?>((ref) {
  if (!ref.watch(ideWebEnabledProvider)) return null;
  return ref.watch(activeServerDiscoveryProvider)?.ideWebBaseUri;
});

/// Địa chỉ đăng nhập `https://<ide>` đã kiểm; `null` khi tắt.
final ideWebAuthBaseUriProvider = Provider<Uri?>((ref) {
  if (!ref.watch(ideWebEnabledProvider)) return null;
  return ref.watch(activeServerDiscoveryProvider)?.ideWebAuthBaseUri;
});
