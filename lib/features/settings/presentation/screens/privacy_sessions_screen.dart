import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/flavor/app_config.dart';
import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../features/auth/domain/entities/user_session.dart';
import '../../../moderation/presentation/controllers/moderation_controller.dart';
import '../../../moderation/presentation/widgets/moderation_actions.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';

final sessionListProvider =
    FutureProvider.autoDispose<Result<List<UserSession>>>((ref) {
      return ref.watch(listSessionsUseCaseProvider).execute();
    });

class PrivacySessionsScreen extends ConsumerWidget {
  const PrivacySessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionListProvider);
    final config = ref.watch(appConfigProvider);
    final workspaceId = ref.watch(
      workspaceControllerProvider.select((state) => state.activeWorkspace?.id),
    );
    final showSessionActions = switch (sessions) {
      AsyncData<Result<List<UserSession>>>(
        value: Success<List<UserSession>>(),
      ) =>
        true,
      _ => false,
    };

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Quay lại',
          onPressed: () => _goBackOrHome(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Quyền riêng tư'),
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.7)),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: WebTuiSpacing.xl),
          children: [
            const WebTuiSectionLabel('Phiên đăng nhập'),
            sessions.when(
              data: (result) {
                return switch (result) {
                  Success<List<UserSession>>(value: final value) =>
                    _SessionList(sessions: value),
                  FailureResult<List<UserSession>>(failure: final failure) =>
                    failure.requiresLogin
                        ? _RequiresLoginState(message: failure.message)
                        : WebTuiErrorState(
                            title: 'Không tải được phiên',
                            message: failure.message,
                            onRetry: () => ref.invalidate(sessionListProvider),
                          ),
                };
              },
              error: (_, _) => WebTuiErrorState(
                title: 'Không tải được phiên',
                message: 'Vui lòng thử lại sau.',
                onRetry: () => ref.invalidate(sessionListProvider),
              ),
              loading: () => const WebTuiLoadingState(
                message: 'Đang tải phiên đăng nhập...',
              ),
            ),
            if (showSessionActions) ...[
              const WebTuiSectionLabel('Thao tác phiên'),
              const _SessionActions(),
            ],
            const WebTuiSectionLabel('Bảo mật màn hình'),
            WebTuiListSurface(
              children: const [
                WebTuiSettingRow(
                  title: 'Ẩn nội dung khi app vào nền',
                  subtitle: 'Đã bật bảo vệ ảnh chụp màn hình',
                  icon: Icons.screenshot_monitor_outlined,
                  trailing: Icon(
                    Icons.check_circle_rounded,
                    color: WebTuiColors.accentGreen,
                  ),
                ),
              ],
            ),
            if (workspaceId?.trim().isNotEmpty == true) ...[
              const WebTuiSectionLabel('An toàn cộng đồng'),
              _BlockedUsersSection(workspaceId: workspaceId!),
            ],
            const WebTuiSectionLabel('Chính sách và dữ liệu'),
            WebTuiListSurface(
              children: [
                WebTuiSettingRow(
                  title: 'Điều khoản sử dụng',
                  subtitle: _isHttpsUrl(config.termsUrl)
                      ? 'Quy tắc sử dụng và nội dung được phép'
                      : 'Chưa được cấu hình cho bản dựng này',
                  icon: Icons.gavel_outlined,
                  trailing: TextButton(
                    onPressed: _isHttpsUrl(config.termsUrl)
                        ? () => _openLegalUrl(
                            context,
                            ref,
                            config.termsUrl,
                            'Điều khoản sử dụng',
                          )
                        : null,
                    child: const Text('Xem'),
                  ),
                ),
                WebTuiSettingRow(
                  title: 'Chính sách quyền riêng tư',
                  subtitle: _isHttpsUrl(config.privacyPolicyUrl)
                      ? 'Xem cách dữ liệu tài khoản và tin nhắn được xử lý'
                      : 'Chưa được cấu hình cho bản dựng này',
                  icon: Icons.policy_outlined,
                  trailing: TextButton(
                    onPressed: _isHttpsUrl(config.privacyPolicyUrl)
                        ? () => _openLegalUrl(
                            context,
                            ref,
                            config.privacyPolicyUrl,
                            'Chính sách quyền riêng tư',
                          )
                        : null,
                    child: const Text('Xem'),
                  ),
                ),
              ],
            ),
            const WebTuiSectionLabel('Tài khoản'),
            const _DeleteAccountAction(),
          ],
        ),
      ),
    );
  }
}

