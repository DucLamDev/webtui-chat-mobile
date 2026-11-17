import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_seamless.dart';
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

/// Bảng màu ô ứng dụng (cùng độ đậm, biểu tượng trắng đọc được ở nền sáng
/// lẫn tối: tương phản ≥ 3:1 với cả hai đầu gradient). Khoá trùng khoá màu
/// lối tắt của máy chủ; khoá lạ dùng xanh dương.
const workAppBlue = Color(0xFF2F6FED);
const workAppOrange = Color(0xFFD9591A);
const workAppGreen = Color(0xFF1B8F52);
const workAppViolet = Color(0xFF7C4DDB);
const workAppRed = Color(0xFFD23C5E);
const workAppTeal = Color(0xFF0F8A82);
const workAppGray = Color(0xFF5F6F86);

Color workAppColorForKey(String? key) => switch (key?.trim()) {
  'violet' => workAppViolet,
  'green' => workAppGreen,
  'orange' => workAppOrange,
  'red' => workAppRed,
  'teal' => workAppTeal,
  'gray' => workAppGray,
  _ => workAppBlue,
};

/// Hai đầu gradient nhẹ của ô: sáng hơn một chút ở trên trái, đậm hơn ở dưới
/// phải. Đầu sáng vẫn giữ tương phản ≥ 3:1 với biểu tượng trắng.
(Color, Color) workAppGradient(Color base) {
  final hsl = HSLColor.fromColor(base);
  return (
    hsl.withLightness((hsl.lightness + 0.03).clamp(0.0, 1.0)).toColor(),
    hsl.withLightness((hsl.lightness - 0.07).clamp(0.0, 1.0)).toColor(),
  );
}

