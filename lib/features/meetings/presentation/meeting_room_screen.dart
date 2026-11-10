import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/tokens/webtui_colors.dart';
import '../../../design_system/tokens/webtui_radii.dart';
import '../../../design_system/tokens/webtui_spacing.dart';
import '../application/meeting_room_controller.dart';
import '../data/livekit_meeting_room_client.dart';
import '../domain/meeting_models.dart';

/// Màn họp trong app (LiveKit): lưới video, mic, camera, đổi camera, loa, rời.
class MeetingRoomScreen extends StatefulWidget {
  const MeetingRoomScreen({
    required this.title,
    required this.join,
    this.startWithVideo = false,
    this.autoJoin = false,
    this.refreshJoin,
    this.clientFactory,
    this.onLeft,
    super.key,
  });

  final String title;
  final MeetingJoinInfo join;

  /// Mở camera ngay khi vào (cuộc gọi nhóm video).
  final bool startWithVideo;

  /// Bỏ màn giải thích quyền và vào luôn (người dùng đã bấm Nhận ở cuộc gọi).
  final bool autoJoin;
  final Future<MeetingJoinInfo> Function()? refreshJoin;
  final MeetingRoomClient Function()? clientFactory;

  /// Gọi sau khi đã rời phòng (mọi cách rời).
  final VoidCallback? onLeft;

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  late final MeetingRoomController _controller;
  late bool _joined = widget.autoJoin;
  bool _leftNotified = false;

  @override
  void initState() {
    super.initState();
    _controller = MeetingRoomController(
      client: (widget.clientFactory ?? LiveKitMeetingRoomClient.new)(),
      join: widget.join,
      startWithVideo: widget.startWithVideo,
      refreshJoin: widget.refreshJoin,
    );
    if (_joined) unawaited(_controller.start());
  }

  @override
  void dispose() {
    _controller.dispose();
    _notifyLeft();
    super.dispose();
  }

  void _notifyLeft() {
    if (_leftNotified) return;
    _leftNotified = true;
    widget.onLeft?.call();
  }

  void _join() {
    setState(() => _joined = true);
    unawaited(_controller.start());
  }

