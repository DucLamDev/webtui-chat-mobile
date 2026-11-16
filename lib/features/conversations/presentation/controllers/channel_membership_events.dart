import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../application/use_cases/conversation_realtime_reducer.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import 'channel_detail_controller.dart';
import 'conversation_home_controller.dart';

/// Lý do một nhóm biến mất khỏi máy này.
enum ChannelRemovalReason {
  /// Mình vừa rời nhóm (ở máy này hoặc máy khác).
  left,

  /// Nhóm vừa bị xoá cho mọi thành viên.
  deleted,
}

/// Báo cho phòng chat / màn thông tin nhóm đang mở rằng nhóm đã không còn:
/// màn đang mở đúng nhóm đó tự đóng và báo người dùng. [serial] tăng mỗi lần
/// để hai lần báo cùng nhóm vẫn là hai giá trị khác nhau.
final class ChannelRemovalSignal {
  const ChannelRemovalSignal({
    required this.workspaceId,
    required this.channelId,
    required this.reason,
    required this.serial,
    this.initiatedHere = false,
  });

  final String workspaceId;
  final String channelId;
  final ChannelRemovalReason reason;
  final int serial;

  /// Do chính máy này bấm Rời / Xoá: màn đã tự đóng và báo, không báo lại.
  final bool initiatedHere;
}

final channelRemovalSignalProvider = StateProvider<ChannelRemovalSignal?>(
  (ref) => null,
);

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);
typedef ProviderExists = bool Function(ProviderBase<Object?> provider);

/// Bỏ nhóm khỏi danh sách Tin nhắn, bộ nhớ đệm và báo màn đang mở nhóm đó.
/// Dùng cả khi người dùng bấm Rời / Xoá lẫn khi nhận sự kiện realtime.
void removeChannelEverywhere({
  required ProviderReader read,
  required ProviderExists exists,
  required String workspaceId,
  required String channelId,
  required ChannelRemovalReason reason,
  bool initiatedHere = false,
  bool forgetCache = true,
}) {
  final home = conversationHomeControllerProvider(workspaceId);
  if (exists(home)) {
    read(home.notifier).removeChannel(channelId);
  }
  if (forgetCache) {
    unawaited(
      read(
        forgetGroupLocallyUseCaseProvider,
      ).execute(workspaceId: workspaceId, channelId: channelId),
    );
  }
  final signal = read(channelRemovalSignalProvider.notifier);
  signal.state = ChannelRemovalSignal(
    workspaceId: workspaceId,
    channelId: channelId,
    reason: reason,
    serial: (signal.state?.serial ?? 0) + 1,
    initiatedHere: initiatedHere,
  );
}

/// Xử lý `ChannelArchived` / `ChannelMemberLeft` (từ room cá nhân hoặc room
/// kênh). Trả `true` nếu là một trong hai sự kiện này.
bool handleChannelMembershipEvent({
  required ProviderReader read,
  required ProviderExists exists,
  required ConversationRealtimeEvent event,
  required String? currentUserId,
}) {
  final change = const ConversationRealtimeReducer().membershipChange(
    event,
    currentUserId: currentUserId,
  );
  if (change == null) {
    return event.type == ConversationRealtimeEventType.channelArchived ||
        event.type == ConversationRealtimeEventType.channelMemberLeft;
  }
  switch (change) {
    case ChannelMembershipChange.archived:
    case ChannelMembershipChange.leftByMe:
      removeChannelEverywhere(
        read: read,
        exists: exists,
        workspaceId: event.workspaceId,
        channelId: event.channelId,
        reason: change == ChannelMembershipChange.archived
            ? ChannelRemovalReason.deleted
            : ChannelRemovalReason.left,
      );
    case ChannelMembershipChange.memberLeft:
      // Người khác rời: làm mới số thành viên ở danh sách và màn thông tin.
      final home = conversationHomeControllerProvider(event.workspaceId);
      if (exists(home)) {
        unawaited(read(home.notifier).syncSilently());
      }
      final tick = read(channelUpdatedTickProvider(event.channelId).notifier);
      tick.state = tick.state + 1;
  }
  return true;
}
