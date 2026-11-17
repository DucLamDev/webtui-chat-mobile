import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/network/api_response.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_avatar.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/use_cases/load_conversation_home_use_case.dart';
import '../../domain/entities/conversation_realtime_event.dart';
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

/// Một lần đổi hiện diện đẩy từ máy chủ (`PresenceChanged`).
final class PresenceChange {
  const PresenceChange({
    required this.seq,
    required this.workspaceId,
    required this.summary,
  });

  /// Tăng dần để hai sự kiện giống hệt nhau vẫn đều báo cho người nghe.
  final int seq;
  final String workspaceId;
  final PresenceSummary summary;
}

/// Sự kiện `PresenceChanged` mới nhất; [workspacePresenceSourceProvider] nghe
/// và cập nhật ngay, không chờ lượt tải định kỳ.
final presenceChangeProvider = StateProvider<PresenceChange?>((ref) => null);

/// Tăng để buộc tải lại `GET /presence` ngay (app quay lại từ nền, WebSocket
/// nối lại).
final presenceRefreshTickProvider = StateProvider<int>((ref) => 0);

/// Đọc `PresenceChanged` thành [PresenceSummary]; thiếu trường / trạng thái lạ
/// thì `null` (bỏ sự kiện).
PresenceSummary? presenceFromRealtimeEvent(ConversationRealtimeEvent event) {
  if (event.type != ConversationRealtimeEventType.presenceChanged) return null;
  final payload = event.payload;
  final userId = stringField(payload, const ['user_id', 'userId']);
  final status = switch (stringField(payload, const ['status']).toLowerCase()) {
    'online' => ConversationPresence.online,
    'away' => ConversationPresence.away,
    'offline' => ConversationPresence.offline,
    _ => null,
  };
  final beat = nullableDateTimeField(payload, const [
    'last_heartbeat_at',
    'lastHeartbeatAt',
  ]);
  if (userId.isEmpty || status == null || beat == null) return null;
  return PresenceSummary(userId: userId, status: status, lastHeartbeatAt: beat);
}

/// Báo cho các nguồn hiện diện một sự kiện `PresenceChanged` của [workspaceId].
/// Trả `true` nếu đúng là sự kiện này (kể cả khi bị bỏ vì thiếu trường).
bool handlePresenceRealtimeEvent({
  required T Function<T>(ProviderListenable<T>) read,
  required ConversationRealtimeEvent event,
  required String workspaceId,
}) {
  if (event.type != ConversationRealtimeEventType.presenceChanged) return false;
  final workspace = stringField(event.payload, const [
    'workspace_id',
    'workspaceId',
  ], fallback: event.workspaceId);
  final summary = presenceFromRealtimeEvent(event);
  if (summary == null || workspace != workspaceId) return true;
  final notifier = read(presenceChangeProvider.notifier);
  notifier.state = PresenceChange(
    seq: (notifier.state?.seq ?? 0) + 1,
    workspaceId: workspace,
    summary: summary,
  );
  return true;
}

/// Buộc mọi nguồn hiện diện tải lại ngay.
void refreshPresenceNow(T Function<T>(ProviderListenable<T>) read) {
  final tick = read(presenceRefreshTickProvider.notifier);
  tick.state = tick.state + 1;
}

/// Gộp danh sách `GET /presence` (nhiều thiết bị) thành một bản ghi mỗi người:
/// trạng thái tốt nhất (online > away > offline), mốc heartbeat mới nhất.
Map<String, PresenceSummary> presenceSummaryByUser(List<PresenceSummary> items) {
  final status = presenceByUser(items);
  final latest = <String, DateTime>{};
  for (final item in items) {
    final current = latest[item.userId];
    if (current == null || item.lastHeartbeatAt.isAfter(current)) {
      latest[item.userId] = item.lastHeartbeatAt;
    }
  }
  return {
    for (final entry in status.entries)
      entry.key: PresenceSummary(
        userId: entry.key,
        status: entry.value,
        lastHeartbeatAt: latest[entry.key]!,
      ),
  };
}

