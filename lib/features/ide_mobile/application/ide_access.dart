import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/foundation_providers.dart';

/// Mục IDE chỉ hiện cho module nội bộ VPSTTT và khi máy chủ chat đã cấu hình
/// cổng IDE (`capabilities.ide`). Máy chủ vẫn kiểm ở mọi API.
final ideEnabledProvider = Provider<bool>((ref) {
  final discovery = ref.watch(activeServerDiscoveryProvider);
  if (discovery == null) return false;
  return discovery.vpstttInternalModules && discovery.capabilities.ide;
});
