import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
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

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Mỗi lần mở màn: tính lại dung lượng kho tệp trên máy.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appSettingsControllerProvider.notifier).measureMediaCache();
    });
  }

  @override
  Widget build(BuildContext context) {
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

    // Sáng: nền xám nhạt, mỗi nhóm một thẻ trắng bo góc (kiểu Cài đặt
    // iPhone). Tối: nền trang trùng nền các dòng, liền một mảng.
    final pageColor = _settingsPageColor();
    return Scaffold(
      backgroundColor: pageColor,
      appBar: AppBar(
        title: Text(strings.appSettingsTitle),
        backgroundColor: pageColor,
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
                  icon: WebTuiIcons.notificationPermission,
                  trailing: notificationPermission.isLoading
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : SettingsActionButton(
                          label:
                              notificationPermission.valueOrNull == 'granted' ||
                                  notificationPermission.valueOrNull ==
                                      'provisional'
                              ? strings.recheck
                              : strings.allow,
                          onPressed: workspaceId == null
                              ? null
                              : () => _requestNotificationPermission(
                                  context,
                                  ref,
                                  workspaceId,
                                ),
                        ),
                ),
                WebTuiSettingRow(
                  title: strings.receiveNotifications,
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
                  value: '${settings.quietStart} – ${settings.quietEnd}',
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
                // Dòng tự ẩn (trả SizedBox) vẫn sinh đường kẻ trong thẻ, nên
                // chỉ thêm khi chắc chắn hiện.
                if (appLockEnabled.valueOrNull == true)
                  const AppLockTimeoutSettingRow(),
                if (ref
                        .watch(activeServerDiscoveryProvider)
                        ?.capabilities
                        .mfa ==
                    true)
                  WebTuiSettingRow(
                    title: strings.totpTitle,
                    icon: WebTuiIcons.shieldCheck,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MfaSettingsScreen(),
                      ),
                    ),
                  ),
                if (workspaceId?.trim().isNotEmpty == true)
                  CallPrivacySettingRow(workspaceId: workspaceId),
              ],
            ),
            _SettingsSection(
              label: tr('Dung lượng và tải tự động', 'Storage and downloads'),
              children: [
                _MediaCacheSizeRow(
                  state: state,
                  onRetry: controller.measureMediaCache,
                ),
                WebTuiSettingRow(
                  key: const ValueKey('app-settings-clear-media-cache'),
                  title: tr('Xóa bộ nhớ đệm', 'Clear cache'),
                  icon: WebTuiIcons.clearCache,
                  trailing: SettingsActionButton(
                    label: state.isClearingMediaCache
                        ? tr('Đang xóa…', 'Clearing…')
                        : strings.delete,
                    onPressed: state.isClearingMediaCache
                        ? null
                        : () => _clearMediaCache(context, controller),
                  ),
                ),
                WebTuiSettingRow(
                  key: const ValueKey('app-settings-auto-download-cellular'),
                  title: tr('Tự tải ảnh khi dùng 4G', 'Auto-load photos on 4G'),
                  subtitle: tr(
                    'Khi dùng dữ liệu di động. Tắt thì chạm vào ảnh mới tải.',
                    'On mobile data. When off, tap a photo to load it.',
                  ),
                  icon: WebTuiIcons.download,
                  trailing: WebTuiToggle(
                    value: settings.autoDownloadMediaOnCellular,
                    onChanged: (value) {
                      controller.update(
                        settings.copyWith(autoDownloadMediaOnCellular: value),
                        workspaceId: workspaceId,
                      );
                    },
                  ),
                ),
              ],
            ),
            _SettingsSection(
              label: strings.sectionOfflineData,
              children: [
                WebTuiSettingRow(
                  title: strings.clearWorkspaceCache,
                  icon: WebTuiIcons.clearCache,
                  trailing: SettingsActionButton(
                    label: strings.delete,
                    onPressed: workspaceId == null
                        ? null
                        : () => controller.clearWorkspaceCache(workspaceId),
                  ),
                ),
              ],
            ),
            _SettingsSection(
              label: strings.sectionFeedback,
              children: [
                WebTuiSettingRow(
                  title: strings.sendFeedback,
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

/// Hỏi xác nhận rồi xoá kho tệp trên máy của tài khoản; báo kết quả.
Future<void> _clearMediaCache(
  BuildContext context,
  AppSettingsController controller,
) async {
  final confirmed = await showWebTuiConfirmDialog(
    context,
    title: tr('Xóa bộ nhớ đệm?', 'Clear cache?'),
    message: tr(
      'Ảnh, video, tin thoại và tệp đã tải về máy sẽ bị xóa, khi mở lại sẽ '
          'tải lại từ máy chủ. Tin nhắn và tài khoản vẫn giữ nguyên.',
      'Downloaded photos, videos, voice messages and files will be removed '
          'from this device and downloaded again when opened. Your messages '
          'and account stay as they are.',
    ),
    confirmLabel: tr('Xóa', 'Clear'),
    destructive: true,
    icon: WebTuiIcons.clearCache,
  );
  if (!confirmed || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final cleared = await controller.clearMediaCache();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        cleared
            ? tr('Đã xóa bộ nhớ đệm', 'Cache cleared')
            : tr(
                'Không xóa được bộ nhớ đệm. Thử lại sau.',
                'Couldn\'t clear the cache. Try again later.',
              ),
      ),
    ),
  );
}

/// Dòng "Dung lượng lưu trên máy": đang tính / đang xoá thì vòng xoay, lỗi
/// thì báo và chạm để tính lại.
class _MediaCacheSizeRow extends StatelessWidget {
  const _MediaCacheSizeRow({required this.state, required this.onRetry});

  final AppSettingsState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final busy = state.isMeasuringMediaCache || state.isClearingMediaCache;
    final error = state.mediaCacheErrorMessage;
    final bytes = state.mediaCacheBytes;
    return WebTuiSettingRow(
      key: const ValueKey('app-settings-media-cache-size'),
      title: tr('Dung lượng lưu trên máy', 'Storage on this device'),
      subtitle:
          error ??
          tr(
            'Ảnh, video, tin thoại và tệp đã tải',
            'Downloaded photos, videos, voice and files',
          ),
      icon: error == null ? WebTuiIcons.storage : WebTuiIcons.warning,
      value: busy
          ? null
          : bytes == null
          ? (error == null ? null : '—')
          : formatStorageBytes(bytes),
      trailing: busy
          ? SizedBox.square(
              key: const ValueKey('app-settings-media-cache-busy'),
              dimension: 20,
              child: Semantics(
                label: state.isClearingMediaCache
                    ? tr('Đang xóa', 'Clearing')
                    : tr('Đang tính dung lượng', 'Calculating storage'),
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
      showChevron: false,
      onTap: busy ? null : onRetry,
    );
  }
}

/// Dung lượng dễ đọc: "0 B", "512 KB", "12,3 MB", "1,2 GB" (tiếng Việt dùng
/// dấu phẩy thập phân).
String formatStorageBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes < 0 ? 0.0 : bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final text = unit == 0 || value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '${tr(text.replaceAll('.', ','), text)} ${units[unit]}';
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
      icon: updateRequired ? WebTuiIcons.update : WebTuiIcons.upToDate,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (updateRecommended && updateUrl != null)
            SettingsActionButton(
              label: updateRequired ? strings.mandatory : strings.update,
              onPressed: () => onOpenUpdate(updateUrl),
            )
          else
            SettingsActionButton(
              label: isChecking ? strings.checking : strings.check,
              onPressed: isChecking ? null : onCheck,
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

Color _settingsPageColor() => WebTuiColors.brightness == Brightness.light
    ? WebTuiColors.groupBackground
    : WebTuiColors.page;

/// Một nhóm cài đặt. Tiêu đề nhóm chữ nhỏ màu xám (không dùng màu nhấn).
/// Sáng: các dòng nằm trong thẻ trắng bo góc, cách mép 16. Tối: các dòng
/// liền nền trang, các nhóm cách nhau bằng khoảng trống.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final grouped = WebTuiColors.brightness == Brightness.light;
    final inset = grouped ? WebTuiSpacing.lg : 0.0;
    final rows = WebTuiListSurface(
      dividerIndent: webTuiSettingDividerIndent,
      children: children,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            inset + WebTuiSpacing.lg,
            WebTuiSpacing.xxl,
            inset + WebTuiSpacing.lg,
            WebTuiSpacing.sm,
          ),
          child: Semantics(
            header: true,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WebTuiTypography.labelSmall.copyWith(
                color: WebTuiColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ),
        if (grouped)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: ClipRRect(
              key: const Key('settings_section_card'),
              borderRadius: BorderRadius.circular(WebTuiRadii.md),
              child: rows,
            ),
          )
        else
          rows,
      ],
    );
  }
}

/// Nút hành động ở cuối dòng cài đặt (Cho phép, Xóa, Kiểm tra...): viên
/// thuốc nền xám nhạt, chữ đậm màu chữ chính, cao 32 (vùng bấm 44). Không
/// dùng chữ xanh trơn như nút web. `onPressed` null thì chữ nhạt, không bấm.
class SettingsActionButton extends StatelessWidget {
  const SettingsActionButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(
          widthFactor: 1,
          child: Material(
            color: WebTuiColors.chipBackground,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  style: WebTuiTypography.labelSmall.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? WebTuiColors.textPrimary
                        : WebTuiColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