/// Màu một ô ứng dụng theo nền: (đầu gradient, cuối gradient, biểu tượng).
/// - Tối: gradient đậm của màu riêng, biểu tượng trắng.
/// - Sáng: nền pastel rất nhạt của màu riêng; biểu tượng là màu riêng tươi hơn,
///   nâng độ sáng tới mức nhạt nhất mà vẫn giữ tương phản ≥ 3:1 với nền.
({Color top, Color bottom, Color icon}) workAppTileColors(
  Color base,
  Brightness brightness,
) {
  if (brightness == Brightness.dark) {
    final (top, bottom) = workAppGradient(base);
    return (top: top, bottom: bottom, icon: Colors.white);
  }
  final top = Color.alphaBlend(base.withValues(alpha: 0.07), Colors.white);
  final bottom = Color.alphaBlend(base.withValues(alpha: 0.12), Colors.white);
  final hsl = HSLColor.fromColor(base);
  final vivid = hsl.withSaturation((hsl.saturation + 0.08).clamp(0.0, 1.0));
  var icon = base;
  for (var step = 0; step <= 30; step++) {
    final candidate = vivid
        .withLightness((hsl.lightness + step * 0.005).clamp(0.0, 1.0))
        .toColor();
    if (_contrastRatio(candidate, bottom) < 3.05) break;
    icon = candidate;
  }
  return (top: top, bottom: bottom, icon: icon);
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Biểu tượng Material của lối tắt; khoá lạ là liên kết.
IconData workShortcutIcon(String? key) => switch (key?.trim()) {
  'globe' => Icons.public_rounded,
  'server' => Icons.dns_rounded,
  'cloud' => Icons.cloud_rounded,
  'code' => Icons.code_rounded,
  'terminal' => Icons.terminal_rounded,
  'database' => Icons.storage_rounded,
  'calendar' => Icons.calendar_month_rounded,
  'folder' => Icons.folder_rounded,
  'file-text' => Icons.description_rounded,
  'chart' => Icons.bar_chart_rounded,
  'shield' => Icons.shield_rounded,
  'shopping-bag' => Icons.shopping_bag_rounded,
  'ticket' => Icons.confirmation_number_rounded,
  'headphones' => Icons.headset_mic_rounded,
  'mail' => Icons.mail_rounded,
  'book-open' => Icons.menu_book_rounded,
  'briefcase' => Icons.work_rounded,
  'wallet' => Icons.account_balance_wallet_rounded,
  'settings' => Icons.settings_rounded,
  _ => Icons.link_rounded,
};

/// Một ô thêm vào lưới Ứng dụng từ ngoài (vd tiện ích My Note), đứng sau Lịch
/// họp và Tệp chia sẻ, trước lối tắt.
final class WorkAppItem {
  const WorkAppItem({
    required this.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
}

/// Nhóm "Ứng dụng": lưới 4 cột ô vuông bo góc màu kiểu mini app + nhãn: Lịch
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
          icon: Icons.calendar_month_rounded,
          label: tr('Lịch họp', 'Meetings'),
          color: workAppOrange,
          onTap: () => context.push(
            Uri(
              path: '/meetings',
              queryParameters: {'workspaceId': workspaceId},
            ).toString(),
          ),
        ),
      _AppTile(
        key: const Key('app_shared_files'),
        icon: Icons.folder_rounded,
        label: tr('Tệp chia sẻ', 'Shared files'),
        color: workAppGreen,
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
          icon: app.icon,
          label: app.label,
          color: app.color,
          onTap: app.onTap,
        ),
      for (final shortcut in list?.shortcuts ?? const <AppShortcut>[])
        _AppTile(
          key: Key('app_shortcut_${shortcut.id}'),
          icon: workShortcutIcon(shortcut.icon),
          label: shortcut.title,
          color: workAppColorForKey(shortcut.color),
          onTap: () => openAppShortcut(context, ref, shortcut),
        ),
      if (canManage)
        _AppTile(
          key: const Key('app_add'),
          icon: Icons.add_rounded,
          label: tr('Thêm', 'Add'),
          color: WebTuiColors.textMuted,
          dashed: true,
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

/// Cạnh ô ứng dụng, bo góc và cỡ biểu tượng.
const workAppTileSize = 52.0;
const workAppTileRadius = 14.0;
const workAppIconSize = 26.0;

/// Một ô ứng dụng: ô vuông 52 bo 14, biểu tượng 26; nhãn 12 (1–2 dòng, căn
/// giữa) bên dưới. Màu theo [workAppTileColors]: nền tối là gradient đậm +
/// biểu tượng trắng + bóng nhẹ; nền sáng là pastel phẳng + biểu tượng màu. Ô
/// [dashed] (Thêm) viền đứt: tối nền surface + biểu tượng xám, sáng nền xanh
/// rất nhạt + biểu tượng xanh.
class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.dashed = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final dark = WebTuiColors.brightness == Brightness.dark;
    final Widget box;
    if (dashed) {
      // Sáng: ô Thêm nhạt màu xanh chủ đạo, không xám; tối giữ nền surface.
      box = CustomPaint(
        key: const Key('app_tile_dashed'),
        painter: _DashedRRectPainter(
          color: dark
              ? WebTuiColors.textMuted.withValues(alpha: 0.55)
              : WebTuiColors.primary.withValues(alpha: 0.40),
          fill: dark
              ? WebTuiColors.surface
              : Color.alphaBlend(
                  WebTuiColors.primary.withValues(alpha: 0.05),
                  Colors.white,
                ),
          radius: workAppTileRadius,
        ),
        child: SizedBox(
          width: workAppTileSize,
          height: workAppTileSize,
          child: Icon(
            icon,
            size: workAppIconSize,
            color: dark ? color : WebTuiColors.primary,
          ),
        ),
      );
    } else {
      final colors = workAppTileColors(color, WebTuiColors.brightness);
      final top = colors.top;
      final bottom = colors.bottom;
      box = DecoratedBox(
        key: const Key('app_tile_color'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(workAppTileRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [top, bottom],
          ),
          // Sáng: ô pastel phẳng, không bóng.
          boxShadow: dark
              ? [
                  BoxShadow(
                    color: bottom.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: SizedBox(
          width: workAppTileSize,
          height: workAppTileSize,
          child: Icon(icon, size: workAppIconSize, color: colors.icon),
        ),
      );
    }
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              box,
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: WebTuiTypography.bodySmall.copyWith(
                  fontSize: 12,
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

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.fill,
    required this.radius,
  });

  final Color color;
  final Color fill;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);
    final path = Path()..addRRect(rrect.deflate(0.75));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), paint);
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.fill != fill || old.radius != radius;
}
