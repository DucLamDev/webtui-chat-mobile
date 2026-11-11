import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/platform/external_url_launcher.dart';
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
    final dismiss = ValueNotifier<bool>(false);
    _dismissSignals[call.id] = dismiss;
    try {
      return await showDialog<GroupCallChoice>(
        context: ctx,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => GroupCallRingDialog(
          title: call.ringTitle,
          isVideo: call.isVideo,
          dismissSignal: dismiss,
          timeout: ringTimeout,
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
        showError('Không mở được phòng họp trên thiết bị này.');
        return;
      }
      final url = MeetingJoinInfo.withJitsiJwt(
        base.resolve(Uri.encodeComponent(join.room)),
        join.token,
      );
      if (!await launcher.open(url.toString())) {
        showError('Không mở được phòng họp trên thiết bị này.');
      }
      await endNativeCall(call.id);
      return;
    }
    await Navigator.of(ctx, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MeetingRoomScreen(
          title: call.channelName.isEmpty ? 'Cuộc họp nhóm' : call.channelName,
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

/// Hộp thoại chuông "người gọi đang gọi nhóm kênh", Nhận / Từ chối.
class GroupCallRingDialog extends StatefulWidget {
  const GroupCallRingDialog({
    required this.title,
    required this.isVideo,
    required this.dismissSignal,
    required this.timeout,
    super.key,
  });

  final String title;
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
    return AlertDialog(
      icon: Icon(widget.isVideo ? Icons.videocam_rounded : Icons.call_rounded),
      title: Text(widget.title, textAlign: TextAlign.center),
      content: Text(
        widget.isVideo ? 'Cuộc gọi nhóm video' : 'Cuộc gọi nhóm thoại',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(
          key: const Key('group-call-decline'),
          onPressed: () => _close(GroupCallChoice.decline),
          child: const Text('Từ chối'),
        ),
        FilledButton(
          key: const Key('group-call-accept'),
          onPressed: () => _close(GroupCallChoice.accept),
          child: const Text('Nhận'),
        ),
      ],
    );
  }
}
