import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/channel_avatar_policy.dart';
import '../../domain/entities/conversation_summary.dart';

/// Mục "Đổi ảnh nhóm" ở màn thông tin kênh. Chỉ hiện cho người được đổi
/// (xem [canChangeChannelAvatar]); máy chủ vẫn kiểm quyền khi tải lên.
class ChannelAvatarSetting extends StatelessWidget {
  const ChannelAvatarSetting({
    required this.channel,
    required this.updating,
    this.errorMessage,
    this.onChange,
    super.key,
  });

  final ConversationSummary? channel;
  final bool updating;
  final String? errorMessage;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    if (!canChangeChannelAvatar(channel)) return const SizedBox.shrink();
    final error = errorMessage?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              0,
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
            ),
            child: Semantics(
              liveRegion: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: WebTuiColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(WebTuiRadii.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(WebTuiSpacing.md),
                  child: Text(
                    error,
                    key: const ValueKey('channel-avatar-error'),
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
          child: WebTuiListSurface(
            children: [
              WebTuiSettingRow(
                key: const ValueKey('channel-change-avatar'),
                title: tr('Đổi ảnh nhóm', 'Change group photo'),
                subtitle: updating
                    ? tr('Đang tải ảnh lên...', 'Uploading photo...')
                    : channel?.channelVisibility == ChannelVisibility.private
                    ? tr(
                        'Thành viên nào của nhóm cũng đổi được',
                        'Any group member can change it',
                      )
                    : tr(
                        'Chỉ người quản lý nhóm đổi được',
                        'Only group managers can change it',
                      ),
                icon: Icons.photo_camera_outlined,
                trailing: updating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: updating ? null : onChange,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
