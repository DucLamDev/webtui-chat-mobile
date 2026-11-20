import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_download_service.dart' show ideIsImageName;
import '../../../domain/ide_talk_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/files/ide_file_card.dart';
import '../../widgets/markdown/ide_markdown.dart';
import '../more/ide_more_common.dart';
import 'ide_talk_providers.dart';

/// Một tin trong cuộc chat: người dùng (bên phải) hoặc AI (Markdown).
class IdeTalkMessageTile extends StatelessWidget {
  const IdeTalkMessageTile({
    required this.talkId,
    required this.message,
    this.onFollowup,
    this.canDownload = true,
    super.key,
  });

  final String talkId;
  final IdeTalkMessage message;
  final ValueChanged<String>? onFollowup;

  /// Có `talk.file` trong `ready.ops`.
  final bool canDownload;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final user = m.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * (user ? 0.86 : 0.96),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: user ? WebTuiColors.messageOutgoing : WebTuiColors.surface,
            border: Border.all(
              color: user
                  ? WebTuiColors.messageOutgoingBorder
                  : WebTuiColors.border,
            ),
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(WebTuiSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (user && m.text.isNotEmpty)
                  SelectableText(
                    m.text,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                    ),
                  )
                else if (!user && m.text.isNotEmpty)
                  IdeMarkdown(text: m.text, streaming: m.pending),
                if (!user && m.text.isEmpty && m.pending)
                  _Hint(
                    m.stage.isNotEmpty
                        ? ideVisibleText(m.stage)
                        : tr('AI đang viết...', 'The AI is writing...'),
                    busy: true,
                  ),
                if (!user &&
                    m.pending &&
                    m.text.isNotEmpty &&
                    m.stage.isNotEmpty)
                  _Hint(ideVisibleText(m.stage), busy: true),
                if (m.error)
                  _Hint(
                    m.note.isNotEmpty
                        ? ideVisibleText(m.note)
                        : tr('AI gặp lỗi khi trả lời.', 'The AI hit an error.'),
                    color: WebTuiColors.danger,
                  )
                else if (m.note.isNotEmpty && !m.pending)
                  _Hint(ideVisibleText(m.note)),
                if (m.plan.isNotEmpty) _Plan(items: m.plan),
                if (m.steps.isNotEmpty) _Steps(steps: m.steps),
                for (final n in [...m.attachments, ...m.images])
                  _TalkFileTile(
                    talkId: talkId,
                    file: IdeTalkFile(name: n),
                    image: ideIsImageName(n),
                    enabled: canDownload,
                  ),
                for (final f in m.files)
                  _TalkFileTile(
                    talkId: talkId,
                    file: f,
                    image: false,
                    enabled: canDownload,
                  ),
                if (m.sources.isNotEmpty) _Sources(sources: m.sources),
                if (!user &&
                    !m.pending &&
                    m.followups.isNotEmpty &&
                    onFollowup != null)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                    child: Wrap(
                      spacing: WebTuiSpacing.sm,
                      children: [
                        for (final q in m.followups)
                          ActionChip(
                            label: Text(
                              ideVisibleText(q),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () => onFollowup!(q),
                          ),
                      ],
                    ),
                  ),
                if (!user && m.model.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                    child: Text(
                      [
                        ideVisibleText(m.model),
                        if (m.effort.isNotEmpty) m.effort,
                      ].join(' · '),
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.color, this.busy = false});

  final String text;
  final Color? color;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
    child: Row(
      children: [
        if (busy)
          const Padding(
            padding: EdgeInsets.only(right: WebTuiSpacing.sm),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Expanded(
          child: Text(
            text,
            style: WebTuiTypography.bodySmall.copyWith(
              color: color ?? WebTuiColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Plan extends StatelessWidget {
  const _Plan({required this.items});

  final List<IdeTalkPlanItem> items;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in items)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                p.status == 'done' || p.status == 'completed'
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: p.status == 'done' || p.status == 'completed'
                    ? WebTuiColors.accentGreen
                    : WebTuiColors.textMuted,
              ),
              const SizedBox(width: WebTuiSpacing.xs),
              Expanded(
                child: Text(
                  ideVisibleText(p.step),
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _Steps extends StatelessWidget {
  const _Steps({required this.steps});

  final List<IdeTalkStep> steps;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      minTileHeight: 44,
      title: Text(
        tr('${steps.length} bước AI đã làm', '${steps.length} steps taken'),
        style: WebTuiTypography.bodySmall.copyWith(
          color: WebTuiColors.textSecondary,
        ),
      ),
      children: [
        for (final s in steps)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
              child: Text(
                '${ideVisibleText(s.tool)}: ${ideVisibleText(s.detail)}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Sources extends StatelessWidget {
  const _Sources({required this.sources});

  final List<IdeTalkSource> sources;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Nguồn', 'Sources'),
          style: WebTuiTypography.labelSmall.copyWith(
            color: WebTuiColors.textSecondary,
          ),
        ),
        for (final s in sources)
          Text(
            ideVisibleText(s.title.isEmpty ? s.url : s.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.primary,
            ),
          ),
      ],
    ),
  );
}

/// Tệp / ảnh trong cuộc: chạm → `talk.file` lấy đường dẫn đã kiểm → thẻ tải
/// (`files.get`). Tên không hợp lệ thì không cho tải.
class _TalkFileTile extends ConsumerStatefulWidget {
  const _TalkFileTile({
    required this.talkId,
    required this.file,
    required this.image,
    required this.enabled,
  });

  final String talkId;
  final IdeTalkFile file;
  final bool image;
  final bool enabled;

  @override
  ConsumerState<_TalkFileTile> createState() => _TalkFileTileState();
}

class _TalkFileTileState extends ConsumerState<_TalkFileTile> {
  ({String path, int size})? _resolved;
  bool _loading = false;
  String? _error;

  Future<void> _resolve() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(ideTalkServiceProvider)
          .file(widget.talkId, widget.file.name);
      if (mounted) setState(() => _resolved = r);
    } on Object catch (e) {
      if (mounted) setState(() => _error = ideMoreErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    final r = _resolved;
    if (r != null) {
      return Padding(
        padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
        child: IdeFileCard(path: r.path, name: f.name, size: r.size),
      );
    }
    final ok = widget.enabled && ideTalkFileNameOk(f.name);
    final label = f.label.isNotEmpty ? f.label : f.name;
    return Padding(
      padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
      child: Material(
        color: WebTuiColors.backgroundMuted,
        borderRadius: BorderRadius.circular(WebTuiRadii.sm),
        child: InkWell(
          key: Key('talk_file_${f.name}'),
          borderRadius: BorderRadius.circular(WebTuiRadii.sm),
          onTap: ok ? _resolve : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WebTuiSpacing.md,
                vertical: WebTuiSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.image
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined,
                    size: 20,
                    color: WebTuiColors.textSecondary,
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ideVisibleText(label),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WebTuiTypography.bodySmall.copyWith(
                            color: WebTuiColors.textPrimary,
                          ),
                        ),
                        if (_error != null)
                          Text(
                            _error!,
                            style: WebTuiTypography.labelSmall.copyWith(
                              color: WebTuiColors.danger,
                            ),
                          )
                        else if (f.size != null)
                          Text(
                            ideFormatSize(f.size!.round()),
                            style: WebTuiTypography.labelSmall.copyWith(
                              color: WebTuiColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (ok)
                    Icon(
                      Icons.download_rounded,
                      size: 20,
                      color: WebTuiColors.primary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
