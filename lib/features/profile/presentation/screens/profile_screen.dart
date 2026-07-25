import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/avatar_upload.dart';
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
  String? _boundProfileId;

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _localeController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profileControllerProvider, (_, next) {
      final profile = next.profile;
      if (profile != null && _boundProfileId != profile.id) {
        _boundProfileId = profile.id;
        _displayNameController.text = profile.displayName;
        _phoneController.text = profile.phoneNumber ?? '';
        _localeController.text = profile.locale;
        _timezoneController.text = profile.timezone;
      }
    });

    final state = ref.watch(profileControllerProvider);
    final controller = ref.read(profileControllerProvider.notifier);
    final profile = state.profile;

    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        shape: Border(
          bottom: BorderSide(color: WebTuiColors.border.withValues(alpha: 0.7)),
        ),
        leading: IconButton(
          tooltip: 'Quay lại',
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
        title: const Text('Hồ sơ cá nhân'),
        actions: [
          IconButton(
            tooltip: 'Lưu',
            onPressed: state.isSaving
                ? null
                : () => controller.save(
                    displayName: _displayNameController.text,
                    phoneNumber: _phoneController.text,
                    locale: _localeController.text,
                    timezone: _timezoneController.text,
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
              return const WebTuiLoadingState(message: 'Đang tải hồ sơ...');
            }
            if (state.errorMessage != null && profile == null) {
              return WebTuiErrorState(
                title: 'Không tải được hồ sơ',
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
                              ],
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Đổi ảnh đại diện',
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
                  label: 'Tên hiển thị',
                  controller: _displayNameController,
                  icon: Icons.badge_outlined,
                ),
                _ProfileField(
                  label: 'Số điện thoại',
                  controller: _phoneController,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                _ProfileField(
                  label: 'Ngôn ngữ',
                  controller: _localeController,
                  icon: Icons.language_rounded,
                ),
                _ProfileField(
                  label: 'Múi giờ',
                  controller: _timezoneController,
                  icon: Icons.schedule_rounded,
                ),
                if (state.errorMessage != null)
                  _MessageBanner(message: state.errorMessage!, error: true),
                if (state.successMessage != null)
                  _MessageBanner(message: state.successMessage!),
              ],
            );
          },
        ),
      ),
    );
  }
}

void _showAvatarSheet(BuildContext context, ProfileController controller) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WebTuiSettingRow(
              title: 'Chụp ảnh mới',
              icon: Icons.photo_camera_outlined,
              onTap: () {
                Navigator.of(context).pop();
                controller.changeAvatar(AvatarPickerSource.camera);
              },
            ),
            WebTuiSettingRow(
              title: 'Chọn từ thư viện',
              icon: Icons.photo_library_outlined,
              onTap: () {
                Navigator.of(context).pop();
                controller.changeAvatar(AvatarPickerSource.gallery);
              },
            ),
          ],
        ),
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
