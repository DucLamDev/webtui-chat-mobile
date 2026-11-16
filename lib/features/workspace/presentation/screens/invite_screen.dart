import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/workspace_invite.dart';
import '../controllers/invite_controller.dart';
import '../controllers/workspace_controller.dart';

/// Mở lời mời `/invite/:token` khi đã đăng nhập: xem trước rồi tham gia.
class InviteScreen extends ConsumerWidget {
  const InviteScreen({required this.token, super.key});

  final String token;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = inviteControllerProvider(token);
    ref.listen<InviteState>(provider, (previous, next) {
      if (next.phase == InvitePhase.accepted &&
          previous?.phase != InvitePhase.accepted) {
        _enterWorkspace(context, ref, next.result?.workspaceId);
      }
    });
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr('Đóng', 'Close'),
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(tr('Lời mời tham gia', 'Invitation to join')),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: switch (state.phase) {
          InvitePhase.loading => WebTuiLoadingState(
            message: tr('Đang tải lời mời...', 'Loading invitation...'),
          ),
          InvitePhase.error => WebTuiErrorState(
            title: tr(
              'Không tải được lời mời',
              'Could not load the invitation',
            ),
            message:
                state.errorMessage ??
                tr('Vui lòng thử lại.', 'Please try again.'),
            onRetry: controller.load,
          ),
          InvitePhase.unavailable => WebTuiEmptyState(
            title: tr('Lời mời không dùng được', 'Invitation unavailable'),
            message:
                state.errorMessage ??
                tr(
                  'Lời mời không còn hiệu lực.',
                  'This invitation is no longer valid.',
                ),
            icon: Icons.link_off_rounded,
          ),
          InvitePhase.accepted => WebTuiLoadingState(
            message: tr('Đang mở workspace...', 'Opening workspace...'),
          ),
          InvitePhase.ready || InvitePhase.accepting => _InvitePreviewView(
            preview: state.preview!,
            busy: state.phase == InvitePhase.accepting,
            errorMessage: state.errorMessage,
            onAccept: controller.accept,
          ),
        },
      ),
    );
  }

  Future<void> _enterWorkspace(
    BuildContext context,
    WidgetRef ref,
    String? workspaceId,
  ) async {
    final workspaces = ref.read(workspaceControllerProvider.notifier);
    await workspaces.load();
    final target = ref
        .read(workspaceControllerProvider)
        .workspaces
        .where((item) => item.id == workspaceId)
        .firstOrNull;
    if (target != null) {
      await workspaces.select(target);
    }
    if (context.mounted) {
      context.go('/');
    }
  }
}

class _InvitePreviewView extends StatelessWidget {
  const _InvitePreviewView({
    required this.preview,
    required this.busy,
    required this.errorMessage,
    required this.onAccept,
  });

  final WorkspaceInvitePreview preview;
  final bool busy;
  final String? errorMessage;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final expiresAt = preview.expiresAt?.toLocal();
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: WebTuiColors.surface,
            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            border: Border.all(color: WebTuiColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(WebTuiSpacing.lg),
            child: Column(
              children: [
                WebTuiAvatar(label: preview.workspaceName, size: 64),
                const SizedBox(height: WebTuiSpacing.md),
                Text(
                  tr(
                    'Bạn được mời vào ${preview.workspaceName}',
                    'You were invited to ${preview.workspaceName}',
                  ),
                  textAlign: TextAlign.center,
                  style: WebTuiTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (preview.domain != null) ...[
                  const SizedBox(height: WebTuiSpacing.xs),
                  Text(
                    preview.domain!,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
                ],
                if (preview.emailHint != null) ...[
                  const SizedBox(height: WebTuiSpacing.sm),
                  Text(
                    tr(
                      'Lời mời dành cho ${preview.emailHint}',
                      'Invitation for ${preview.emailHint}',
                    ),
                    textAlign: TextAlign.center,
                    style: WebTuiTypography.bodySmall,
                  ),
                ],
                if (expiresAt != null) ...[
                  const SizedBox(height: WebTuiSpacing.xs),
                  Text(
                    tr(
                      'Hết hạn ngày ${expiresAt.day.toString().padLeft(2, '0')}/'
                          '${expiresAt.month.toString().padLeft(2, '0')}/'
                          '${expiresAt.year}',
                      'Expires on ${expiresAt.day.toString().padLeft(2, '0')}/'
                          '${expiresAt.month.toString().padLeft(2, '0')}/'
                          '${expiresAt.year}',
                    ),
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: WebTuiSpacing.md),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: WebTuiSpacing.lg),
        FilledButton.icon(
          key: const Key('invite_accept_button'),
          onPressed: busy ? null : onAccept,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.group_add_rounded),
          label: const Text('Tham gia workspace'),
        ),
      ],
    );
  }
}
