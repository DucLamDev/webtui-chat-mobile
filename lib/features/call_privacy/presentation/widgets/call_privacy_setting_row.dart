import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/call_privacy.dart';

/// Cài đặt hiện tại theo workspace.
final callPrivacyProvider = FutureProvider.autoDispose
    .family<Result<WhoCanCallMe>, String>((ref, workspaceId) {
      return ref.watch(loadCallPrivacyUseCaseProvider).execute(workspaceId);
    });

/// Dòng "Ai được gọi cho tôi" trong Cài đặt (lõi 3.5). Máy chủ kiểm khi tạo
/// cuộc gọi; dòng này chỉ đổi cài đặt của chính người dùng.
class CallPrivacySettingRow extends ConsumerWidget {
  const CallPrivacySettingRow({required this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = workspaceId?.trim() ?? '';
    if (id.isEmpty) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(callPrivacyProvider(id));
    final String subtitle;
    WhoCanCallMe? current;
    switch (state) {
      case AsyncData(value: Success<WhoCanCallMe>(value: final value)):
        current = value;
        subtitle = value.description;
      case AsyncData(value: FailureResult<WhoCanCallMe>()):
      case AsyncError():
        subtitle = tr(
          'Không tải được cài đặt. Chạm để thử lại.',
          'Could not load the setting. Tap to retry.',
        );
      default:
        subtitle = tr('Đang tải...', 'Loading...');
    }
    return WebTuiSettingRow(
      key: const Key('call_privacy_row'),
      title: current == null
          ? tr('Ai được gọi cho tôi', 'Who can call me')
          : tr(
              'Ai được gọi cho tôi: ${current.label}',
              'Who can call me: ${current.label}',
            ),
      subtitle: subtitle,
      icon: WebTuiIcons.phoneCall,
      onTap: () {
        if (current == null) {
          ref.invalidate(callPrivacyProvider(id));
          return;
        }
        _choose(context, ref, id, current);
      },
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    String id,
    WhoCanCallMe current,
  ) async {
    final selected = await showWebTuiSheet<WhoCanCallMe>(
      context: context,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          WebTuiSheetHeader(
            title: tr(
              'Ai được gọi thoại / video cho bạn',
              'Who can voice / video call you',
            ),
          ),
          for (final option in WhoCanCallMe.values)
            WebTuiSheetActionTile(
              key: Key('call_privacy_choice_${option.apiValue}'),
              icon: WebTuiIcons.phoneCall,
              title: option.label,
              subtitle: option.description,
              selected: option == current,
              trailing: option == current
                  ? Icon(
                      WebTuiIcons.check,
                      size: 20,
                      color: WebTuiColors.primary,
                    )
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(option),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (selected == null || selected == current) {
      return;
    }
    final result = await ref
        .read(updateCallPrivacyUseCaseProvider)
        .execute(id, selected);
    if (!context.mounted) {
      return;
    }
    switch (result) {
      case Success<WhoCanCallMe>():
        ref.invalidate(callPrivacyProvider(id));
      case FailureResult<WhoCanCallMe>(failure: final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}
