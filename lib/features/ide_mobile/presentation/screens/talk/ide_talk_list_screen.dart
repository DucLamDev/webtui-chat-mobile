import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_talk_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';
import 'ide_talk_new_sheet.dart';
import 'ide_talk_providers.dart';

/// Danh sách chat thường (`talk.list`), tạo chat mới, mở theo mã.
class IdeTalkListScreen extends ConsumerStatefulWidget {
  const IdeTalkListScreen({super.key});

  @override
  ConsumerState<IdeTalkListScreen> createState() => _IdeTalkListScreenState();
}

class _IdeTalkListScreenState extends ConsumerState<IdeTalkListScreen> {
  int _scope = 0; // 0 tất cả, 1 chat, 2 agent
  int _reloadKey = 0;

  Future<void> _create() async {
    final id = await showIdeTalkNewSheet(
      context,
      models: ideTalkCan(ref, 'talk.models'),
    );
    if (id == null || !mounted) return;
    setState(() => _reloadKey++);
    await context.push('/ide/talk/$id');
    if (mounted) setState(() => _reloadKey++);
  }

  Future<void> _openById() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const _OpenByIdDialog(),
    );
    if (id == null || !mounted) return;
    await context.push('/ide/talk/$id');
  }

  @override
  Widget build(BuildContext context) {
    final canSend = ideTalkHasOp(ref, 'talk.send');
    return IdeMorePage(
      title: tr('Chat thường', 'Chat'),
      actions: [
        IconButton(
          key: const Key('talk_open_id'),
          tooltip: tr('Mở theo mã', 'Open by code'),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: const Icon(Icons.tag_rounded),
          onPressed: _openById,
        ),
      ],
      floating: canSend
          ? FloatingActionButton.extended(
              key: const Key('talk_new'),
              onPressed: _create,
              icon: const Icon(Icons.add_comment_outlined),
              label: Text(tr('Chat mới', 'New chat')),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
            ),
            child: WebTuiSegmentedTabs(
              key: const Key('talk_scope'),
              tabs: [
                tr('Tất cả', 'All'),
                tr('Chat', 'Chats'),
                tr('Agent', 'Agents'),
              ],
              selectedIndex: _scope,
              onChanged: (i) => setState(() => _scope = i),
            ),
          ),
          Expanded(
            child: IdeLoader<List<IdeTalkSummary>>(
              key: ValueKey(_reloadKey),
              load: () => ref.read(ideTalkServiceProvider).list(),
              builder: (context, items, reload) => _TalkList(
                items: [
                  for (final t in items)
                    if (_scope == 0 || (_scope == 2) == t.isAgent) t,
                ],
                reload: reload,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TalkList extends StatelessWidget {
  const _TalkList({required this.items, required this.reload});

  final List<IdeTalkSummary> items;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: reload,
      child: items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                WebTuiEmptyState(
                  title: tr('Chưa có cuộc chat nào', 'No chats yet'),
                  message: tr(
                    'Bấm "Chat mới" để hỏi AI.',
                    'Tap "New chat" to ask the AI.',
                  ),
                  icon: Icons.chat_bubble_outline_rounded,
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                0,
                WebTuiSpacing.lg,
                96,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: WebTuiSpacing.sm),
              itemBuilder: (context, i) => _TalkRow(item: items[i]),
            ),
    );
  }
}

class _TalkRow extends StatelessWidget {
  const _TalkRow({required this.item});

  final IdeTalkSummary item;

  @override
  Widget build(BuildContext context) {
    final title = item.title.trim().isEmpty
        ? tr('Cuộc chat mới', 'New chat')
        : ideVisibleText(item.title);
    final time = item.updated == null ? '' : ideFormatDateTime(item.updated!);
    return IdeCard(
      key: Key('talk_row_${item.id}'),
      onTap: () => context.push('/ide/talk/${item.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (item.unread)
                Padding(
                  padding: const EdgeInsets.only(right: WebTuiSpacing.sm),
                  child: Icon(Icons.circle, size: 10, color: IdeWb.accentInk),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: IdeType.bodyMedium.copyWith(
                    color: IdeWb.textStrong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          Wrap(
            spacing: WebTuiSpacing.xs,
            runSpacing: WebTuiSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.isAgent) IdeTag('Agent', color: IdeWb.accentInk),
              if (item.busy)
                IdeTag(tr('Đang trả lời', 'Replying'), color: IdeWb.warn),
              if (item.shared)
                IdeTag(tr('Đã chia sẻ', 'Shared'), color: IdeWb.ok),
              if (item.archived) IdeTag(tr('Lưu trữ', 'Archived')),
              if (time.isNotEmpty)
                Text(
                  time,
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: IdeWb.text,
                  ),
                ),
              if (item.model.isNotEmpty)
                Text(
                  ideVisibleText(item.model),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: IdeWb.text2,
                  ),
                ),
            ],
          ),
          if (item.isAgent && item.agent?.lastRun?.summary.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
              child: Text(
                ideVisibleText(item.agent!.lastRun!.summary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: IdeType.bodySmall.copyWith(color: IdeWb.text),
              ),
            ),
        ],
      ),
    );
  }
}

class _OpenByIdDialog extends StatefulWidget {
  const _OpenByIdDialog();

  @override
  State<_OpenByIdDialog> createState() => _OpenByIdDialogState();
}

class _OpenByIdDialogState extends State<_OpenByIdDialog> {
  final _c = TextEditingController();
  bool _bad = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    final id = _c.text.trim().toLowerCase();
    if (!ideTalkIdOk(id)) {
      setState(() => _bad = true);
      return;
    }
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Mở cuộc chat theo mã', 'Open a chat by code')),
      content: TextField(
        key: const Key('talk_id_field'),
        controller: _c,
        autofocus: true,
        autocorrect: false,
        maxLength: 32,
        onSubmitted: (_) => _go(),
        decoration: InputDecoration(
          hintText: tr('32 ký tự 0-9, a-f', '32 characters 0-9, a-f'),
          errorText: _bad ? tr('Mã không đúng.', 'Invalid code.') : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Huỷ', 'Cancel')),
        ),
        FilledButton(onPressed: _go, child: Text(tr('Mở', 'Open'))),
      ],
    );
  }
}
