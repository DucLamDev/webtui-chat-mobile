import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

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
          label: tr('Lịch họp', 'Meetings'),
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
        label: tr('Tệp chia sẻ', 'Shared files'),
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
                  tr('Ứng dụng', 'Apps'),
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
                      tr('Quản lý', 'Manage'),
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
              tr('Chưa có lối tắt', 'No shortcuts yet'),
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

/// Kích thước chung của ô biểu tượng trong khu "Ứng dụng": ô màu và ô "Thêm"
/// viền đứt cùng cạnh, cùng bo góc, biểu tượng cùng cỡ.
abstract final class WorkAppTileMetrics {
  static const double iconBox = 52;
  static const double iconRadius = 16;
  static const double iconSize = 26;

  /// Viền ô (mảnh với ô màu, nét đứt với ô "Thêm"): vẽ phía trong cạnh ô nên
  /// kích thước ngoài của mọi ô luôn đúng [iconBox].
  static const double borderWidth = 1.4;
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
    return _AppTileFrame(
      onTap: onTap,
      label: label,
      icon: DecoratedBox(
        key: const Key('app_tile_icon_box'),
        // Viền mảnh cùng màu biểu tượng: nền nhạt (cam, xanh) trên thẻ trắng
        // vẫn thấy rõ mép ô, nên ô màu trông bằng ô "Thêm" viền đứt.
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(WorkAppTileMetrics.iconRadius),
          border: Border.all(
            color: colors.foreground.withValues(alpha: 0.16),
            width: WorkAppTileMetrics.borderWidth,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            size: WorkAppTileMetrics.iconSize,
            color: colors.foreground,
          ),
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
    return _AppTileFrame(
      key: const Key('app_add'),
      onTap: onTap,
      label: tr('Thêm', 'Add'),
      icon: const CustomPaint(
        key: Key('app_tile_icon_box'),
        painter: _DashedBoxPainter(),
        child: Center(
          child: Icon(
            WebTuiIcons.add,
            size: WorkAppTileMetrics.iconSize,
            color: WebTuiColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Khung chung của một ô ứng dụng: thẻ trắng, ô biểu tượng cố định
/// [WorkAppTileMetrics.iconBox] rồi một dòng chữ. Mọi ô dùng cùng khung nên
/// ô biểu tượng và dòng chữ thẳng hàng giữa các ô.
class _AppTileFrame extends StatelessWidget {
  const _AppTileFrame({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WorkCard(
      onTap: onTap,
      radius: 20,
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(dimension: WorkAppTileMetrics.iconBox, child: icon),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: WebTuiColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Khung bo góc nét đứt của ô "Thêm".
class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = WorkAppTileMetrics.borderWidth;
    final paint = Paint()
      ..color = WebTuiColors.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    // Lùi nửa nét vào trong: nét đứt nằm gọn trong ô, cạnh ngoài bằng ô màu.
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(WorkAppTileMetrics.iconRadius - stroke / 2),
        ),
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
