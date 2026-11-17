import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../../auth/presentation/widgets/app_lock_timeout_setting_row.dart';
import '../../../call_privacy/presentation/widgets/call_privacy_setting_row.dart';
import '../../../mfa/presentation/mfa_settings_screen.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/mobile_release_policy.dart';
import '../controllers/app_settings_controller.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
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
      // Nền trang trùng nền các dòng (sáng: trắng; tối: nền tối) để màn liền
      // một mảng như app, không lộ dải xám giữa các nhóm như trang web.
      backgroundColor: WebTuiColors.page,
      appBar: AppBar(
        title: Text(strings.appSettingsTitle),
        backgroundColor: WebTuiColors.page,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: WebTuiSpacing.xl),
          children: [
            _SettingsSection(
              label: strings.sectionAppearance,
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
                _LanguageRow(
                  languageCode: settings.languageCode,
                  onChanged: (value) {
                    controller.update(
                      settings.copyWith(languageCode: value),
                      workspaceId: workspaceId,
                    );
                  },
                ),
              ],
            ),
            _SettingsSection(
              label: strings.sectionNotifications,
              children: [
                WebTuiSettingRow(
                  title: strings.systemNotificationPermission,
                  subtitle: _notificationPermissionLabel(
                    strings,
                    notificationPermission.valueOrNull,
                  ),
                  icon: WebTuiIcons.notificationPermission,
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
                                ? strings.recheck
                                : strings.allow,
                          ),
                        ),
                ),
                WebTuiSettingRow(
                  title: strings.receiveNotifications,
                  subtitle: strings.receiveNotificationsSubtitle,
                  icon: WebTuiIcons.bell,
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
                  title: strings.hideSensitivePreview,
                  subtitle: strings.hideSensitivePreviewSubtitle,
                  icon: WebTuiIcons.hidePreview,
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
                  title: strings.quietHours,
                  subtitle: '${settings.quietStart} - ${settings.quietEnd}',
                  icon: WebTuiIcons.quietHours,
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
            _SettingsSection(
              label: strings.sectionCalls,
              children: [
                WebTuiSettingRow(
                  title: strings.muteMicOnJoin,
                  subtitle: strings.muteMicOnJoinSubtitle,
                  icon: WebTuiIcons.micOff,
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
                  title: strings.cameraOffOnJoin,
                  subtitle: strings.cameraOffOnJoinSubtitle,
                  icon: WebTuiIcons.videoOff,
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
            _SettingsSection(
              label: strings.sectionAppSecurity,
              children: [
                WebTuiSettingRow(
                  title: strings.appLock,
                  subtitle: strings.appLockSubtitle,
                  icon: WebTuiIcons.lock,
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
                const AppLockTimeoutSettingRow(),
                if (ref
                        .watch(activeServerDiscoveryProvider)
                        ?.capabilities
                        .mfa ==
                    true)
                  WebTuiSettingRow(
                    title: strings.totpTitle,
                    subtitle: strings.totpSubtitle,
                    icon: WebTuiIcons.shieldCheck,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MfaSettingsScreen(),
                      ),
                    ),
                  ),
                CallPrivacySettingRow(workspaceId: workspaceId),
              ],
            ),
            _SettingsSection(
              label: strings.sectionOfflineData,
              children: [
                WebTuiSettingRow(
                  title: strings.clearWorkspaceCache,
                  subtitle: strings.clearWorkspaceCacheSubtitle,
                  icon: WebTuiIcons.clearCache,
                  trailing: TextButton(
                    onPressed: workspaceId == null
                        ? null
                        : () => controller.clearWorkspaceCache(workspaceId),
                    child: Text(strings.delete),
                  ),
                ),
              ],
            ),
            _SettingsSection(
              label: strings.sectionFeedback,
              children: [
                WebTuiSettingRow(
                  title: strings.sendFeedback,
                  subtitle: strings.sendFeedbackSubtitle,
                  icon: WebTuiIcons.feedback,
                  onTap: () => context.push('/feedback'),
                ),
              ],
            ),
            _SettingsSection(
              label: strings.sectionVersion,
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
                      SnackBar(content: Text(strings.cannotOpenUpdateLink)),
                    );
                  },
                ),
                if (state.releaseErrorMessage != null)
                  WebTuiSettingRow(
                    title: strings.checkFailed,
                    subtitle: state.releaseErrorMessage!,
                    icon: WebTuiIcons.warning,
                  ),
              ],
            ),
            if (state.errorMessage != null)
              WebTuiErrorState(
                title: strings.settingsSaveFailed,
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
  final strings = context.strings;
  final message = switch (permission) {
    'granted' => strings.notifGranted,
    'provisional' => strings.notifProvisional,
    'denied' => strings.notifDenied,
    _ => strings.notifUnknown,
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _notificationPermissionLabel(AppStrings strings, String? permission) {
  return switch (permission) {
    'granted' => strings.notifLabelGranted,
    'provisional' => strings.notifLabelProvisional,
    'denied' => strings.notifLabelDenied,
    'unknown' || null => strings.notifLabelAsk,
    _ => strings.notifLabelOther,
  };
}

Future<void> _setAppLock(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  final strings = context.strings;
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
      reason: strings.authToDisableLock,
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
          : strings.pinVerifyFailed;
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
  final strings = context.strings;
  final pinController = TextEditingController();
  final confirmationController = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      String? error;
      return StatefulBuilder(
        builder: (context, setState) => WebTuiDialog(
          title: strings.enableAppLockTitle,
          icon: WebTuiIcons.lock,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebTuiDialogTextField(
                controller: pinController,
                label: strings.pinLabel,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                prefixIcon: WebTuiIcons.key,
              ),
              const SizedBox(height: 12),
              WebTuiDialogTextField(
                controller: confirmationController,
                label: strings.pinRepeat,
                obscureText: true,
                keyboardType: TextInputType.number,
                prefixIcon: WebTuiIcons.key,
                errorText: error,
              ),
            ],
          ),
          actions: [
            WebTuiDialogAction(
              label: strings.cancel,
              onPressed: () => Navigator.pop(dialogContext),
            ),
            WebTuiDialogAction(
              label: strings.enableLock,
              primary: true,
              onPressed: () {
                final pin = pinController.text.trim();
                if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
                  setState(() => error = strings.pinInvalid);
                  return;
                }
                if (pin != confirmationController.text.trim()) {
                  setState(() => error = strings.pinMismatch);
                  return;
                }
                Navigator.pop(dialogContext, pin);
              },
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
  final strings = context.strings;
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => WebTuiDialog(
      title: strings.confirmPinTitle,
      icon: WebTuiIcons.lock,
      content: WebTuiDialogTextField(
        controller: controller,
        label: strings.currentPin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        prefixIcon: WebTuiIcons.key,
        onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
      ),
      actions: [
        WebTuiDialogAction(
          label: strings.cancel,
          onPressed: () => Navigator.pop(dialogContext),
        ),
        WebTuiDialogAction(
          label: strings.confirm,
          primary: true,
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
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
    final strings = context.strings;
    final updateRequired = policy?.requiresUpdate == true;
    final updateRecommended = policy?.recommendsUpdate == true;
    final updateUrl = _updateUrl(policy);
    return WebTuiSettingRow(
      title: updateRequired
          ? strings.updateRequired
          : updateRecommended
          ? strings.updateAvailable
          : strings.appUpToDate,
      subtitle: policy == null
          ? strings.versionCheckHint
          : _releaseSubtitle(policy!),
      icon: updateRequired ? WebTuiIcons.update : WebTuiIcons.upToDate,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (updateRecommended && updateUrl != null)
            TextButton(
              onPressed: () => onOpenUpdate(updateUrl),
              child: Text(updateRequired ? strings.mandatory : strings.update),
            )
          else
            TextButton(
              onPressed: isChecking ? null : onCheck,
              child: Text(isChecking ? strings.checking : strings.check),
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
    final strings = context.strings;
    final options = <(WebTuiThemePreference, String)>[
      (WebTuiThemePreference.system, strings.themeSystem),
      (WebTuiThemePreference.light, strings.themeLight),
      (WebTuiThemePreference.dark, strings.themeDark),
    ];
    final current = options.firstWhere((option) => option.$1 == settings.theme);
    return WebTuiSettingRow(
      key: const ValueKey('app-settings-theme'),
      title: strings.themeTitle,
      icon: WebTuiIcons.theme,
      value: current.$2,
      onTap: () async {
        final picked = await showSettingsChoiceSheet<WebTuiThemePreference>(
          context: context,
          title: strings.themeTitle,
          selected: settings.theme,
          options: options,
        );
        if (picked != null && picked != settings.theme) onChanged(picked);
      },
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.languageCode, required this.onChanged});

  final String languageCode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final options = <(String, String)>[
      ('vi', strings.languageNameVi),
      ('en', strings.languageNameEn),
    ];
    return WebTuiSettingRow(
      key: const ValueKey('app-settings-language'),
      title: strings.languageTitle,
      icon: WebTuiIcons.language,
      value: languageCode == 'vi'
          ? strings.languageNameVi
          : strings.languageNameEn,
      onTap: () async {
        final picked = await showSettingsChoiceSheet<String>(
          context: context,
          title: strings.languageTitle,
          selected: languageCode,
          options: options,
        );
        if (picked != null && picked != languageCode) onChanged(picked);
      },
    );
  }
}

/// Một nhóm cài đặt trên nền liền: tiêu đề nhóm màu nhấn ngay trên các dòng,
/// các nhóm cách nhau bằng khoảng trắng (không dải xám, không viền khối).
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.xl,
            WebTuiSpacing.lg,
            WebTuiSpacing.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WebTuiTypography.labelSmall.copyWith(
                color: WebTuiColors.primary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        WebTuiListSurface(
          dividerIndent: webTuiSettingDividerIndent,
          children: children,
        ),
      ],
    );
  }
}

/// Bảng chọn một giá trị (chủ đề, ngôn ngữ) trượt từ dưới lên: mỗi lựa chọn
/// một dòng cao 52, lựa chọn hiện tại chữ đậm + dấu tích màu nhấn. Trả giá trị
/// được chọn; đóng bảng thì trả `null`.
Future<T?> showSettingsChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<(T, String)> options,
}) {
  return showWebTuiSheet<T>(
    context: context,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebTuiSheetHeader(title: title),
          for (final (value, label) in options)
            Semantics(
              selected: value == selected,
              button: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('settings-choice-$value'),
                  onTap: () => Navigator.of(sheetContext).pop(value),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: WebTuiSpacing.xl,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: WebTuiTypography.bodyMedium.copyWith(
                                fontSize: 16,
                                color: WebTuiColors.textPrimary,
                                fontWeight: value == selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (value == selected)
                            Icon(
                              WebTuiIcons.check,
                              size: 22,
                              color: WebTuiColors.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: WebTuiSpacing.md),
        ],
      ),
    ),
  );
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
