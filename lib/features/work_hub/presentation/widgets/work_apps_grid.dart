import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
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
      const SnackBar(content: Text('Đường dẫn lối tắt không hợp lệ.')),
    );
    return;
  }
  final opened = await ref
      .read(externalUrlLauncherProvider)
      .open(shortcut.url.trim());
  if (!opened) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Không mở được liên kết này.')),
    );
  }
}

/// Khối "Ứng dụng": Lịch họp, Tệp chia sẻ, lối tắt quản trị thêm, ô Thêm.
class WorkAppsSection extends ConsumerWidget {
  const WorkAppsSection({required this.workspaceId, super.key});

  final String workspaceId;

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
          icon: WebTuiIcons.meetings,
          label: 'Lịch họp',
          colors: webTuiShortcutColors('orange'),
          onTap: () => context.push(
            Uri(
              path: '/meetings',
              queryParameters: {'workspaceId': workspaceId},
            ).toString(),
          ),
        ),
      _AppTile(
        key: const Key('app_shared_files'),
        icon: WebTuiIcons.sharedFiles,
        label: 'Tệp chia sẻ',
        colors: webTuiShortcutColors('green'),
        onTap: () => context.push(
          Uri(
            path: '/files',
            queryParameters: {'workspaceId': workspaceId},
          ).toString(),
        ),
      ),
      for (final shortcut in list?.shortcuts ?? const <AppShortcut>[])
        _AppTile(
          key: Key('app_shortcut_${shortcut.id}'),
          icon: webTuiShortcutIcon(shortcut.icon),
          label: shortcut.title,
          colors: webTuiShortcutColors(shortcut.color),
          onTap: () => openAppShortcut(context, ref, shortcut),
        ),
      if (canManage) _AddTile(onTap: () => _add(context, ref)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Ứng dụng',
                  style: WebTuiTypography.titleLarge.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
              if (canManage)
                InkWell(
                  key: const Key('apps_manage'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.push(
                    Uri(
                      path: '/shortcuts',
                      queryParameters: {'workspaceId': workspaceId},
                    ).toString(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      'Quản lý',
                      style: WebTuiTypography.bodyMedium.copyWith(
                        color: WebTuiColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            final width = math.max(0.0, (constraints.maxWidth - gap * 2) / 3);
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items) SizedBox(width: width, child: item),
              ],
            );
          },
        ),
        if (workHub && shortcuts.hasError)
          WorkErrorBox(
            message: workHubErrorText(shortcuts.error!),
            onRetry: () => ref.invalidate(appShortcutsProvider),
          )
        else if (workHub && list != null && list.shortcuts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Chưa có lối tắt',
              key: const Key('shortcuts_empty'),
              textAlign: TextAlign.center,
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
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

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final ({Color background, Color foreground}) colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WorkCard(
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      child: SizedBox(
        height: 84,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            WorkIconBox(
              icon: icon,
              size: 48,
              radius: 15,
              iconSize: 26,
              background: colors.background,
              foreground: colors.foreground,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WebTuiTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: WebTuiColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WorkCard(
      key: const Key('app_add'),
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      child: SizedBox(
        height: 84,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              painter: const _DashedBoxPainter(),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  WebTuiIcons.add,
                  size: 26,
                  color: WebTuiColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Thêm',
              style: WebTuiTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: WebTuiColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Khung bo góc nét đứt của ô "Thêm".
class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF8A96A8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(15)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), paint);
        distance += 8;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
