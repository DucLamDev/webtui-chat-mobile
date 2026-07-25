import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
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
    final workspaceId = ref.watch(
      workspaceControllerProvider.select((value) => value.activeWorkspace?.id),
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
                  title: 'Nhận thông báo',
                  subtitle: 'Tin nhắn, kênh và cảnh báo workspace',
                  icon: Icons.notifications_none_rounded,
                  trailing: WebTuiToggle(
                    value: settings.notificationsEnabled,
                    onChanged: (value) {
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
