import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_avatar.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/use_cases/load_conversation_home_use_case.dart';
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
    return PeerPresenceLabel(
      text: tr('Đang hoạt động', 'Active now'),
      online: true,
    );
  }
  final last = presence.lastHeartbeatAt.toLocal();
  final diff = now.difference(last);
  // Mốc ở tương lai hoặc quá xa (máy chủ chưa từng ghi) coi như không có dữ liệu.
  if (diff.isNegative && diff.inMinutes < -5) return null;
  if (last.year < 2000) return null;
  final String text;
  if (diff.inMinutes < 1) {
    text = tr('Vừa hoạt động', 'Active just now');
  } else if (diff.inMinutes < 60) {
    text = tr(
      'Hoạt động ${diff.inMinutes} phút trước',
      'Active ${diff.inMinutes} min ago',
    );
  } else if (diff.inHours < 24 && last.day == now.day) {
    text = tr(
      'Hoạt động ${diff.inHours} giờ trước',
      'Active ${diff.inHours} h ago',
    );
  } else {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(last.year, last.month, last.day);
    final days = today.difference(day).inDays;
    if (days <= 1) {
      text = days == 0
          ? tr(
              'Hoạt động ${diff.inHours} giờ trước',
              'Active ${diff.inHours} h ago',
            )
          : tr('Hoạt động hôm qua', 'Active yesterday');
    } else if (days < 7) {
      text = tr('Hoạt động $days ngày trước', 'Active $days days ago');
    } else {
      final date =
          '${last.day.toString().padLeft(2, '0')}/'
          '${last.month.toString().padLeft(2, '0')}/${last.year}';
      text = tr('Hoạt động $date', 'Active $date');
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

/// Hiện diện cả workspace theo người, tải lại mỗi 30 giây (cùng nguồn
/// `GET /presence` với danh sách hội thoại). Danh sách hội thoại và danh sách
/// thành viên nhóm cùng đọc nguồn này nên chấm xanh hai nơi luôn khớp. Lỗi mạng
/// thì giữ kết quả lần trước (chưa có lần nào thì chưa có giá trị). Bộ hẹn giờ
/// bị huỷ khi không còn màn nào nghe.
final workspacePresenceProvider = StreamProvider.autoDispose
    .family<Map<String, ConversationPresence>, String>((ref, workspaceId) {
      final repository = ref.watch(conversationRepositoryProvider);
      final controller = StreamController<Map<String, ConversationPresence>>();
      Timer? timer;
      var disposed = false;
      Future<void> load() async {
        final result = await repository.listPresence(workspaceId: workspaceId);
        if (disposed) return;
        if (result case Success<List<PresenceSummary>>(value: final list)) {
          controller.add(presenceByUser(list));
        }
        timer = Timer(
          workspacePresenceRefreshInterval,
          () => unawaited(load()),
        );
      }

      ref.onDispose(() {
        disposed = true;
        timer?.cancel();
        unawaited(controller.close());
      });
      unawaited(load());
      return controller.stream;
    });

/// Chu kỳ tải lại hiện diện của [workspacePresenceProvider].
const workspacePresenceRefreshInterval = Duration(seconds: 30);

/// Chấm trên ảnh đại diện ở danh sách thành viên nhóm: giống dòng chat ở danh
/// sách hội thoại, chỉ hiện chấm xanh khi đang online; còn lại không chấm.
WebTuiPresenceStatus? memberPresenceStatus(ConversationPresence? presence) {
  return presence == ConversationPresence.online
      ? WebTuiPresenceStatus.online
      : null;
}
