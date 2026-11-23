import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/foundation_providers.dart';

/// IDE chỉ chạy trên Android và iOS (cần chip bảo mật + sinh trắc học).
bool ideSupportedPlatform([TargetPlatform? platform]) {
  if (kIsWeb) return false;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

/// Mục IDE chỉ hiện trên Android / iOS, cho module nội bộ VPSTTT và khi máy
/// chủ chat đã cấu hình cổng IDE (`capabilities.ide`, chỉ bật / tắt tab).
/// Máy chủ vẫn kiểm ở mọi API.
final ideEnabledProvider = Provider<bool>((ref) {
  if (!ideSupportedPlatform()) return false;
  final discovery = ref.watch(activeServerDiscoveryProvider);
  if (discovery == null) return false;
  return discovery.vpstttInternalModules && discovery.capabilities.ide;
});