class _BlockedUsersSection extends ConsumerWidget {
  const _BlockedUsersSection({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = moderationControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    if (state.isLoadingBlockedUsers && state.blockedUsers.isEmpty) {
      return const WebTuiLoadingState(
        message: 'Đang tải danh sách người dùng đã chặn...',
      );
    }
    if (state.errorMessage != null && state.blockedUsers.isEmpty) {
      return WebTuiErrorState(
        title: 'Không tải được danh sách đã chặn',
        message: state.errorMessage!,
        onRetry: controller.loadBlockedUsers,
      );
    }
    if (state.blockedUsers.isEmpty) {
      return WebTuiListSurface(
        children: const [
          WebTuiSettingRow(
            title: 'Không có người dùng bị chặn',
            subtitle:
                'Bạn có thể chặn từ thao tác tin nhắn hoặc trang thành viên.',
            icon: Icons.shield_outlined,
          ),
        ],
      );
    }
    return WebTuiListSurface(
      children: [
        for (final blockedUser in state.blockedUsers)
          WebTuiSettingRow(
            title: blockedUser.label,
            subtitle: blockedUser.reason?.trim().isNotEmpty == true
                ? 'Đã chặn · ${blockedUser.reason}'
                : 'Nội dung từ người dùng này đang được ẩn',
            icon: Icons.block_rounded,
            trailing: TextButton(
              onPressed: () => toggleUserBlock(
                context,
                ref,
                workspaceId: workspaceId,
                userId: blockedUser.blockedUserId,
                userLabel: blockedUser.label,
              ),
              child: const Text('Bỏ chặn'),
            ),
          ),
      ],
    );
  }
}

Future<void> _openLegalUrl(
  BuildContext context,
  WidgetRef ref,
  String url,
  String label,
) async {
  final opened = await ref.read(externalUrlLauncherProvider).open(url);
  if (context.mounted && !opened) {
    _showSnackBar(context, 'Không mở được $label.');
  }
}

bool _isHttpsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
}

class _DeleteAccountAction extends ConsumerStatefulWidget {
  const _DeleteAccountAction();

  @override
  ConsumerState<_DeleteAccountAction> createState() =>
      _DeleteAccountActionState();
}

