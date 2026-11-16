import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../l10n/app_strings.dart';
import '../../../notifications/presentation/controllers/channel_mute_controller.dart';

/// Nút menu trên thanh phòng chat bot: Tắt / Bật thông báo cả chat bot.
class NoticeBotMuteAction extends ConsumerWidget {
  const NoticeBotMuteAction({
    required this.workspaceId,
    required this.channelId,
    super.key,
  });

  final String workspaceId;
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ChannelMuteKey(workspaceId: workspaceId, channelId: channelId);
    final provider = channelMuteControllerProvider(key);
    final state = ref.watch(provider);
    final muted = state.muted ?? false;
    final label = muted
        ? tr('Bật thông báo', 'Turn on notifications')
        : tr('Tắt thông báo', 'Turn off notifications');
    if (state.isSaving) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              key: Key('notice_bot_mute_saving'),
              strokeWidth: 2,
              color: WebTuiColors.primary,
            ),
          ),
        ),
      );
    }
    return PopupMenuButton<bool>(
      key: const Key('notice_bot_mute_menu'),
      tooltip: tr('Tuỳ chọn thông báo', 'Notification options'),
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (_) async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final controller = ref.read(provider.notifier);
        final saved = await controller.toggle();
        if (!context.mounted) return;
        final message = saved
            ? (ref.read(provider).muted == true
                  ? tr(
                      'Đã tắt thông báo của bot.',
                      'Bot notifications turned off.',
                    )
                  : tr(
                      'Đã bật thông báo của bot.',
                      'Bot notifications turned on.',
                    ))
            : (ref.read(provider).errorMessage ??
                  tr(
                    'Chưa lưu được cài đặt thông báo.',
                    'Could not save notification settings.',
                  ));
        messenger?.showSnackBar(SnackBar(content: Text(message)));
      },
      itemBuilder: (_) => [
        PopupMenuItem<bool>(
          key: const Key('notice_bot_mute_toggle'),
          value: true,
          child: Row(
            children: [
              Icon(
                muted
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(label),
            ],
          ),
        ),
      ],
    );
  }
}
