import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../l10n/app_strings.dart';

/// Chỗ đăng ký sẵn cho `/ide/ai/:key`, `/ide/jobs/:id` (GĐ sau).
class IdeComingSoonScreen extends StatelessWidget {
  const IdeComingSoonScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), surfaceTintColor: Colors.transparent),
      body: WebTuiEmptyState(
        title: tr('Sắp có', 'Coming soon'),
        message: tr(
          'Chức năng này đang được hoàn thiện.',
          'This feature is being finished.',
        ),
        icon: Icons.hourglass_empty_rounded,
      ),
    );
  }
}
