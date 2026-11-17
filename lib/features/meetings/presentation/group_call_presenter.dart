import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../core/platform/external_url_launcher.dart';
import '../../conversations/presentation/widgets/incoming_call_view.dart';
import '../application/group_call_coordinator.dart';
import '../data/meeting_remote_data_source.dart';
import '../domain/meeting_models.dart';
import 'meeting_room_screen.dart';

/// Chuông trong app, mở họp và tắt chuông gốc của cuộc gọi nhóm.
final class ShellGroupCallPresenter implements GroupCallPresenter {
  ShellGroupCallPresenter({
    required this.context,
    required this.api,
    required this.launcher,
    required this.endNativeRinging,
    required this.endNativeCall,
    this.ringTimeout = const Duration(seconds: 45),
  });

  /// `null` khi màn đã gỡ.
  final BuildContext? Function() context;
  final MeetingApi api;
  final ExternalUrlLauncher launcher;

  /// Tắt chuông gốc còn đang đổ (không đụng cuộc gọi đã nhận).
  final Future<void> Function(String groupCallId) endNativeRinging;

  /// Kết thúc giao diện cuộc gọi gốc sau khi rời họp.
  final Future<void> Function(String groupCallId) endNativeCall;
  final Duration ringTimeout;
  final _dismissSignals = <String, ValueNotifier<bool>>{};

  @override
  Future<GroupCallChoice?> showRinging(GroupCall call) async {
    final ctx = context();
    if (ctx == null || !ctx.mounted) return null;
    // Giờ chuông theo máy chủ nếu có; hết rồi thì không hiện nữa.
    var timeout = ringTimeout;
    final endsAt = call.ringEndsAt;
    if (endsAt != null) {
      timeout = endsAt.difference(DateTime.now());
      if (timeout <= Duration.zero) return null;
    }
    final dismiss = ValueNotifier<bool>(false);
    _dismissSignals[call.id] = dismiss;
    try {
      return await showDialog<GroupCallChoice>(
        context: ctx,
        useRootNavigator: true,
        barrierDismissible: false,
        // Toàn màn hình như cuộc gọi 1-1 (màn tự chừa vùng an toàn).
        useSafeArea: false,
        builder: (_) => GroupCallRingDialog(
          title: call.ringTitle,
          groupName: call.channelName,
          callerName: call.startedByName,
          isVideo: call.isVideo,
          dismissSignal: dismiss,
          timeout: timeout,
        ),
      );
    } finally {
      if (identical(_dismissSignals[call.id], dismiss)) {
        _dismissSignals.remove(call.id);
      }
    }
  }

  @override
  Future<void> dismissRinging(String groupCallId) async {
    _dismissSignals[groupCallId]?.value = true;
    await endNativeRinging(groupCallId);
  }

  @override
  Future<void> openMeeting(GroupCall call, MeetingJoinInfo join) async {
    final ctx = context();
    if (ctx == null || !ctx.mounted) return;
    if (join.provider == MeetingProviderKind.jitsi) {
      final base = Uri.tryParse(join.serverUrl);
      if (base == null || join.room.isEmpty) {
        showError(
          tr(
            'Không mở được phòng họp trên thiết bị này.',
            'Couldn\'t open the meeting room on this device.',
          ),
        );
        return;
      }
      final url = MeetingJoinInfo.withJitsiJwt(
        base.resolve(Uri.encodeComponent(join.room)),
        join.token,
      );
      if (!await launcher.open(url.toString())) {
        showError(
          tr(
            'Không mở được phòng họp trên thiết bị này.',
            'Couldn\'t open the meeting room on this device.',
          ),
        );
      }
      await endNativeCall(call.id);
      return;
    }
    await Navigator.of(ctx, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MeetingRoomScreen(
          title: call.channelName.isEmpty
              ? tr('Cuộc họp nhóm', 'Group meeting')
              : call.channelName,
          join: join,
          startWithVideo: call.isVideo,
          autoJoin: true,
          refreshJoin: () => api.fetchJoinToken(
            workspaceId: call.workspaceId,
            channelId: call.channelId,
            meetingId: call.meetingId,
          ),
          onLeft: () => unawaited(endNativeCall(call.id)),
        ),
      ),
    );
  }

  @override
  void showError(String message) {
    final ctx = context();
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.maybeOf(
      ctx,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Màn chuông cuộc gọi nhóm toàn màn hình (cùng kiểu cuộc gọi 1-1): tên nhóm,
/// "Người gọi đang gọi nhóm…", Trả lời / Từ chối.
class GroupCallRingDialog extends StatefulWidget {
  const GroupCallRingDialog({
    required this.title,
    required this.isVideo,
    required this.dismissSignal,
    required this.timeout,
    this.groupName = '',
    this.callerName = '',
    super.key,
  });

  /// Câu đầy đủ "Người gọi đang gọi nhóm Tên nhóm" (đọc cho trình đọc màn
  /// hình, dùng khi thiếu tên nhóm).
  final String title;
  final String groupName;
  final String callerName;
  final bool isVideo;
  final ValueNotifier<bool> dismissSignal;
  final Duration timeout;

  @override
  State<GroupCallRingDialog> createState() => _GroupCallRingDialogState();
}

class _GroupCallRingDialogState extends State<GroupCallRingDialog> {
  Timer? _timer;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.dismissSignal.addListener(_onDismiss);
    _timer = Timer(widget.timeout, () => _close(GroupCallChoice.timedOut));
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.dismissSignal.removeListener(_onDismiss);
    super.dispose();
  }

  void _onDismiss() {
    if (widget.dismissSignal.value) _close(null);
  }

  void _close(GroupCallChoice? choice) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(choice);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.groupName.trim();
    final caller = widget.callerName.trim();
    return PopScope(
      canPop: false,
      child: Semantics(
        label: widget.title,
        child: IncomingCallView(
          key: const Key('group-call-ring'),
          name: group.isEmpty ? widget.title : group,
          isGroup: true,
          isVideo: widget.isVideo,
          subtitle: group.isEmpty
              ? null
              : (caller.isEmpty
                    ? null
                    : tr(
                        '$caller đang gọi nhóm…',
                        '$caller is calling the group…',
                      )),
          onDecline: () => _close(GroupCallChoice.decline),
          onAccept: () => _close(GroupCallChoice.accept),
        ),
      ),
    );
  }
}
