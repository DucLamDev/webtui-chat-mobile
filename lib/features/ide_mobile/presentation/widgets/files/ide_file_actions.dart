import 'package:flutter/material.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../l10n/app_strings.dart';
import '../../screens/ide_ai_chat_screen.dart';

/// "Hỏi AI về tệp này": chọn Claude / Codex rồi mở phiên mới trong dự án
/// [root] với ô soạn điền sẵn `@<đường dẫn> `.
Future<void> ideAskAiAboutPath(
  BuildContext context, {
  required String root,
  required String path,
}) async {
  final kind = await showWebTuiSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebTuiSheetHeader(
            title: tr('Hỏi AI về tệp này', 'Ask AI about this file'),
          ),
          WebTuiSheetActionTile(
            key: const Key('ide_ask_claude'),
            icon: Icons.auto_awesome_rounded,
            title: 'Claude',
            onTap: () => Navigator.of(ctx).pop('claude'),
          ),
          WebTuiSheetActionTile(
            key: const Key('ide_ask_codex'),
            icon: Icons.auto_awesome_outlined,
            title: 'Codex',
            onTap: () => Navigator.of(ctx).pop('codex'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => IdeAiChatScreen.newSession(
        kind: kind,
        root: root,
        initialText: '@$path ',
      ),
    ),
  );
}
