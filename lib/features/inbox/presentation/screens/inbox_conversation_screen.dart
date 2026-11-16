import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/inbox.dart';
import '../controllers/inbox_access_provider.dart';
import '../controllers/inbox_conversation_controller.dart';
import '../widgets/inbox_message_bubble.dart';
import 'inbox_list_screen.dart';

/// Màn hội thoại khách: tin, trả lời / ghi chú, nhận, trạng thái, tag.
class InboxConversationScreen extends ConsumerWidget {
  const InboxConversationScreen({
    required this.conversationId,
    this.workspaceId,
    super.key,
  });

  final String conversationId;
  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(inboxAccessProvider(workspaceId));
    final gate = inboxAccessGate(access);
    final requested = workspaceId?.trim() ?? '';
    final active = ref.watch(
      workspaceControllerProvider.select((state) => state.activeWorkspace?.id),
    );
    final id = gate != null
        ? ''
        : (requested.isNotEmpty ? requested : active ?? '');
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        title: Text(tr('Hội thoại khách', 'Customer conversation')),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child:
            gate ??
            (id.isEmpty || conversationId.trim().isEmpty
                ? WebTuiEmptyState(
                    title: tr(
                      'Không mở được hội thoại',
                      'Couldn\'t open the conversation',
                    ),
                    message: tr(
                      'Thiếu thông tin hội thoại.',
                      'Conversation details are missing.',
                    ),
                    icon: Icons.forum_outlined,
                  )
                : _ConversationBody(
                    args: (workspaceId: id, conversationId: conversationId),
                    canAct: access.canReply,
                  )),
      ),
    );
  }
}

class _ConversationBody extends ConsumerStatefulWidget {
  const _ConversationBody({required this.args, required this.canAct});

  final InboxConversationArgs args;

  /// Có `inbox.reply`; không thì chỉ xem.
  final bool canAct;

  @override
  ConsumerState<_ConversationBody> createState() => _ConversationBodyState();
}

class _ConversationBodyState extends ConsumerState<_ConversationBody> {
  final _replyText = TextEditingController();
  final _noteText = TextEditingController();

  @override
  void dispose() {
    _replyText.dispose();
    _noteText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = inboxConversationControllerProvider(widget.args);
    ref.listen<InboxConversationState>(provider, (previous, next) {
      final error = next.actionError;
      if (error != null && error != previous?.actionError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
        ref.read(provider.notifier).clearActionError();
      }
    });
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    if (state.forbidden) return const InboxNoAccessState();
    if (state.notFound) {
      return WebTuiEmptyState(
        key: Key('inbox_not_found'),
        title: tr('Không tìm thấy hội thoại', 'Conversation not found'),
        message: tr(
          'Hội thoại đã bị xoá hoặc không thuộc workspace này.',
          'The conversation was deleted or doesn\'t belong to this workspace.',
        ),
        icon: Icons.forum_outlined,
      );
    }
    final conversation = state.conversation;
    if (conversation == null) {
      if (state.errorMessage != null) {
        return WebTuiErrorState(
          title: tr(
            'Không tải được hội thoại',
            'Couldn\'t load the conversation',
          ),
          message: state.errorMessage!,
          onRetry: controller.load,
        );
      }
      return WebTuiLoadingState(
        message: tr('Đang tải hội thoại...', 'Loading conversation...'),
      );
    }
    return Column(
      children: [
        _Header(
          state: state,
          conversation: conversation,
          controller: controller,
          canAct: widget.canAct,
        ),
        Expanded(child: _messages(state, controller)),
        if (widget.canAct)
          _Composer(
            state: state,
            controller: controller,
            replyText: _replyText,
            noteText: _noteText,
          )
        else
          const _ViewOnlyNotice(),
      ],
    );
  }

