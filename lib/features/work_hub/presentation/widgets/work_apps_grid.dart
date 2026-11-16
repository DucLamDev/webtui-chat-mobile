import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_seamless.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../application/use_cases/work_hub_use_cases.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/work_hub_providers.dart';
import 'shortcut_form_sheet.dart';
import 'work_common.dart';

/// Mở lối tắt bằng trình duyệt ngoài (chỉ https).
Future<void> openAppShortcut(
  BuildContext context,
  WidgetRef ref,
  AppShortcut shortcut,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (validateShortcutUrl(shortcut.url) != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Đường dẫn lối tắt không hợp lệ.',
            'The shortcut link isn\'t valid.',
          ),
        ),
      ),
    );
    return;
  }
  final opened = await ref
      .read(externalUrlLauncherProvider)
      .open(shortcut.url.trim());
  if (!opened) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr('Không mở được liên kết này.', 'Couldn\'t open this link.'),
        ),
      ),
    );
  }
}

/// Màu biểu tượng Lịch họp (cam) theo nền sáng / tối.
Color get workMeetingsAppColor => WebTuiColors.brightness == Brightness.dark
    ? const Color(0xFFFF9A5C)
    : const Color(0xFFE8692A);

/// Màu biểu tượng Tệp chia sẻ (xanh lá) theo nền sáng / tối.
Color get workSharedFilesAppColor => WebTuiColors.brightness == Brightness.dark
    ? const Color(0xFF3CCF89)
    : const Color(0xFF1E9A57);

/// Một ô thêm vào lưới Ứng dụng từ ngoài (vd tiện ích My Note), đứng sau Lịch
/// họp và Tệp chia sẻ, trước lối tắt.
final class WorkAppItem {
  const WorkAppItem({
    required this.key,
    required this.glyph,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Key key;
  final PhosphorDuotoneGlyph glyph;
  final Color color;
  final String label;
  final VoidCallback onTap;
}

/// Nhóm "Ứng dụng": lưới 4 cột biểu tượng hai lớp + nhãn, không ô nền: Lịch
/// họp, Tệp chia sẻ, [extraApps], lối tắt quản trị thêm, ô Thêm.
class WorkAppsSection extends ConsumerWidget {
  const WorkAppsSection({
    required this.workspaceId,
    this.extraApps = const [],
    super.key,
  });

  final String workspaceId;
  final List<WorkAppItem> extraApps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workHub = ref.watch(workHubEnabledProvider);
    final shortcuts = ref.watch(appShortcutsProvider(workspaceId));
    final list = shortcuts.valueOrNull;
    final canManage = list?.canManage ?? false;
    final items = <Widget>[
      if (workHub)
        _AppTile(
          key: const Key('app_meetings'),
          glyph: WebTuiDuotoneIcons.meetings,
          label: tr('Lịch họp', 'Meetings'),
          color: workMeetingsAppColor,
          onTap: () => context.push(
            Uri(
              path: '/meetings',
              queryParameters: {'workspaceId': workspaceId},
            ).toString(),
          ),
        ),
      _AppTile(
        key: const Key('app_shared_files'),
        glyph: WebTuiDuotoneIcons.sharedFiles,
        label: tr('Tệp chia sẻ', 'Shared files'),
        color: workSharedFilesAppColor,
        onTap: () => context.push(
          Uri(
            path: '/files',
            queryParameters: {'workspaceId': workspaceId},
          ).toString(),
        ),
      ),
      for (final app in extraApps)
        _AppTile(
          key: app.key,
          glyph: app.glyph,
          label: app.label,
          color: app.color,
          onTap: app.onTap,
        ),
      for (final shortcut in list?.shortcuts ?? const <AppShortcut>[])
        _AppTile(
          key: Key('app_shortcut_${shortcut.id}'),
          glyph: webTuiShortcutDuotoneIcon(shortcut.icon),
          label: shortcut.title,
          color: webTuiShortcutColors(shortcut.color).foreground,
          onTap: () => openAppShortcut(context, ref, shortcut),
        ),
      if (canManage)
        _AppTile(
          key: const Key('app_add'),
          glyph: WebTuiDuotoneIcons.add,
          label: tr('Thêm', 'Add'),
          color: WebTuiColors.textMuted,
          onTap: () => _add(context, ref),
        ),
    ];
    return Column(
      key: const Key('work_apps_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebTuiGroupHeader(
          title: tr('Ứng dụng', 'Apps'),
          actionLabel: canManage ? tr('Quản lý', 'Manage') : null,
          actionKey: const Key('apps_manage'),
          onAction: () => context.push(
            Uri(
              path: '/shortcuts',
              queryParameters: {'workspaceId': workspaceId},
            ).toString(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(0.0, constraints.maxWidth / 4);
              return Wrap(
                runSpacing: 6,
                children: [
                  for (final item in items) SizedBox(width: width, child: item),
                ],
              );
            },
          ),
        ),
        if (workHub && shortcuts.hasError)
          WorkSeamlessError(
            message: workHubErrorText(shortcuts.error!),
            onRetry: () => ref.invalidate(appShortcutsProvider),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final saved = await showShortcutFormSheet(
      context,
      workspaceId: workspaceId,
    );
    if (saved == true) ref.invalidate(appShortcutsProvider);
  }
}

/// Cỡ biểu tượng hai lớp trong lưới Ứng dụng.
const workAppIconSize = 36.0;

/// Một ô ứng dụng: biểu tượng hai lớp 36 (không ô nền) + nhãn 13 bên dưới.
class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.glyph,
    required this.label,
    required this.color,
    required this.onTap,
    super.key,
  });

  final PhosphorDuotoneGlyph glyph;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WebTuiDuotoneIcon(glyph, color: color, size: workAppIconSize),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodySmall.copyWith(
                  fontSize: 13,
                  height: 1.25,
                  color: WebTuiColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
