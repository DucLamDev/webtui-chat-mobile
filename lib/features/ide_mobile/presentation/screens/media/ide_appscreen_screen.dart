import 'package:flutter/material.dart';

import '../../../../../l10n/app_strings.dart';
import '../ide_coming_soon_screen.dart';

/// Khung GĐ4 (Phụ lục C): màn tạm, agent thay bằng màn thật.
class IdeAppScreenScreen extends StatelessWidget {
  const IdeAppScreenScreen({this.project, super.key});

  final String? project;

  @override
  Widget build(BuildContext context) =>
      IdeComingSoonScreen(title: tr('Màn hình app', 'App screen'));
}