  Widget _messages(
    InboxConversationState state,
    InboxConversationController controller,
  ) {
    if (state.messages.isEmpty) {
      return WebTuiEmptyState(
        key: Key('inbox_messages_empty'),
        title: tr('Chưa có tin nhắn', 'No messages yet'),
        message: tr(
          'Tin của khách sẽ hiện ở đây.',
          'Customer messages will appear here.',
        ),
        icon: Icons.chat_bubble_outline_rounded,
      );
    }
    final messages = state.messages.reversed.toList(growable: false);
    return ListView.builder(
      key: const Key('inbox_messages'),
      reverse: true,
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      itemCount: messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return Center(
            child: TextButton(
              key: const Key('inbox_load_older'),
              onPressed: state.isLoadingMore ? null : controller.loadOlder,
              child: Text(
                state.isLoadingMore
                    ? tr('Đang tải...', 'Loading...')
                    : tr('Tải tin cũ hơn', 'Load older messages'),
              ),
            ),
          );
        }
        final message = messages[index];
        return InboxMessageBubble(
          message: message,
          onRetry:
              widget.canAct &&
                  message.isLocal &&
                  message.delivery == InboxDelivery.failed
              ? () => controller.retry(message.clientMessageId)
              : null,
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.conversation,
    required this.controller,
    required this.canAct,
  });

  final InboxConversationState state;
  final InboxConversation conversation;
  final InboxConversationController controller;
  final bool canAct;