  Future<void> _leave() async {
    await _controller.leave();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_controller.leave());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10151F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF10151F),
          foregroundColor: Colors.white,
          title: Text(widget.title, overflow: TextOverflow.ellipsis),
        ),
        body: SafeArea(
          child: _joined
              ? ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _room(context),
                )
              : _preJoin(),
        ),
      ),
    );
  }

  Widget _preJoin() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_outlined, color: Colors.white, size: 48),
            const SizedBox(height: WebTuiSpacing.lg),
            const Text(
              'Sẵn sàng vào họp?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            const Text(
              'Ứng dụng cần dùng micro để mọi người nghe bạn nói và camera để '
              'chia sẻ hình ảnh. Máy sẽ hỏi quyền khi bạn bật từng thiết bị; '
              'bạn có thể tắt bất cứ lúc nào trong cuộc họp.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: WebTuiSpacing.xxl),
            FilledButton.icon(
              key: const Key('meeting-join-button'),
              onPressed: _join,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Tham gia họp'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _room(BuildContext context) {
    final controller = _controller;
    return switch (controller.state) {
      MeetingConnectionState.idle ||
      MeetingConnectionState.connecting => const Center(
        key: Key('meeting-connecting'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: WebTuiSpacing.lg),
            Text('Đang kết nối...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
      MeetingConnectionState.failed ||
      MeetingConnectionState.disconnected => _problem(controller),
      _ => Column(
        children: [
          if (controller.state == MeetingConnectionState.reconnecting)
            _banner(
              'Đang kết nối lại...',
              WebTuiColors.accentAmber,
              key: const Key('meeting-reconnecting'),
            ),
          if (controller.mediaNotice != null)
            _banner(
              controller.mediaNotice!,
              WebTuiColors.danger,
              onClose: controller.dismissNotice,
            ),
          Expanded(child: _grid(controller)),
          _controls(controller),
        ],
      ),
    };
  }

  Widget _problem(MeetingRoomController controller) {
    final left =
        controller.state == MeetingConnectionState.disconnected &&
        controller.error == null;
    return Center(
      key: const Key('meeting-problem'),
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              left ? Icons.call_end_rounded : Icons.wifi_off_rounded,
              color: Colors.white,
              size: 44,
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            Text(
              left
                  ? 'Bạn đã rời cuộc họp.'
                  : controller.error ?? 'Không vào được cuộc họp.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: WebTuiSpacing.xl),
            if (!left)
              FilledButton(
                key: const Key('meeting-retry-button'),
                onPressed: () => unawaited(controller.retry()),
                child: const Text('Thử lại'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                left ? 'Đóng' : 'Rời phòng',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(String text, Color color, {Key? key, VoidCallback? onClose}) {
    return Container(
      key: key,
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.md,
        vertical: WebTuiSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white)),
          ),
          if (onClose != null)
            InkWell(
              onTap: onClose,
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _grid(MeetingRoomController controller) {
    final people = controller.participants;
    if (people.isEmpty) {
      return const Center(
        child: Text(
          'Chưa có ai trong phòng.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    final columns = people.length <= 1 ? 1 : (people.length <= 4 ? 2 : 3);
    return GridView.builder(
      key: const Key('meeting-grid'),
      padding: const EdgeInsets.all(WebTuiSpacing.sm),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: WebTuiSpacing.sm,
        crossAxisSpacing: WebTuiSpacing.sm,
        childAspectRatio: columns == 1 ? 0.8 : 0.75,
      ),
      itemCount: people.length,
      itemBuilder: (context, index) {
        final person = people[index];
        return _ParticipantTile(
          person: person,
          video: person.cameraOn ? controller.videoFor(person.id) : null,
        );
      },
    );
  }

  Widget _controls(MeetingRoomController c) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: WebTuiSpacing.md,
        horizontal: WebTuiSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            key: const Key('meeting-mic-button'),
            icon: c.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: c.micOn ? 'Tắt mic' : 'Bật mic',
            active: c.micOn,
            onPressed: c.canToggleMic ? () => unawaited(c.toggleMic()) : null,
          ),
          _RoundButton(
            key: const Key('meeting-camera-button'),
            icon: c.cameraOn
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            label: c.cameraOn ? 'Tắt cam' : 'Bật cam',
            active: c.cameraOn,
            onPressed: c.canToggleCamera
                ? () => unawaited(c.toggleCamera())
                : null,
          ),
          _RoundButton(
            key: const Key('meeting-flip-button'),
            icon: Icons.cameraswitch_rounded,
            label: 'Đổi cam',
            onPressed: c.cameraOn ? () => unawaited(c.flipCamera()) : null,
          ),
          _RoundButton(
            key: const Key('meeting-speaker-button'),
            icon: c.speakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded,
            label: c.speakerOn ? 'Loa ngoài' : 'Loa trong',
            active: c.speakerOn,
            onPressed: () => unawaited(c.toggleSpeaker()),
          ),
          _RoundButton(
            key: const Key('meeting-leave-button'),
            icon: Icons.call_end_rounded,
            label: 'Rời phòng',
            danger: true,
            onPressed: () => unawaited(_leave()),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final background = danger
        ? WebTuiColors.danger
        : active
        ? Colors.white
        : Colors.white24;
    final foreground = danger || !active ? Colors.white : Colors.black87;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: background,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(icon, color: foreground),
                ),
              ),
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.person, required this.video});

  final MeetingParticipantView person;
  final Widget? video;

  @override
  Widget build(BuildContext context) {
    final initial = person.name.trim().isEmpty
        ? '?'
        : String.fromCharCode(person.name.trim().runes.first).toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1C2433),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(
          color: person.speaking
              ? WebTuiColors.accentGreen
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            video ??
                Center(
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: WebTuiColors.primary,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            Positioned(
              left: WebTuiSpacing.sm,
              right: WebTuiSpacing.sm,
              bottom: WebTuiSpacing.sm,
              child: Row(
                children: [
                  if (!person.micOn)
                    const Padding(
                      padding: EdgeInsets.only(right: WebTuiSpacing.xs),
                      child: Icon(
                        Icons.mic_off_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      person.isLocal ? '${person.name} (Bạn)' : person.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        shadows: [Shadow(blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
