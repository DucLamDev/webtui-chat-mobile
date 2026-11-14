import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';

/// Tên và logo hiển thị cho chat bot thông báo. Dựng từ discovery (không dùng
/// tên máy chủ lưu trong kênh) để luôn đúng khi tổ chức đổi tên hoặc logo.
final class NoticeBotIdentity {
  const NoticeBotIdentity({required this.title, this.logoUrl});

  final String title;
  final String? logoUrl;

  /// Chữ viết tắt khi chưa có logo.
  String get avatarLabel => title;

  static NoticeBotIdentity fromOrganization({String? name, String? logoUrl}) {
    final cleanName = name?.trim() ?? '';
    final cleanLogo = logoUrl?.trim() ?? '';
    return NoticeBotIdentity(
      title: cleanName.isEmpty ? 'Bot thông báo' : '$cleanName Bot',
      logoUrl: cleanLogo.isEmpty ? null : cleanLogo,
    );
  }
}

final noticeBotIdentityProvider = Provider<NoticeBotIdentity>((ref) {
  final discovery = ref.watch(activeServerDiscoveryProvider);
  return NoticeBotIdentity.fromOrganization(
    name: discovery?.name,
    logoUrl: discovery?.logoUrl,
  );
});
