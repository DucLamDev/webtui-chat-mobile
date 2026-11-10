import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        title: const Text('Hội thoại khách'),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child:
            gate ??
            (id.isEmpty || conversationId.trim().isEmpty
                ? const WebTuiEmptyState(
                    title: 'Không mở được hội thoại',
                    message: 'Thiếu thông tin hội thoại.',
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
      return const WebTuiEmptyState(
        key: Key('inbox_not_found'),
        title: 'Không tìm thấy hội thoại',
        message: 'Hội thoại đã bị xoá hoặc không thuộc workspace này.',
        icon: Icons.forum_outlined,
      );
    }
    final conversation = state.conversation;
    if (conversation == null) {
      if (state.errorMessage != null) {
        return WebTuiErrorState(
          title: 'Không tải được hội thoại',
          message: state.errorMessage!,
          onRetry: controller.load,
        );
      }
      return const WebTuiLoadingState(message: 'Đang tải hội thoại...');
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
      return const WebTuiEmptyState(
        key: Key('inbox_messages_empty'),
        title: 'Chưa có tin nhắn',
        message: 'Tin của khách sẽ hiện ở đây.',
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
                state.isLoadingMore ? 'Đang tải...' : 'Tải tin cũ hơn',
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
              style: const TextStyle(color: WebTuiColors.textSecondary),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PopupMenuButton<InboxStatus>(
                  key: const Key('inbox_status_menu'),
                  tooltip: 'Đổi trạng thái',
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
                    child: const Text('Nhận xử lý'),
                  )
                else if (mine)
                  OutlinedButton(
                    key: const Key('inbox_release'),
                    onPressed: !canAct || state.isUpdating
                        ? null
                        : controller.release,
                    child: const Text('Bỏ nhận'),
                  )
                else
                  Chip(
                    key: const Key('inbox_assignee'),
                    avatar: const Icon(Icons.person_outline, size: 16),
                    label: Text(
                      conversation.assigneeName.isEmpty
                          ? 'Đã có người nhận'
                          : 'Do ${conversation.assigneeName} xử lý',
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
                    label: const Text('Gắn tag'),
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
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
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
      return const Padding(
        padding: EdgeInsets.all(WebTuiSpacing.xl),
        child: Text('Workspace chưa có tag nào.'),
      );
    }
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
              child: const Text('Lưu tag'),
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
    return const Material(
      color: WebTuiColors.surface,
      child: Padding(
        padding: EdgeInsets.all(WebTuiSpacing.md),
        child: Center(
          child: Text(
            'Bạn chỉ có quyền xem hộp thư này.',
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
              segments: const [
                ButtonSegment(
                  value: InboxComposeMode.reply,
                  label: Text('Trả lời'),
                ),
                ButtonSegment(
                  value: InboxComposeMode.note,
                  label: Text('Ghi chú'),
                ),
              ],
              selected: {state.mode},
              onSelectionChanged: (value) => controller.setMode(value.first),
            ),
            if (blocked)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                child: Text(
                  reason.isEmpty ? 'Chưa trả lời được hội thoại này.' : reason,
                  key: const Key('inbox_reply_blocked'),
                  style: const TextStyle(color: WebTuiColors.danger),
                ),
              ),
            if (noteMode)
              const Padding(
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
                          ? 'Viết ghi chú nội bộ...'
                          : blocked
                          ? 'Không thể trả lời'
                          : 'Trả lời khách...',
                    ),
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                IconButton.filled(
                  key: const Key('inbox_send'),
                  tooltip: noteMode ? 'Lưu ghi chú' : 'Gửi',
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
