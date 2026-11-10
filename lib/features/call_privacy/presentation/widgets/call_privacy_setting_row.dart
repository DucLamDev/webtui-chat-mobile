import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
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
        subtitle = 'Không tải được cài đặt. Chạm để thử lại.';
      default:
        subtitle = 'Đang tải...';
    }
    return WebTuiSettingRow(
      key: const Key('call_privacy_row'),
      title: current == null
          ? 'Ai được gọi cho tôi'
          : 'Ai được gọi cho tôi: ${current.label}',
      subtitle: subtitle,
      icon: Icons.phone_locked_outlined,
      trailing: const Icon(Icons.chevron_right_rounded),
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
    final selected = await showModalBottomSheet<WhoCanCallMe>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Ai được gọi thoại / video cho bạn')),
            for (final option in WhoCanCallMe.values)
              ListTile(
                key: Key('call_privacy_choice_${option.apiValue}'),
                title: Text(option.label),
                subtitle: Text(option.description),
                trailing: option == current
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
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
