import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../profile/domain/entities/user_profile.dart';
import '../../domain/entities/call_session.dart';
import '../controllers/peer_presence.dart';

/// Khoá tra hồ sơ đồng nghiệp: hồ sơ công việc (chức danh, phòng ban...) theo
/// workspace đang mở.
typedef ColleagueProfileKey = ({String workspaceId, String userId});

/// Hồ sơ đồng nghiệp từ máy chủ (`GET /api/v1/users/{id}`). Máy chủ chỉ trả
/// người cùng workspace / zone và đã bỏ IP, thiết bị với người xem thường.
final colleagueProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, ColleagueProfileKey>((ref, key) {
      return ref
          .watch(profileRemoteDataSourceProvider)
          .byId(key.userId, workspaceId: key.workspaceId);
    });

/// Mở bảng hồ sơ đồng nghiệp (bấm ảnh / tên ở đầu chat 1-1, bấm ảnh người gửi
/// trong nhóm). Tên, ảnh, giới tính, trạng thái truyền sẵn để đầu bảng hiện
/// ngay trong lúc tải hồ sơ đầy đủ.
///
/// [onMessage] / [onCall] `null` thì ẩn nút tương ứng (vd đang ở chính chat
/// 1-1 với người đó thì không cần "Nhắn tin", máy chủ tắt gọi thì không có nút
/// gọi). Bấm nút thì đóng bảng rồi mới chạy hành động.
Future<void> showColleagueProfileSheet(
  BuildContext context, {
  required String workspaceId,
  required String userId,
  required String fallbackName,
  String? avatarUrl,
  WebTuiAvatarGender? gender,
  PeerPresenceLabel? presence,
  VoidCallback? onMessage,
  ValueChanged<CallMode>? onCall,
}) {
  return showWebTuiSheet<void>(
    context: context,
    builder: (_) => ColleagueProfileSheet(
      profileKey: (workspaceId: workspaceId, userId: userId),
      fallbackName: fallbackName,
      avatarUrl: avatarUrl,
      gender: gender,
      presence: presence,
      onMessage: onMessage,
      onCall: onCall,
    ),
  );
}

class ColleagueProfileSheet extends ConsumerWidget {
  const ColleagueProfileSheet({
    required this.profileKey,
    required this.fallbackName,
    this.avatarUrl,
    this.gender,
    this.presence,
    this.onMessage,
    this.onCall,
    super.key,
  });

  final ColleagueProfileKey profileKey;
  final String fallbackName;
  final String? avatarUrl;
  final WebTuiAvatarGender? gender;
  final PeerPresenceLabel? presence;
  final VoidCallback? onMessage;
  final ValueChanged<CallMode>? onCall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(colleagueProfileProvider(profileKey));
    final profile = async.valueOrNull;
    final name = _nonEmpty(profile?.displayName) ?? fallbackName;
    final work = profile?.work ?? const WorkProfile();
    final headline = [
      _nonEmpty(work.title),
      _nonEmpty(work.department),
    ].whereType<String>().join(' · ');
    final presence = this.presence;

