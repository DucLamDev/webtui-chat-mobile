import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import 'business_dashboard_screen.dart';

/// Trang `/business`: chỉ mở được khi discovery bật automation; không thì
/// báo "không hỗ trợ" (không gọi máy chủ).
class BusinessRouteScreen extends ConsumerWidget {
  const BusinessRouteScreen({this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled =
        ref.watch(activeServerDiscoveryProvider)?.automationEnabled ?? false;
    final requested = workspaceId?.trim() ?? '';
    final active = ref.watch(
      workspaceControllerProvider.select((state) => state.activeWorkspace?.id),
    );
    final id = requested.isNotEmpty ? requested : active?.trim() ?? '';
    final Widget body;
    if (!enabled) {
      body = WebTuiEmptyState(
        key: Key('business_unavailable'),
        title: tr('Chưa có module nghiệp vụ', 'No business module'),
        message: tr(
          'Máy chủ này chưa bật module nghiệp vụ.',
          'This server hasn\'t enabled the business module.',
        ),
        icon: Icons.lock_outline_rounded,
      );
    } else if (id.isEmpty) {
      body = WebTuiEmptyState(
        title: tr('Chưa chọn workspace', 'No workspace selected'),
        message: tr(
          'Chọn workspace trước khi xem nghiệp vụ.',
          'Select a workspace before viewing business.',
        ),
        icon: Icons.dashboard_customize_outlined,
      );
    } else {
      body = BusinessDashboardScreen(workspaceId: id);
    }
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        title: Text(tr('Nghiệp vụ', 'Business')),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(top: false, child: body),
    );
  }
}
