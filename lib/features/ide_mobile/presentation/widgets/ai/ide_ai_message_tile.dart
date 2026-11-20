import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../files/ide_file_card.dart';
import '../markdown/ide_markdown.dart';
import 'ide_ai_json.dart';

/// Một tin trong cuộc trò chuyện: người dùng (bong bóng bên phải), AI
/// (Markdown đầy đủ bề ngang), hệ thống (dòng nhỏ ở giữa). Nhấn giữ tin người
/// dùng → Chép / Quay lui; dòng hệ thống có `undo.redo` → Làm lại.
class IdeAiMessageTile extends StatelessWidget {
  const IdeAiMessageTile({
    required this.message,
    this.streaming = false,
    this.canControl = true,
    this.highlighted = false,
    this.onFormSubmit,
    this.onRewind,
    this.onRedo,
    super.key,
  });

  final Map<String, Object?> message;
  final bool streaming;
  final bool canControl;
  final bool highlighted;
  final ValueChanged<String>? onFormSubmit;
  final ValueChanged<String>? onRewind;
  final ValueChanged<String>? onRedo;

  @override
  Widget build(BuildContext context) {
    final role = aiStr(message['role']);
    final text = aiStr(message['text']);
    final id = aiStr(message['id']);
    final attachments = aiList(message['attachments']);
    final Widget body = switch (role) {
      'user' => _userBubble(context, id, text, attachments),
      'system' => _system(context, id, text),
      _ => _assistant(text),
    };
    if (!highlighted) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.primarySoft,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: body,
    );
  }

  Widget _userBubble(
    BuildContext context,
    String id,
    String text,
    List<Map<String, Object?>> attachments,
  ) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        key: const Key('ide_ai_user_bubble'),
        onLongPress: () => _userMenu(context, id, text),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.86,
          ),
          margin: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          decoration: BoxDecoration(
            color: WebTuiColors.messageOutgoing,
            border: Border.all(color: WebTuiColors.messageOutgoingBorder),
            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in attachments)
                if (aiStr(a['path']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
                    child: IdeFileCard(
                      path: aiStr(a['path']),
                      name: aiStr(a['name']).isEmpty ? null : aiStr(a['name']),
                    ),
                  ),
              if (text.isNotEmpty)
                Text(
                  text,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assistant(String text) {
    final paths = ideFilePathsIn(text).take(6).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeMarkdown(
            text: text,
            streaming: streaming,
            onFormSubmit: canControl ? onFormSubmit : null,
          ),
          for (final p in paths)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: IdeFileCard(path: p),
            ),
        ],
      ),
    );
  }

  Widget _system(BuildContext context, String id, String text) {
    final undo = aiMap(message['undo']);
    final canRedo = canControl && undo['redo'] != null && undo['redo'] != false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textMuted,
            ),
          ),
          if (canRedo && onRedo != null)
            TextButton(
              key: const Key('ide_ai_redo'),
              onPressed: () => onRedo!(id),
              child: Text(tr('Làm lại', 'Redo')),
            ),
        ],
      ),
    );
  }

  Future<void> _userMenu(BuildContext context, String id, String text) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: WebTuiColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              minTileHeight: 52,
              leading: const Icon(Icons.copy_rounded),
              title: Text(tr('Chép nội dung', 'Copy text')),
              onTap: () => Navigator.of(sheet).pop('copy'),
            ),
            if (canControl && onRewind != null)
              ListTile(
                key: const Key('ide_ai_rewind_tile'),
                minTileHeight: 52,
                leading: const Icon(Icons.history_rounded),
                title: Text(
                  tr('Quay lui về trước tin này', 'Rewind to before this'),
                ),
                onTap: () => Navigator.of(sheet).pop('rewind'),
              ),
          ],
        ),
      ),
    );
    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
    } else if (choice == 'rewind') {
      onRewind?.call(id);
    }
  }
}