    void run(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    final actions = <Widget>[
      if (onMessage != null)
        _ProfileAction(
          key: const Key('colleague_profile_message'),
          icon: WebTuiIcons.newMessage,
          label: tr('Nhắn tin', 'Message'),
          onTap: () => run(onMessage!),
        ),
      if (onCall != null) ...[
        _ProfileAction(
          key: const Key('colleague_profile_call_audio'),
          icon: WebTuiIcons.phone,
          label: tr('Gọi thoại', 'Voice call'),
          onTap: () => run(() => onCall!(CallMode.audio)),
        ),
        _ProfileAction(
          key: const Key('colleague_profile_call_video'),
          icon: WebTuiIcons.video,
          label: tr('Gọi video', 'Video call'),
          onTap: () => run(() => onCall!(CallMode.video)),
        ),
      ],
    ];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.xl,
          0,
          WebTuiSpacing.xl,
          WebTuiSpacing.xxl,
        ),
        child: Column(
          key: const Key('colleague_profile_sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: WebTuiAvatar(
                label: name,
                imageUrl: _nonEmpty(profile?.avatarUrl) ?? avatarUrl,
                gender: profile?.gender == null
                    ? gender
                    : WebTuiAvatarGender.parse(profile!.gender),
                status: presence?.online == true
                    ? WebTuiPresenceStatus.online
                    : null,
                size: 88,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WebTuiTypography.titleLarge.copyWith(
                color: WebTuiColors.textPrimary,
              ),
            ),
            if (headline.isNotEmpty) ...[
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                headline,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ],
            if (presence != null) ...[
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                presence.text,
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: presence.online
                      ? WebTuiColors.accentGreen
                      : WebTuiColors.textMuted,
                  fontWeight: presence.online ? FontWeight.w600 : null,
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: WebTuiSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final action in actions)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WebTuiSpacing.sm,
                      ),
                      child: action,
                    ),
                ],
              ),
            ],
            const SizedBox(height: WebTuiSpacing.xl),
            _ProfileDetails(
              async: async,
              onRetry: () =>
                  ref.invalidate(colleagueProfileProvider(profileKey)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nút tròn dưới tên (nhắn tin / gọi): nền xanh nhạt, biểu tượng xanh, nhãn
/// nhỏ bên dưới; vùng bấm 72 × 76.
class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        child: SizedBox(
          width: 72,
          height: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: WebTuiColors.primary.withValues(
                    alpha: dark ? 0.22 : 0.1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: dark ? WebTuiColors.textPrimary : WebTuiColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.labelSmall.copyWith(
                  fontSize: 12,
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phần thông tin: đang tải / lỗi / chưa có thông tin / danh sách dòng.
class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({required this.async, required this.onRetry});

  final AsyncValue<UserProfile> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final profile = async.valueOrNull;
    if (profile == null && async.isLoading) {
      return Padding(
        key: const Key('colleague_profile_loading'),
        padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WebTuiColors.primary,
              ),
            ),
            const SizedBox(width: WebTuiSpacing.sm),
            Text(
              tr('Đang tải hồ sơ…', 'Loading profile…'),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }
    if (profile == null) {
      final notFound = _isNotFound(async.error);
      return Column(
        key: const Key('colleague_profile_error'),
        children: [
          Text(
            notFound
                ? tr(
                    'Bạn không xem được hồ sơ của người này.',
                    "You can't view this person's profile.",
                  )
                : tr(
                    'Không tải được hồ sơ. Hãy kiểm tra mạng rồi thử lại.',
                    "Couldn't load the profile. Check your connection and try again.",
                  ),
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textMuted,
            ),
          ),
          if (!notFound)
            TextButton(onPressed: onRetry, child: Text(tr('Thử lại', 'Retry'))),
        ],
      );
    }

    final work = profile.work;
    final startDate = work.startDate;
    final rows = <Widget>[
      if (_nonEmpty(profile.email) case final email?)
        _ProfileInfoRow(
          icon: WebTuiIcons.email,
          label: tr('Email', 'Email'),
          value: email,
          copyable: true,
        ),
      if (_nonEmpty(profile.phoneNumber) case final phone?)
        _ProfileInfoRow(
          icon: WebTuiIcons.phone,
          label: tr('Điện thoại', 'Phone'),
          value: phone,
          copyable: true,
        ),
      // Chức danh, phòng ban đã hiện ngay dưới tên: không lặp ở đây.
      if (_nonEmpty(work.location) case final location?)
        _ProfileInfoRow(
          icon: WebTuiIcons.location,
          label: tr('Nơi làm việc', 'Location'),
          value: location,
        ),
      if (startDate != null)
        _ProfileInfoRow(
          icon: WebTuiIcons.startDate,
          label: tr('Ngày vào làm', 'Start date'),
          value: _formatDate(startDate),
        ),
    ];
    if (rows.isEmpty) {
      return Text(
        tr('Chưa có thông tin công việc.', 'No work details yet.'),
        key: const Key('colleague_profile_empty'),
        textAlign: TextAlign.center,
        style: WebTuiTypography.bodySmall.copyWith(
          color: WebTuiColors.textMuted,
        ),
      );
    }
    return Column(
      key: const Key('colleague_profile_details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: WebTuiColors.border),
        for (final row in rows) ...[
          row,
          Divider(height: 1, color: WebTuiColors.border),
        ],
      ],
    );
  }
}

/// Một dòng thông tin: biểu tượng, nhãn nhỏ, giá trị; email / điện thoại có
/// nút chép.
class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Icon(icon, size: 22, color: WebTuiColors.textSecondary),
          const SizedBox(width: WebTuiSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: WebTuiColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    value,
                    maxLines: 2,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: tr('Chép $label', 'Copy $label'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(
                    content: Text(tr('Đã chép $value', 'Copied $value')),
                  ),
                );
              },
              icon: Icon(
                WebTuiIcons.copy,
                size: 20,
                color: WebTuiColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

bool _isNotFound(Object? error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    return status == 404 || status == 403;
  }
  return false;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _formatDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}
