import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/conversation_summary.dart';

/// Nhãn trạng thái hoạt động của người kia ở đầu phòng chat 1-1.
final class PeerPresenceLabel {
  const PeerPresenceLabel({required this.text, required this.online});

  /// Dòng phụ dưới tên.
  final String text;

  /// `true`: hiện chấm xanh.
  final bool online;
}

/// Chọn nhãn từ dữ liệu hiện diện (cùng nguồn danh sách hội thoại):
/// online → "Đang hoạt động" + chấm xanh; không online nhưng có thời điểm hoạt
/// động gần nhất → "Hoạt động … trước", không chấm; không có dữ liệu → `null`
/// (ẩn dòng phụ và chấm).
PeerPresenceLabel? peerPresenceLabel(PresenceSummary? presence, DateTime now) {
  if (presence == null) return null;
  if (presence.status == ConversationPresence.online) {
    return const PeerPresenceLabel(text: 'Đang hoạt động', online: true);
  }
  final last = presence.lastHeartbeatAt.toLocal();
  final diff = now.difference(last);
  // Mốc ở tương lai hoặc quá xa (máy chủ chưa từng ghi) coi như không có dữ liệu.
  if (diff.isNegative && diff.inMinutes < -5) return null;
  if (last.year < 2000) return null;
  final String text;
  if (diff.inMinutes < 1) {
    text = 'Vừa hoạt động';
  } else if (diff.inMinutes < 60) {
    text = 'Hoạt động ${diff.inMinutes} phút trước';
  } else if (diff.inHours < 24 && last.day == now.day) {
    text = 'Hoạt động ${diff.inHours} giờ trước';
  } else {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(last.year, last.month, last.day);
    final days = today.difference(day).inDays;
    if (days <= 1) {
      text = days == 0
          ? 'Hoạt động ${diff.inHours} giờ trước'
          : 'Hoạt động hôm qua';
    } else if (days < 7) {
      text = 'Hoạt động $days ngày trước';
    } else {
      text =
          'Hoạt động ${last.day.toString().padLeft(2, '0')}/'
          '${last.month.toString().padLeft(2, '0')}/${last.year}';
    }
  }
  return PeerPresenceLabel(text: text, online: false);
}

typedef PeerPresenceKey = ({String workspaceId, String peerUserId});

/// Hiện diện của người kia, tải lại mỗi 30 giây. Lỗi mạng → `null` (ẩn).
final peerPresenceProvider = StreamProvider.autoDispose
    .family<PresenceSummary?, PeerPresenceKey>((ref, key) async* {
      final repository = ref.watch(conversationRepositoryProvider);
      while (true) {
        final result = await repository.listPresence(
          workspaceId: key.workspaceId,
        );
        PresenceSummary? found;
        if (result case Success<List<PresenceSummary>>(value: final list)) {
          for (final item in list) {
            if (item.userId == key.peerUserId) found = item;
          }
        }
        yield found;
        await Future<void>.delayed(const Duration(seconds: 30));
      }
    });
