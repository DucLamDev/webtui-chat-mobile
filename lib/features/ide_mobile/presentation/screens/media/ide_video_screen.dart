import 'package:flutter/material.dart';

import '../../../../../l10n/app_strings.dart';
import '../ide_coming_soon_screen.dart';

/// Khung GĐ4 (Phụ lục C): màn tạm, agent thay bằng màn thật.
class IdeVideoScreen extends StatelessWidget {
  const IdeVideoScreen({required this.project, required this.slug, super.key});

  final String project;
  final String slug;

  @override
  Widget build(BuildContext context) =>
      IdeComingSoonScreen(title: tr('Studio video', 'Video studio'));
}
