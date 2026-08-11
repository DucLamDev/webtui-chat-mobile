import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/mobile_release_policy.dart';
import '../controllers/app_settings_controller.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appSettingsControllerProvider);
    final controller = ref.read(appSettingsControllerProvider.notifier);
    final settings = state.settings;
    final appLockEnabled = ref.watch(isAppLockEnabledProvider);
    final workspaceId = ref.watch(
      workspaceControllerProvider.select((value) => value.activeWorkspace?.id),
    );
    final notificationPermission = ref.watch(
      notificationPermissionStatusProvider,
    );
    if (workspaceId?.trim().isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.loadNotificationPreference(workspaceId!);
      });
    }

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        title: const Text('Thiết lập ứng dụng'),
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
            const WebTuiSectionLabel('Giao diện'),
            WebTuiListSurface(
              children: [
                _ThemeRow(
                  settings: settings,
                  onChanged: (theme) {
                    controller.update(
                      settings.copyWith(theme: theme),
                      workspaceId: workspaceId,
                    );
                  },
                ),
                WebTuiSettingRow(
                  title: 'Ngôn ngữ',
                  subtitle: settings.languageCode == 'vi'
                      ? 'Tiếng Việt'
                      : 'English',
                  icon: Icons.language_rounded,
                  trailing: DropdownButton<String>(
                    value: settings.languageCode,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'vi', child: Text('VI')),
                      DropdownMenuItem(value: 'en', child: Text('EN')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        controller.update(
                          settings.copyWith(languageCode: value),
                          workspaceId: workspaceId,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const WebTuiSectionLabel('Thông báo'),
            WebTuiListSurface(
              children: [
                WebTuiSettingRow(
                  title: 'Quyền thông báo hệ thống',
                  subtitle: _notificationPermissionLabel(
                    notificationPermission.valueOrNull,
                  ),
                  icon: Icons.notifications_active_outlined,
                  trailing: notificationPermission.isLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: workspaceId == null
                              ? null
                              : () => _requestNotificationPermission(
                                  context,
                                  ref,
                                  workspaceId,
                                ),
                          child: Text(
                            notificationPermission.valueOrNull == 'granted' ||
                                    notificationPermission.valueOrNull ==
                                        'provisional'
                                ? 'Kiểm tra lại'
                                : 'Cho phép',
                          ),
                        ),
                ),
                WebTuiSettingRow(
                  title: 'Nhận thông báo',
                  subtitle: 'Tin nhắn, kênh và cảnh báo workspace',
                  icon: Icons.notifications_none_rounded,
                  trailing: WebTuiToggle(
                    value: settings.notificationsEnabled,
                    onChanged: (value) async {
                      if (value && workspaceId != null) {
                        await _requestNotificationPermission(
                          context,
                          ref,
                          workspaceId,
                        );
                      }
                      controller.update(
                        settings.copyWith(notificationsEnabled: value),
                        workspaceId: workspaceId,
                      );
                    },
                  ),
                ),
                WebTuiSettingRow(
                  title: 'Ẩn xem trước nhạy cảm',
                  subtitle: 'Không hiện nội dung trong lock screen',
                  icon: Icons.privacy_tip_outlined,
                  trailing: WebTuiToggle(
                    value: settings.sensitivePreviewEnabled,
                    onChanged: (value) {
                      controller.update(
                        settings.copyWith(sensitivePreviewEnabled: value),
                        workspaceId: workspaceId,
                      );
                    },
                  ),
                ),
                WebTuiSettingRow(
                  title: 'Giờ yên lặng',
                  subtitle: '${settings.quietStart} - ${settings.quietEnd}',
                  icon: Icons.bedtime_outlined,
                  trailing: WebTuiToggle(
                    value: settings.quietHoursEnabled,
                    onChanged: (value) {
                      controller.update(
                        settings.copyWith(quietHoursEnabled: value),
                        workspaceId: workspaceId,
                      );
                    },
                  ),
                ),
              ],
            ),
            const WebTuiSectionLabel('Cuộc gọi'),
            WebTuiListSurface(
              children: [
                WebTuiSettingRow(
                  title: 'Tắt mic khi tham gia',
                  subtitle: 'Tránh tiếng ồn bất ngờ khi vào cuộc gọi',
                  icon: Icons.mic_off_outlined,
                  trailing: WebTuiToggle(
                    value: !settings.microphoneEnabledOnJoin,
                    onChanged: (value) {
                      controller.update(
                        settings.copyWith(microphoneEnabledOnJoin: !value),
                        workspaceId: workspaceId,
                      );
                    },
                  ),
                ),
                WebTuiSettingRow(
                  title: 'Tắt camera khi tham gia',
                  subtitle: 'Có thể bật lại sau khi đã vào video call',
                  icon: Icons.videocam_off_outlined,
                  trailing: WebTuiToggle(
                    value: !settings.cameraEnabledOnJoin,
                    onChanged: (value) {
                      controller.update(
                        settings.copyWith(cameraEnabledOnJoin: !value),
                        workspaceId: workspaceId,
                      );
                    },
                  ),
                ),
              ],
            ),
            const WebTuiSectionLabel('Bảo mật ứng dụng'),
            WebTuiListSurface(
              children: [
                WebTuiSettingRow(
                  title: 'Khóa ứng dụng',
                  subtitle:
                      'Yêu cầu PIN hoặc sinh trắc học khi quay lại ứng dụng',
                  icon: Icons.phonelink_lock_rounded,
                  trailing: appLockEnabled.isLoading
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : WebTuiToggle(
                          value: appLockEnabled.valueOrNull ?? false,
                          onChanged: (value) =>
                              _setAppLock(context, ref, value),
                        ),
                ),
              ],
            ),
            const WebTuiSectionLabel('Dữ liệu offline'),
            WebTuiListSurface(
              children: [
                WebTuiSettingRow(
                  title: 'Xóa cache workspace',
                  subtitle: 'Chỉ xóa dữ liệu đọc gần nhất, giữ draft và outbox',
                  icon: Icons.cleaning_services_outlined,
                  trailing: TextButton(
                    onPressed: workspaceId == null
                        ? null
                        : () => controller.clearWorkspaceCache(workspaceId),
                    child: const Text('Xóa'),
                  ),
                ),
              ],
            ),
            const WebTuiSectionLabel('Phiên bản'),
            WebTuiListSurface(
              children: [
                _ReleasePolicyRow(
                  policy: state.mobileReleasePolicy,
                  isChecking: state.isCheckingRelease,
                  onCheck: controller.checkReleasePolicy,
                  onOpenUpdate: (url) async {
                    final opened = await ref
                        .read(externalUrlLauncherProvider)
                        .open(url);
                    if (!context.mounted || opened) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Không mở được link cập nhật.'),
                      ),
                    );
                  },
                ),
                if (state.releaseErrorMessage != null)
                  WebTuiSettingRow(
                    title: 'Không kiểm tra được',
                    subtitle: state.releaseErrorMessage!,
                    icon: Icons.warning_amber_rounded,
                  ),
              ],
            ),
            if (state.errorMessage != null)
              WebTuiErrorState(
                title: 'Không lưu được thiết lập',
                message: state.errorMessage!,
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _requestNotificationPermission(
  BuildContext context,
  WidgetRef ref,
  String workspaceId,
) async {
  final permission = await ref
      .read(pushNotificationServiceProvider)
      .requestNotificationPermissionForWorkspace(workspaceId);
  ref.invalidate(notificationPermissionStatusProvider);
  if (!context.mounted) {
    return;
  }
  final message = switch (permission) {
    'granted' => 'Đã bật thông báo hệ thống.',
    'provisional' => 'Thông báo tạm thời đã được bật.',
    'denied' =>
      'Quyền thông báo đang bị từ chối. Hãy bật trong Cài đặt hệ thống.',
    _ => 'Không xác định được trạng thái quyền thông báo.',
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _notificationPermissionLabel(String? permission) {
  return switch (permission) {
    'granted' => 'Đã cho phép thông báo tin nhắn và cuộc gọi',
    'provisional' => 'Đang cho phép thông báo tạm thời',
    'denied' => 'Đã từ chối trong cài đặt hệ thống',
    'unknown' || null => 'Chỉ hỏi quyền khi bạn chọn Cho phép',
    _ => 'Trạng thái chưa xác định',
  };
}

Future<void> _setAppLock(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  if (enabled) {
    final pin = await _promptNewPin(context);
    if (pin == null || !context.mounted) {
      return;
    }
    final result = await ref.read(enableAppLockUseCaseProvider).execute(pin);
    if (!context.mounted) {
      return;
    }
    switch (result) {
      case Success<void>():
        ref.invalidate(isAppLockEnabledProvider);
      case FailureResult<void>(failure: final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
    return;
  }

  var authorized = false;
  final biometrics = ref.read(biometricAuthServiceProvider);
  if (await biometrics.isAvailable()) {
    authorized = await biometrics.authenticate(
      reason: 'Xác thực để tắt khóa ứng dụng',
    );
  }
  if (!authorized && context.mounted) {
    final pin = await _promptCurrentPin(context);
    if (pin == null) {
      return;
    }
    final verification = await ref.read(unlockAppUseCaseProvider).execute(pin);
    authorized = verification is Success<void>;
    if (!authorized && context.mounted) {
      final message = verification is FailureResult<void>
          ? verification.failure.message
          : 'Không thể xác minh mã PIN.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
  if (!authorized) {
    return;
  }
  await ref.read(disableAppLockUseCaseProvider).execute();
  ref.invalidate(isAppLockEnabledProvider);
}

Future<String?> _promptNewPin(BuildContext context) {
  final pinController = TextEditingController();
  final confirmationController = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      String? error;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Bật khóa ứng dụng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinController,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'PIN (4-12 số)'),
              ),
              TextField(
                controller: confirmationController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nhập lại PIN'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final pin = pinController.text.trim();
                if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
                  setState(() => error = 'PIN phải gồm 4-12 chữ số.');
                  return;
                }
                if (pin != confirmationController.text.trim()) {
                  setState(() => error = 'Hai mã PIN không khớp.');
                  return;
                }
                Navigator.pop(dialogContext, pin);
              },
              child: const Text('Bật khóa'),
            ),
          ],
        ),
      );
    },
  ).whenComplete(() {
    pinController.dispose();
    confirmationController.dispose();
  });
}

