import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
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
        ? 'Không dùng hoặc chạy nền quá thời gian này thì khóa. '
              'Máy chủ cho phép tối đa ${AppLockTimeoutPolicy.label(serverMax)}.'
        : 'Không dùng hoặc chạy nền quá thời gian này thì khóa.';
    return WebTuiSettingRow(
      key: const Key('app_lock_timeout_row'),
      title: 'Tự khóa sau ${AppLockTimeoutPolicy.label(effective)}',
      subtitle: subtitle,
      icon: Icons.timer_outlined,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _choose(context, ref, serverMax, effective),
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    int serverMax,
    int current,
  ) async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final choices = AppLockTimeoutPolicy.allowedChoices(serverMax);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Tự khóa ứng dụng sau'),
                subtitle: Text(
                  'Đang gọi thì ứng dụng không tự khóa để không cắt cuộc gọi.',
                ),
              ),
              for (final minutes in choices)
                ListTile(
                  key: Key('app_lock_timeout_choice_$minutes'),
                  title: Text(AppLockTimeoutPolicy.label(minutes)),
                  trailing: minutes == current
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(minutes),
                ),
            ],
          ),
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
