import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import 'chat_room_controller.dart';

/// Vị trí đọc của các thành viên trong một kênh, để hiện "Đã xem" ở chat 1-1.
final class PeerReadState {
  const PeerReadState({this.readAtByUserId = const {}, this.memberCount = 0});

  /// Thời điểm đọc tới của từng thành viên (chỉ người đã có mốc đọc).
  final Map<String, DateTime> readAtByUserId;

  /// Số thành viên đang hoạt động; chỉ khi đúng 2 người mới coi là chat 1-1.
  final int memberCount;

  /// Mốc đọc của người kia (không phải [currentUserId]); `null` nếu chưa rõ,
  /// hoặc kênh không phải chat đúng 2 người.
  DateTime? peerReadAt(String? currentUserId) {
    if (currentUserId == null || memberCount != 2) return null;
    DateTime? latest;
    for (final entry in readAtByUserId.entries) {
      if (entry.key == currentUserId) continue;
      if (latest == null || entry.value.isAfter(latest)) latest = entry.value;
    }
    return latest;
  }

  PeerReadState withRead(String userId, DateTime readAt) {
    final current = readAtByUserId[userId];
    if (current != null && !readAt.isAfter(current)) return this;
    return PeerReadState(
      readAtByUserId: {...readAtByUserId, userId: readAt},
      memberCount: memberCount,
    );
  }
}

/// Tin CUỐI của mình đã được người kia đọc: tin của mình có `createdAt` không
/// muộn hơn [peerReadAt]; `null` nếu chưa tin nào được đọc. Tin đang gửi / lỗi
/// và tin đã xoá không tính.
String? seenMessageIdFor({
  required List<ChatMessage> messages,
  required DateTime? peerReadAt,
}) {
  if (peerReadAt == null) return null;
  ChatMessage? last;
  for (final message in messages) {
    if (!message.isMine || message.isDeleted) continue;
    if (const {
      'uploading',
      'queued',
      'sending',
      'failed',
    }.contains(message.deliveryStatus)) {
      continue;
    }
    if (message.createdAt.isAfter(peerReadAt)) continue;
    if (last == null || message.createdAt.isAfter(last.createdAt)) {
      last = message;
    }
  }
  return last?.id;
}

final class PeerReadController extends StateNotifier<PeerReadState> {
  PeerReadController({
    required this.scope,
    required Future<Result<List<ChannelMember>>> Function() loadMembers,
    required Stream<ConversationRealtimeEvent> events,
  }) : _loadMembers = loadMembers,
       super(const PeerReadState()) {
    _subscription = events
        .where(
          (event) =>
              event.type == ConversationRealtimeEventType.channelReadUpdated &&
              event.belongsTo(
                workspaceId: scope.workspaceId,
                channelId: scope.channelId,
              ),
        )
        .listen(_onEvent);
    unawaited(refresh());
  }

  final ChatRoomScope scope;
  final Future<Result<List<ChannelMember>>> Function() _loadMembers;
  StreamSubscription<ConversationRealtimeEvent>? _subscription;

  Future<void> refresh() async {
    final result = await _loadMembers();
    if (!mounted) return;
    if (result case Success<List<ChannelMember>>(value: final members)) {
      final active = members.where(
        (member) => member.status == 'active' || member.status == 'muted',
      );
      var next = PeerReadState(memberCount: active.length);
      for (final member in active) {
        final readAt = member.lastReadAt;
        if (readAt != null) next = next.withRead(member.userId, readAt);
      }
      // Giữ mốc mới hơn đã nhận qua realtime trong lúc tải.
      for (final entry in state.readAtByUserId.entries) {
        next = next.withRead(entry.key, entry.value);
      }
      state = next;
    }
  }

  void _onEvent(ConversationRealtimeEvent event) {
    final userId = event.userId?.trim();
    final raw = event.payload['last_read_at'] ?? event.payload['lastReadAt'];
    final readAt = raw is String ? DateTime.tryParse(raw) : null;
    if (userId == null || userId.isEmpty || readAt == null) return;
    state = state.withRead(userId, readAt);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

final peerReadProvider = StateNotifierProvider.autoDispose
    .family<PeerReadController, PeerReadState, ChatRoomScope>((ref, scope) {
      final members = ref.watch(listChannelMembersUseCaseProvider);
      final realtime = ref.watch(subscribeConversationRealtimeUseCaseProvider);
      return PeerReadController(
        scope: scope,
        loadMembers: () => members.execute(
          workspaceId: scope.workspaceId,
          channelId: scope.channelId,
        ),
        events: realtime.execute(
          workspaceId: scope.workspaceId,
          channelId: scope.channelId,
        ),
      );
    });