class _DeleteAccountActionState extends ConsumerState<_DeleteAccountAction> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    return WebTuiListSurface(
      children: [
        WebTuiSettingRow(
          title: 'Xóa tài khoản',
          subtitle: 'Xóa vĩnh viễn tài khoản và yêu cầu xóa dữ liệu liên quan',
          icon: Icons.delete_forever_outlined,
          trailing: TextButton(
            onPressed: _isDeleting ? null : _deleteAccount,
            style: TextButton.styleFrom(foregroundColor: WebTuiColors.danger),
            child: _isDeleting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Xóa'),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAccount() async {
    final request = await _confirmAccountDeletion(context);
    if (request == null || !mounted) {
      return;
    }
    setState(() => _isDeleting = true);
    final result = await ref
        .read(deleteAccountUseCaseProvider)
        .execute(
          confirmation: request.confirmation,
          ownershipSuccessorEmail: request.ownershipSuccessorEmail,
        );
    if (!mounted) {
      return;
    }
    setState(() => _isDeleting = false);
    switch (result) {
      case Success<void>():
        context.go('/login');
      case FailureResult<void>(failure: final failure):
        if (failure.kind == FailureKind.conflict) {
          await _showAccountDeletionConflict(context, failure.message);
          return;
        }
        _showSnackBar(context, failure.message);
        if (failure.code == 'ACCOUNT_DELETED_LOCAL_CLEAR_FAILED') {
          context.go('/login');
        }
    }
  }
}

Future<({String confirmation, String? ownershipSuccessorEmail})?>
_confirmAccountDeletion(BuildContext context) {
  final confirmationController = TextEditingController();
  final successorController = TextEditingController();
  return showDialog<({String confirmation, String? ownershipSuccessorEmail})>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final canDelete =
              confirmationController.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            title: const Text('Xóa vĩnh viễn tài khoản?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thao tác này không thể hoàn tác. Các phiên đăng nhập sẽ bị thu hồi; dữ liệu phải lưu theo quy định pháp luật hoặc chính sách tổ chức có thể được giữ lại trong thời hạn đã công bố.',
                  ),
                  const SizedBox(height: WebTuiSpacing.md),
                  const Text('Nhập DELETE để xác nhận.'),
                  const SizedBox(height: WebTuiSpacing.sm),
                  TextField(
                    controller: successorController,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email thành viên nhận quyền',
                      helperText:
                          'Chỉ nhập nếu bạn là owner; người nhận phải đang hoạt động trong mọi workspace bạn sở hữu.',
                    ),
                  ),
                  const SizedBox(height: WebTuiSpacing.md),
                  TextField(
                    controller: confirmationController,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Xác nhận',
                      hintText: 'DELETE',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: canDelete
                    ? () {
                        final successorEmail = successorController.text.trim();
                        Navigator.pop(dialogContext, (
                          confirmation: confirmationController.text.trim(),
                          ownershipSuccessorEmail: successorEmail.isEmpty
                              ? null
                              : successorEmail,
                        ));
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: WebTuiColors.danger,
                ),
                child: const Text('Xóa tài khoản'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(() {
    confirmationController.dispose();
    successorController.dispose();
  });
}

Future<void> _showAccountDeletionConflict(
  BuildContext context,
  String serverMessage,
) {
  final message = serverMessage.trim().isEmpty
      ? 'Bạn đang sở hữu workspace. Hãy nhập email của một thành viên đang hoạt động để chuyển quyền rồi thử lại.'
      : serverMessage;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cần chuyển quyền sở hữu'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );
}

class _RequiresLoginState extends ConsumerWidget {
  const _RequiresLoginState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: WebTuiColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: WebTuiColors.border.withValues(alpha: 0.8)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_clock_rounded,
                color: WebTuiColors.danger,
                size: 28,
              ),
              const SizedBox(height: WebTuiSpacing.sm),
              Text(
                'Cần đăng nhập lại',
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                message.isEmpty ? 'Phiên đăng nhập đã hết hạn.' : message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
              const SizedBox(height: WebTuiSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _goBackOrHome(context),
                    child: const Text('Quay lại'),
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  FilledButton.icon(
                    onPressed: () async {
                      await ref.read(logoutUseCaseProvider).execute();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Đăng nhập lại'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionList extends ConsumerWidget {
  const _SessionList({required this.sessions});

  final List<UserSession> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessions.isEmpty) {
      return const WebTuiEmptyState(
        title: 'Chưa có phiên khác',
        message: 'Các thiết bị đăng nhập sẽ xuất hiện ở đây.',
        icon: Icons.devices_other_outlined,
      );
    }

    return WebTuiListSurface(
      children: [
        for (final session in sessions)
          WebTuiSettingRow(
            title: session.deviceName ?? 'Thiết bị không xác định',
            subtitle: session.isActive ? 'Đang hoạt động' : 'Đã hết hạn',
            icon: Icons.devices_rounded,
            trailing: IconButton(
              tooltip: 'Thu hồi phiên',
              onPressed: () async {
                final confirmed = await _confirmDestructiveAction(
                  context,
                  title: 'Thu hồi phiên này?',
                  message: session.isActive
                      ? 'Phiên hiện tại sẽ bị đăng xuất khỏi thiết bị này.'
                      : 'Thiết bị này sẽ cần đăng nhập lại để tiếp tục sử dụng.',
                  confirmLabel: 'Thu hồi',
                );
                if (!confirmed || !context.mounted) {
                  return;
                }

                final result = await ref
                    .read(revokeSessionUseCaseProvider)
                    .execute(session.id);
                if (!context.mounted) {
                  return;
                }
                switch (result) {
                  case Success<void>():
                    if (session.isActive) {
                      await ref.read(logoutUseCaseProvider).execute();
                      if (!context.mounted) {
                        return;
                      }
                      context.go('/login');
                      return;
                    }
                    ref.invalidate(sessionListProvider);
                    _showSnackBar(context, 'Đã thu hồi phiên.');
                  case FailureResult<void>(failure: final failure):
                    _showSnackBar(context, failure.message);
                }
              },
              icon: const Icon(Icons.logout_rounded),
            ),
          ),
      ],
    );
  }
}

class _SessionActions extends ConsumerWidget {
  const _SessionActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WebTuiListSurface(
      children: [
        WebTuiSettingRow(
          title: 'Đăng xuất tất cả thiết bị',
          subtitle: 'Thu hồi mọi phiên và quay lại màn đăng nhập',
          icon: Icons.logout_rounded,
          trailing: TextButton.icon(
            onPressed: () async {
              final confirmed = await _confirmDestructiveAction(
                context,
                title: 'Đăng xuất tất cả thiết bị?',
                message:
                    'Tất cả phiên đăng nhập sẽ bị thu hồi. Bạn cần đăng nhập lại trên thiết bị này.',
                confirmLabel: 'Đăng xuất',
              );
              if (!confirmed || !context.mounted) {
                return;
              }

              final result = await ref
                  .read(revokeAllSessionsUseCaseProvider)
                  .execute();
              if (!context.mounted) {
                return;
              }
              switch (result) {
                case Success<void>():
                  await ref.read(logoutUseCaseProvider).execute();
                  if (context.mounted) {
                    context.go('/login');
                  }
                case FailureResult<void>(failure: final failure):
                  _showSnackBar(context, failure.message);
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Đăng xuất'),
          ),
        ),
      ],
    );
  }
}

Future<bool> _confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

void _showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void _goBackOrHome(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.go('/');
  }
}
