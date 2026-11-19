import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/avatar_upload.dart';
import '../../domain/entities/user_profile.dart';
import '../controllers/profile_controller.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _localeController = TextEditingController();
  final _timezoneController = TextEditingController();
  final _titleController = TextEditingController();
  String? _boundProfileId;

  @override
  void initState() {
    super.initState();
    // Hồ sơ có thể đã nạp sẵn trước khi mở màn: `ref.listen` sẽ không chạy.
    _bind(ref.read(profileControllerProvider).profile);
  }

  /// Điền ô một lần cho mỗi hồ sơ; tải lại cùng hồ sơ không đè chữ đang sửa.
  void _bind(UserProfile? profile) {
    if (profile == null || _boundProfileId == profile.id) return;
    _boundProfileId = profile.id;
    _displayNameController.text = profile.displayName;
    _phoneController.text = profile.phoneNumber ?? '';
    _localeController.text = profile.locale;
    _timezoneController.text = profile.timezone;
    _titleController.text = profile.work.title ?? '';
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _localeController.dispose();
    _timezoneController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profileControllerProvider, (_, next) => _bind(next.profile));

    final state = ref.watch(profileControllerProvider);
    final controller = ref.read(profileControllerProvider.notifier);
    final profile = state.profile;
    final strings = context.strings;

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.7)),
        ),
        leading: IconButton(
          tooltip: strings.back,
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
              return;
            }
            context.go('/');
          },
          icon: const Icon(CupertinoIcons.back),
        ),
        title: Text(strings.profileTitle),
        actions: [
          IconButton(
            tooltip: strings.save,
            onPressed: state.isSaving || profile == null
                ? null
                : () => controller.save(
                    displayName: _displayNameController.text,
                    phoneNumber: _phoneController.text,
                    locale: _localeController.text,
                    timezone: _timezoneController.text,
                    title: _titleController.text,
                  ),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (state.isLoading && profile == null) {
              return WebTuiLoadingState(message: strings.profileLoading);
            }
            if (state.errorMessage != null && profile == null) {
              return WebTuiErrorState(
                title: strings.profileLoadFailed,
                message: state.errorMessage!,
                onRetry: controller.load,
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                WebTuiSpacing.md,
                WebTuiSpacing.lg,
                WebTuiSpacing.xl,
              ),
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: WebTuiColors.surface,
                    borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                    border: Border.all(color: WebTuiColors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(WebTuiSpacing.lg),
                    child: Row(
                      children: [
                        WebTuiAvatar(
                          label: profile?.displayName ?? 'WebTui',
                          imageUrl: profile?.avatarUrl,
                          gender: WebTuiAvatarGender.parse(profile?.gender),
                          size: 68,
                          status: WebTuiPresenceStatus.online,
                        ),
                        const SizedBox(width: WebTuiSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?.displayName ?? 'WebTui',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WebTuiTypography.titleMedium.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (profile != null) ...[
                                const SizedBox(height: WebTuiSpacing.xs),
                                Text(
                                  '${profile.email} · @${profile.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: WebTuiTypography.bodySmall.copyWith(
                                    color: WebTuiColors.textMuted,
                                  ),
                                ),
                                if (!profile.work.isEmpty) ...[
                                  const SizedBox(height: WebTuiSpacing.xs),
                                  Text(
                                    profile.work.summary,
                                    key: const Key('profile_work_summary'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: WebTuiTypography.bodySmall.copyWith(
                                      color: WebTuiColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: strings.changeAvatar,
                          onPressed: state.isSaving
                              ? null
                              : () => _showAvatarSheet(context, controller),
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: WebTuiSpacing.lg),
                _ProfileField(
                  label: strings.fieldDisplayName,
                  controller: _displayNameController,
                  icon: Icons.badge_outlined,
                ),
                _ProfileField(
                  label: strings.fieldJobTitle,
                  controller: _titleController,
                  icon: Icons.work_outline_rounded,
                ),
                if (profile != null)
                  _GenderField(
                    value: profile.gender,
                    enabled: !state.isSaving,
                    onChanged: controller.changeGender,
                  ),
                _ProfileField(
                  label: strings.fieldPhone,
                  controller: _phoneController,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                _ProfileField(
                  label: strings.fieldLanguage,
                  controller: _localeController,
                  icon: Icons.language_rounded,
                ),
                _ProfileField(
                  label: strings.fieldTimezone,
                  controller: _timezoneController,
                  icon: Icons.schedule_rounded,
                ),
                if (state.errorMessage != null)
                  _MessageBanner(message: state.errorMessage!, error: true),
                if (state.successMessage != null)
                  _MessageBanner(message: state.successMessage!),
                const SizedBox(height: WebTuiSpacing.lg),
                WebTuiSectionLabel(strings.accountSecurityGroup),
                WebTuiListSurface(
                  children: [
                    WebTuiSettingRow(
                      key: const Key('profile_account_security_row'),
                      title: strings.accountSecurityTitle,
                      subtitle: strings.accountSecuritySubtitle,
                      icon: Icons.account_circle_outlined,
                      onTap: () => context.push('/privacy'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

void _showAvatarSheet(BuildContext context, ProfileController controller) {
  final strings = context.strings;
  showWebTuiSheet<void>(
    context: context,
    builder: (context) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebTuiSheetHeader(title: strings.avatarSheetTitle),
          WebTuiSheetActionTile(
            title: strings.takePhoto,
            icon: WebTuiIcons.image,
            onTap: () {
              Navigator.of(context).pop();
              controller.changeAvatar(AvatarPickerSource.camera);
            },
          ),
          WebTuiSheetActionTile(
            title: strings.pickFromLibrary,
            icon: WebTuiIcons.imageFile,
            onTap: () {
              Navigator.of(context).pop();
              controller.changeAvatar(AvatarPickerSource.gallery);
            },
          ),
          const SizedBox(height: 8),
        ],
      );
    },
  );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          filled: true,
          fillColor: WebTuiColors.surface,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _GenderField extends StatelessWidget {
  const _GenderField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected =
        value == 'male' || value == 'female' || value == 'unspecified'
        ? value
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
            child: Text(
              tr('Giới tính', 'Gender'),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              key: const Key('profile_gender_field'),
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 'male',
                  label: Text(tr('Nam', 'Male'), maxLines: 1),
                ),
                ButtonSegment(
                  value: 'female',
                  label: Text(tr('Nữ', 'Female'), maxLines: 1),
                ),
                ButtonSegment(
                  value: 'unspecified',
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tr('Không muốn nói', 'Prefer not to say'),
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
              selected: {?selected},
              onSelectionChanged: enabled
                  ? (values) {
                      if (values.isNotEmpty) onChanged(values.first);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: WebTuiSpacing.md),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: WebTuiTypography.bodySmall.copyWith(
          color: error ? WebTuiColors.danger : WebTuiColors.accentGreen,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