/// Nguồn hiện diện chung của một workspace (một lượt `GET /presence` cho cả
/// chấm xanh danh sách lẫn thanh trên phòng chat 1-1). Cập nhật: ngay khi có
/// `PresenceChanged`, ngay khi [presenceRefreshTickProvider] tăng, và định kỳ
/// [workspacePresenceRefreshInterval] làm dự phòng (máy chủ cũ chưa có sự
/// kiện). Lỗi mạng thì giữ kết quả lần trước. Bộ hẹn giờ bị huỷ khi không còn
/// màn nào nghe.
final workspacePresenceSourceProvider = StreamProvider.autoDispose
    .family<Map<String, PresenceSummary>, String>((ref, workspaceId) {
      final repository = ref.watch(conversationRepositoryProvider);
      final controller =
          StreamController<Map<String, PresenceSummary>>();
      var current = <String, PresenceSummary>{};
      Timer? timer;
      var disposed = false;
      var generation = 0;

      Future<void> load() async {
        timer?.cancel();
        final mine = ++generation;
        final result = await repository.listPresence(workspaceId: workspaceId);
        if (disposed || mine != generation) return;
        if (result case Success<List<PresenceSummary>>(value: final list)) {
          current = presenceSummaryByUser(list);
          controller.add(Map.unmodifiable(current));
        }
        timer = Timer(
          workspacePresenceRefreshInterval,
          () => unawaited(load()),
        );
      }

      ref.listen<PresenceChange?>(presenceChangeProvider, (_, change) {
        if (disposed || change == null || change.workspaceId != workspaceId) {
          return;
        }
        current = {...current, change.summary.userId: change.summary};
        controller.add(Map.unmodifiable(current));
      });
      ref.listen<int>(presenceRefreshTickProvider, (_, _) {
        if (!disposed) unawaited(load());
      });
      ref.onDispose(() {
        disposed = true;
        timer?.cancel();
        unawaited(controller.close());
      });
      unawaited(load());
      return controller.stream;
    });

Stream<T> _deriveFromSource<T>(
  Ref ref,
  String workspaceId,
  T Function(Map<String, PresenceSummary>) pick,
) {
  final controller = StreamController<T>();
  final source = workspacePresenceSourceProvider(workspaceId);
  void emit(AsyncValue<Map<String, PresenceSummary>>? value) {
    final data = value?.valueOrNull;
    if (data != null && !controller.isClosed) controller.add(pick(data));
  }

  ref.listen(source, (_, next) => emit(next));
  ref.onDispose(() => unawaited(controller.close()));
  emit(ref.read(source));
  return controller.stream;
}

/// Hiện diện của người kia (thanh trên phòng chat 1-1), đọc từ nguồn chung
/// [workspacePresenceSourceProvider]. Chưa có dữ liệu / lỗi mạng → không có giá
/// trị, người dùng thấy `null` (ẩn dòng phụ); không có bản ghi của người đó →
/// `null`.
final peerPresenceProvider = StreamProvider.autoDispose
    .family<PresenceSummary?, PeerPresenceKey>((ref, key) {
      return _deriveFromSource<PresenceSummary?>(
        ref,
        key.workspaceId,
        (all) => all[key.peerUserId],
      );
    });

/// Hiện diện cả workspace theo người (cùng nguồn `GET /presence` với danh sách
/// hội thoại), đọc từ [workspacePresenceSourceProvider]. Danh sách hội thoại,
/// Danh bạ và danh sách thành viên nhóm cùng đọc nên chấm xanh các nơi luôn
/// khớp và đổi ngay khi có `PresenceChanged`.
final workspacePresenceProvider = StreamProvider.autoDispose
    .family<Map<String, ConversationPresence>, String>((ref, workspaceId) {
      return _deriveFromSource<Map<String, ConversationPresence>>(
        ref,
        workspaceId,
        (all) => Map.unmodifiable({
          for (final e in all.entries) e.key: e.value.status,
        }),
      );
    });

/// Chu kỳ tải lại dự phòng. Giữ 30 giây: đã có `PresenceChanged` + tải ngay khi
/// resume / nối lại WebSocket, và nguồn chung chỉ gọi một lượt cho mọi màn.
const workspacePresenceRefreshInterval = Duration(seconds: 30);

/// Chấm trên ảnh đại diện ở danh sách thành viên nhóm: giống dòng chat ở danh
/// sách hội thoại, chỉ hiện chấm xanh khi đang online; còn lại không chấm.
WebTuiPresenceStatus? memberPresenceStatus(ConversationPresence? presence) {
  return presence == ConversationPresence.online
      ? WebTuiPresenceStatus.online
      : null;
}
