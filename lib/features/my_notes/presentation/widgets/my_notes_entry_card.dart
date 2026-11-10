import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../controllers/my_notes_access_provider.dart';

/// Thẻ "My Note" trong tab Công việc; ẩn khi máy chủ chưa bật tính năng.
class MyNotesEntryCard extends ConsumerWidget {
  const MyNotesEntryCard({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(myNotesEnabledProvider) || workspaceId.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
      child: Material(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        child: InkWell(
          key: const Key('my_notes_entry_card'),
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          onTap: () => unawaited(
            context.push(
              Uri(
                path: '/my-notes',
                queryParameters: {'workspaceId': workspaceId.trim()},
              ).toString(),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(WebTuiSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WebTuiRadii.lg),
              border: Border.all(color: WebTuiColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: WebTuiColors.primarySoft,
                    borderRadius: BorderRadius.circular(WebTuiRadii.md),
                  ),
                  child: const Icon(
                    Icons.sticky_note_2_outlined,
                    color: WebTuiColors.primary,
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Note',
                        style: WebTuiTypography.bodyMedium.copyWith(
                          color: WebTuiColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Sổ ghi chú riêng của bạn, chỉ mình bạn xem được.',
                        style: WebTuiTypography.bodySmall.copyWith(
                          color: WebTuiColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: WebTuiColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
