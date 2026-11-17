import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/app_lock_timeout_policy.dart';

/// Dòng "Tự khóa sau" trong Cài đặt (lõi 3.1). Chỉ hiện khi đã bật khóa ứng dụng.
/// Người dùng chỉ chọn được mức ≤ mức máy chủ cho phép.
class AppLockTimeoutSettingRow extends ConsumerWidget {
  const AppLockTimeoutSettingRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isAppLockEnabledProvider).valueOrNull != true) {
      return const SizedBox.shrink();
    }
    final serverMax = ref.watch(appLockServerMaxMinutesProvider);
    final effective = ref.watch(effectiveAppLockMinutesProvider);
    final subtitle = serverMax > 0
        ? tr(
            'Không dùng hoặc chạy nền quá thời gian này thì khóa. '
                'Máy chủ cho phép tối đa ${AppLockTimeoutPolicy.label(serverMax)}.',
            'The app locks if it is unused or in the background for longer than this. '
                'The server allows at most ${AppLockTimeoutPolicy.label(serverMax)}.',
          )
        : tr(
            'Không dùng hoặc chạy nền quá thời gian này thì khóa.',
            'The app locks if it is unused or in the background for longer than this.',
          );
    return WebTuiSettingRow(
      key: const Key('app_lock_timeout_row'),
      title: tr(
        'Tự khóa sau ${AppLockTimeoutPolicy.label(effective)}',
        'Auto-lock after ${AppLockTimeoutPolicy.label(effective)}',
      ),
      subtitle: subtitle,
      icon: WebTuiIcons.timer,
      onTap: () => _choose(context, ref, serverMax, effective),
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    int serverMax,
    int current,
  ) async {
    final selected = await showWebTuiSheet<int>(
      context: context,
      builder: (sheetContext) {
        final choices = AppLockTimeoutPolicy.allowedChoices(serverMax);
        return ListView(
          shrinkWrap: true,
          children: [
            WebTuiSheetHeader(
              title: tr('Tự khóa ứng dụng sau', 'Auto-lock app after'),
              subtitle: tr(
                'Đang gọi thì ứng dụng không tự khóa để không cắt cuộc gọi.',
                'The app does not lock during a call so the call is not cut off.',
              ),
            ),
            for (final minutes in choices)
              WebTuiSheetActionTile(
                key: Key('app_lock_timeout_choice_$minutes'),
                icon: WebTuiIcons.lock,
                title: AppLockTimeoutPolicy.label(minutes),
                selected: minutes == current,
                trailing: minutes == current
                    ? Icon(
                        WebTuiIcons.check,
                        size: 20,
                        color: WebTuiColors.primary,
                      )
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(minutes),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
    if (selected == null || selected == current) {
      return;
    }
    final result = await ref
        .read(saveAppLockIdleMinutesUseCaseProvider)
        .execute(minutes: selected, serverMaxMinutes: serverMax);
    if (!context.mounted) {
      return;
    }
    switch (result) {
      case Success<void>():
        ref.invalidate(appLockIdleMinutesProvider);
      case FailureResult<void>(failure: final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}