Future<String?> _promptCurrentPin(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Xác nhận mã PIN'),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Mã PIN hiện tại'),
        onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Xác nhận'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _ReleasePolicyRow extends StatelessWidget {
  const _ReleasePolicyRow({
    required this.policy,
    required this.isChecking,
    required this.onCheck,
    required this.onOpenUpdate,
  });

  final MobileReleasePolicy? policy;
  final bool isChecking;
  final VoidCallback onCheck;
  final ValueChanged<String> onOpenUpdate;

  @override
  Widget build(BuildContext context) {
    final updateRequired = policy?.requiresUpdate == true;
    final updateRecommended = policy?.recommendsUpdate == true;
    final updateUrl = _updateUrl(policy);
    return WebTuiSettingRow(
      title: updateRequired
          ? 'Cần cập nhật ứng dụng'
          : updateRecommended
          ? 'Có bản cập nhật mới'
          : 'Ứng dụng hiện tại',
      subtitle: policy == null
          ? 'Kiểm tra version gate từ backend'
          : _releaseSubtitle(policy!),
      icon: updateRequired
          ? Icons.system_update_alt_rounded
          : Icons.verified_outlined,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (updateRecommended && updateUrl != null)
            TextButton(
              onPressed: () => onOpenUpdate(updateUrl),
              child: Text(updateRequired ? 'Bắt buộc' : 'Cập nhật'),
            )
          else
            TextButton(
              onPressed: isChecking ? null : onCheck,
              child: Text(isChecking ? 'Đang kiểm tra' : 'Kiểm tra'),
            ),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.settings, required this.onChanged});

  final AppSettings settings;
  final ValueChanged<WebTuiThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    return WebTuiSettingRow(
      title: 'Chủ đề',
      subtitle: switch (settings.theme) {
        WebTuiThemePreference.system => 'Theo hệ thống',
        WebTuiThemePreference.light => 'Sáng',
        WebTuiThemePreference.dark => 'Tối',
      },
      icon: Icons.palette_outlined,
      trailing: DropdownButton<WebTuiThemePreference>(
        value: settings.theme,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(
            value: WebTuiThemePreference.system,
            child: Text('Hệ thống'),
          ),
          DropdownMenuItem(
            value: WebTuiThemePreference.light,
            child: Text('Sáng'),
          ),
          DropdownMenuItem(
            value: WebTuiThemePreference.dark,
            child: Text('Tối'),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }
}

String _releaseSubtitle(MobileReleasePolicy policy) {
  final target = policy.minimumVersion?.trim().isNotEmpty == true
      ? 'min ${policy.minimumVersion}'
      : 'recommended ${policy.recommendedVersion ?? policy.currentVersion}';
  return '${policy.platform}/${policy.channel} ${policy.currentVersion} - $target';
}

String? _updateUrl(MobileReleasePolicy? policy) {
  final storeUrl = policy?.storeUrl?.trim();
  if (storeUrl != null && storeUrl.isNotEmpty) {
    return storeUrl;
  }
  final downloadUrl = policy?.downloadUrl?.trim();
  if (downloadUrl != null && downloadUrl.isNotEmpty) {
    return downloadUrl;
  }
  return null;
}