  @override
  Widget build(BuildContext context) {
    final mine = state.assignedToMe;
    return Material(
      color: WebTuiColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conversation.title,
              key: const Key('inbox_title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              [
                conversation.source.kindLabel,
                if (conversation.contact.email.isNotEmpty)
                  conversation.contact.email,
                if (conversation.contact.phone.isNotEmpty)
                  conversation.contact.phone,
              ].join(' · '),
              style: TextStyle(color: WebTuiColors.textSecondary),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PopupMenuButton<InboxStatus>(
                  key: const Key('inbox_status_menu'),
                  tooltip: tr('Đổi trạng thái', 'Change status'),
                  enabled: canAct && !state.isUpdating,
                  onSelected: controller.setStatus,
                  itemBuilder: (_) => [
                    for (final status in const [
                      InboxStatus.open,
                      InboxStatus.pending,
                      InboxStatus.closed,
                    ])
                      PopupMenuItem(
                        key: Key('inbox_status_${status.apiValue}'),
                        value: status,
                        child: Text(status.label),
                      ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.flag_outlined, size: 16),
                    label: Text(conversation.status.label),
                  ),
                ),
                if (!conversation.isAssigned)
                  OutlinedButton(
                    key: const Key('inbox_claim'),
                    onPressed: !canAct || state.isUpdating
                        ? null
                        : controller.claim,
                    child: Text(tr('Nhận xử lý', 'Assign to me')),
                  )
                else if (mine)
                  OutlinedButton(
                    key: const Key('inbox_release'),
                    onPressed: !canAct || state.isUpdating
                        ? null
                        : controller.release,
                    child: Text(tr('Bỏ nhận', 'Unassign me')),
                  )
                else
                  Chip(
                    key: const Key('inbox_assignee'),
                    avatar: const Icon(Icons.person_outline, size: 16),
                    label: Text(
                      conversation.assigneeName.isEmpty
                          ? tr('Đã có người nhận', 'Already assigned')
                          : tr(
                              'Do ${conversation.assigneeName} xử lý',
                              'Handled by ${conversation.assigneeName}',
                            ),
                    ),
                  ),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final tag in conversation.tags)
                    Chip(
                      key: Key('inbox_tag_${tag.id}'),
                      label: Text('#${tag.name}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  TextButton.icon(
                    key: const Key('inbox_tags_edit'),
                    onPressed: !canAct || state.isUpdating
                        ? null
                        : () => _editTags(context),
                    icon: const Icon(Icons.sell_outlined, size: 18),
                    label: Text(tr('Gắn tag', 'Add tags')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTags(BuildContext context) async {
    final tags = await controller.loadTags();
    if (!context.mounted) return;
    final selected = {for (final tag in conversation.tags) tag.id};
    final result = await showWebTuiSheet<Set<String>>(
      context: context,
      builder: (context) => _TagSheet(tags: tags, selected: selected),
    );
    if (result != null) await controller.setTags(result.toList());
  }
}

class _TagSheet extends StatefulWidget {
  const _TagSheet({required this.tags, required this.selected});

  final List<InboxTag> tags;
  final Set<String> selected;

  @override
  State<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<_TagSheet> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    if (widget.tags.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebTuiSheetHeader(title: tr('Gắn tag', 'Add tags')),
          Padding(
            padding: EdgeInsets.fromLTRB(
              WebTuiSpacing.xl,
              0,
              WebTuiSpacing.xl,
              WebTuiSpacing.xl,
            ),
            child: Text(
              tr(
                'Workspace chưa có tag nào.',
                'This workspace has no tags yet.',
              ),
            ),
          ),
        ],
      );
    }
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WebTuiSheetHeader(title: tr('Gắn tag', 'Add tags')),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final tag in widget.tags)
                  CheckboxListTile(
                    key: Key('inbox_tag_option_${tag.id}'),
                    value: _selected.contains(tag.id),
                    title: Text('#${tag.name}'),
                    onChanged: (on) => setState(() {
                      on == true
                          ? _selected.add(tag.id)
                          : _selected.remove(tag.id);
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(WebTuiSpacing.md),
            child: FilledButton(
              key: const Key('inbox_tags_save'),
              onPressed: () => Navigator.of(context).pop(_selected),
              child: Text(tr('Lưu tag', 'Save tags')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewOnlyNotice extends StatelessWidget {
  const _ViewOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTuiColors.surface,
      child: Padding(
        padding: EdgeInsets.all(WebTuiSpacing.md),
        child: Center(
          child: Text(
            tr(
              'Bạn chỉ có quyền xem hộp thư này.',
              'You can only view this inbox.',
            ),
            key: Key('inbox_view_only'),
            style: TextStyle(color: WebTuiColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.state,
    required this.controller,
    required this.replyText,
    required this.noteText,
  });

  final InboxConversationState state;
  final InboxConversationController controller;
  final TextEditingController replyText;
  final TextEditingController noteText;

  @override
  Widget build(BuildContext context) {
    final noteMode = state.mode == InboxComposeMode.note;
    final blocked = !noteMode && !state.canReply;
    final reason = state.conversation?.replyBlockedReason.trim() ?? '';
    final text = noteMode ? noteText : replyText;
    return Material(
      color: noteMode ? inboxNoteColor : WebTuiColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<InboxComposeMode>(
              key: const Key('inbox_compose_mode'),
              segments: [
                ButtonSegment(
                  value: InboxComposeMode.reply,
                  label: Text(tr('Trả lời', 'Reply')),
                ),
                ButtonSegment(
                  value: InboxComposeMode.note,
                  label: Text(tr('Ghi chú', 'Note')),
                ),
              ],
              selected: {state.mode},
              onSelectionChanged: (value) => controller.setMode(value.first),
            ),
            if (blocked)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                child: Text(
                  reason.isEmpty
                      ? tr(
                          'Chưa trả lời được hội thoại này.',
                          'Couldn\'t reply to this conversation.',
                        )
                      : reason,
                  key: const Key('inbox_reply_blocked'),
                  style: TextStyle(color: WebTuiColors.danger),
                ),
              ),
            if (noteMode)
              Padding(
                padding: EdgeInsets.only(top: WebTuiSpacing.sm),
                child: Text(
                  inboxNoteLabel,
                  style: TextStyle(fontSize: 12, color: Color(0xFF7A5B00)),
                ),
              ),
            const SizedBox(height: WebTuiSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: Key(
                      noteMode ? 'inbox_note_input' : 'inbox_reply_input',
                    ),
                    controller: text,
                    enabled: !blocked,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 5000,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: noteMode
                          ? tr(
                              'Viết ghi chú nội bộ...',
                              'Write an internal note...',
                            )
                          : blocked
                          ? tr('Không thể trả lời', 'Can\'t reply')
                          : tr('Trả lời khách...', 'Reply to the customer...'),
                    ),
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                IconButton.filled(
                  key: const Key('inbox_send'),
                  tooltip: noteMode
                      ? tr('Lưu ghi chú', 'Save note')
                      : tr('Gửi', 'Send'),
                  onPressed: blocked || state.isSendingNote
                      ? null
                      : () => _send(noteMode, text),
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(bool noteMode, TextEditingController text) async {
    final value = text.text;
    if (value.trim().isEmpty) return;
    if (noteMode) {
      if (await controller.addNote(value)) text.clear();
      return;
    }
    // Tin trả lời hiện ngay trong danh sách (kèm trạng thái / Gửi lại), nên
    // xoá ô nhập luôn.
    text.clear();
    await controller.sendReply(value);
  }
}
