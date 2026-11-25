import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/foundation_providers.dart';
import '../../ide_mobile/application/ide_access.dart';

const ideWebRoutePath = '/ide-web';

/// Ô VPSTTT IDE (WebView) chỉ hiện trên Android / iOS, ở máy chủ nội bộ đã bật
/// tích hợp với địa chỉ nhúng hợp lệ. Máy chủ vẫn kiểm quyền ở mọi API.
final ideWebEnabledProvider = Provider<bool>((ref) {
  if (!ideSupportedPlatform()) return false;
  return ref.watch(activeServerDiscoveryProvider)?.ideWebEnabled ?? false;
});

/// Địa chỉ `https://ide.<chat>` đã kiểm; `null` khi tắt.
final ideWebBaseUriProvider = Provider<Uri?>((ref) {
  if (!ref.watch(ideWebEnabledProvider)) return null;
  return ref.watch(activeServerDiscoveryProvider)?.ideWebBaseUri;
});
