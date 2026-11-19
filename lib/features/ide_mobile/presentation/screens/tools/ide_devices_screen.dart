import 'package:flutter/material.dart';

import '../../../../../l10n/app_strings.dart';
import '../ide_coming_soon_screen.dart';

/// Khung GĐ4 (Phụ lục C): màn tạm, agent thay bằng màn thật.
class IdeDevicesScreen extends StatelessWidget {
  const IdeDevicesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      IdeComingSoonScreen(title: tr('Điện thoại đã gắn', 'Linked phones'));
}
