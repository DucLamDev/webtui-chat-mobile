import 'package:flutter/material.dart';

import '../../../../../l10n/app_strings.dart';
import '../ide_coming_soon_screen.dart';

/// Khung GĐ4 (Phụ lục C): màn tạm, agent thay bằng màn thật.
class IdeTalkScreen extends StatelessWidget {
  const IdeTalkScreen({required this.talkId, super.key});

  final String talkId;

  @override
  Widget build(BuildContext context) =>
      IdeComingSoonScreen(title: tr('Chat thường', 'Chat'));
}
