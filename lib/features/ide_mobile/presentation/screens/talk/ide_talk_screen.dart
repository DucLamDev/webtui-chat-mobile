import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_talk_controller.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_talk_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';
import 'ide_talk_agent_sheet.dart';
import 'ide_talk_composer.dart';
import 'ide_talk_messages.dart';
import 'ide_talk_providers.dart';

/// Một cuộc chat thường: stream `talk`, gửi / dừng / hàng chờ, chia sẻ, agent.
class IdeTalkScreen extends ConsumerStatefulWidget {
  const IdeTalkScreen({required this.talkId, super.key});

  final String talkId;

  @override
  ConsumerState<IdeTalkScreen> createState() => _IdeTalkScreenState();
}

class _IdeTalkScreenState extends ConsumerState<IdeTalkScreen>
    with WidgetsBindingObserver {
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    super.dispose();
  }

  IdeTalkController get _ctl =>
      ref.read(ideTalkControllerProvider(widget.talkId).notifier);

  // Stream chỉ chạy khi app ở trước VÀ màn này đang là route trên cùng (mở
  // cuộc khác đè lên thì dừng, quay lại thì mở lại). Cách của màn hàng chờ gộp.
  bool _appForeground = true;
  bool _routeCurrent = true;

  void _syncStream() {
    if (!mounted) return;
    if (_appForeground && _routeCurrent) {
      _ctl.resume();
    } else {
      _ctl.pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current != _routeCurrent) {
      _routeCurrent = current;
      _syncStream();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _appForeground = false;
      _syncStream();
    } else if (s == AppLifecycleState.resumed) {
      _appForeground = true;
      _syncStream();
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<T?> _run<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } on IdeCancelled {
      return null;
    } on Object catch (e) {
      _snack(ideMoreErrorText(e));
      return null;
    }
  }

  Future<bool> _send(String text, List<IdeTalkAttachment> files) async {
    final r = await _run(() => _ctl.send(text, attachments: files));
    if (r == null) return false;
    if (r.queued) {
      _snack(tr('Đã xếp vào hàng chờ.', 'Added to the queue.'));
    } else if (r.note.isNotEmpty) {
      _snack(ideVisibleText(r.note));
    }
    return true;
  }

  Future<void> _share() async {
    final svc = ref.read(ideTalkServiceProvider);
    final r = await _run(
      () => _ctl.guard('share', () => svc.share(widget.talkId)),
    );
    if (r == null || !mounted) return;
    final text = r.url ?? r.link;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đã tạo link chia sẻ', 'Share link created')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Mọi nhân viên đã đăng nhập mở được, kể cả tin sau này, tới khi bạn dừng chia sẻ.',
                'Any signed-in employee can open it, including later messages, until you stop sharing.',
              ),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            SelectableText(ideVisibleText(text)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('Đóng', 'Close')),
          ),
          FilledButton(
            key: const Key('talk_share_copy'),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: ideTalkCleanText(text)),
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
              _snack(tr('Đã chép.', 'Copied.'));
            },
            child: Text(tr('Chép', 'Copy')),
          ),
        ],
      ),
    );
  }

  Future<void> _stopShare() async {
    final svc = ref.read(ideTalkServiceProvider);
    final ok = await _run(
      () => _ctl.guard('share', () async {
        await svc.stopShare(widget.talkId);
        return true;
      }),
    );
    if (ok == true) _snack(tr('Đã dừng chia sẻ.', 'Sharing stopped.'));
  }

  Future<void> _saveAgent(IdeTalkConversation conv) async {
    final firstUser = conv.messages.where((m) => m.isUser).firstOrNull?.text;
    final msg = await showIdeTalkAgentSheet(
      context,
      talkId: widget.talkId,
      // Tiêu đề GỐC đã lọc ký tự Cf / điều khiển (không phải chuỗi hiển thị có
      // `⏎` / `<U+202E>`), cắt theo ký tự người dùng thấy.
      initialName: ideTalkCleanText(
        conv.title,
      ).trim().characters.take(60).string,
      initialTask: (firstUser ?? '').characters.take(8000).string,
      agent: conv.agent,
      canDraft: ideTalkCan(ref, 'talk.agent_draft'),
    );
    if (msg != null) _snack(msg);
  }

  Future<void> _runAgent() async {
    final svc = ref.read(ideTalkServiceProvider);
    final id = await _run(
      () => _ctl.guard('agent_run', () => svc.agentRun(widget.talkId)),
    );
    if (id == null || !mounted) return;
    if (ideTalkIdOk(id) && id != widget.talkId) {
      await context.push('/ide/talk/$id');
    } else {
      _snack(tr('Agent đang chạy.', 'The agent is running.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(ideTalkControllerProvider(widget.talkId));
    final conv = st.conversation;
    bool has(String op) => ideTalkHasOp(ref, op);
    final title = conv == null || conv.title.trim().isEmpty
        ? tr('Chat thường', 'Chat')
        : ideVisibleText(conv.title);
    return IdeMorePage(
      title: title,
      actions: [
        if (conv != null)
          PopupMenuButton<String>(
            key: const Key('talk_menu'),
            tooltip: tr('Thêm', 'More'),
            onSelected: (v) {
              switch (v) {
                case 'share':
                  unawaited(_share());
                case 'unshare':
                  unawaited(_stopShare());
                case 'agent':
                  unawaited(_saveAgent(conv));
                case 'run':
                  unawaited(_runAgent());
              }
            },
            itemBuilder: (_) => [
              if (has('talk.share') && !conv.shared)
                PopupMenuItem(
                  value: 'share',
                  height: 48,
                  child: Text(tr('Chia sẻ cuộc chat', 'Share chat')),
                ),
              if (has('talk.share') && conv.shared)
                PopupMenuItem(
                  value: 'unshare',
                  height: 48,
                  child: Text(tr('Dừng chia sẻ', 'Stop sharing')),
                ),
              if (has('talk.agent_save'))
                PopupMenuItem(
                  value: 'agent',
                  height: 48,
                  child: Text(
                    conv.isAgent
                        ? tr('Sửa AI Agent', 'Edit AI Agent')
                        : tr('Lưu thành AI Agent', 'Save as AI Agent'),
                  ),
                ),
              if (conv.isAgent && has('talk.agent_run'))
                PopupMenuItem(
                  value: 'run',
                  height: 48,
                  child: Text(tr('Chạy ngay', 'Run now')),
                ),
            ],
          ),
      ],
      body: _body(st, has),
    );
  }

  Widget _body(IdeTalkState st, bool Function(String) has) {
    final conv = st.conversation;
    if (conv == null) {
      return switch (st.link) {
        IdeTalkLink.connecting => WebTuiLoadingState(
          message: tr('Đang mở cuộc chat...', 'Opening the chat...'),
        ),
        IdeTalkLink.notFound => const IdeMoreErrorView(error: IdeNotFound()),
        IdeTalkLink.denied => const IdeMoreErrorView(error: IdeForbidden()),
        IdeTalkLink.gone => WebTuiEmptyState(
          title: tr('Cuộc chat đã bị xoá', 'This chat was deleted'),
          message: tr(
            'Cuộc chat này không còn nữa.',
            'This chat no longer exists.',
          ),
          icon: Icons.delete_outline_rounded,
        ),
        IdeTalkLink.busy => WebTuiErrorState(
          title: tr('Đang mở quá nhiều cuộc chat', 'Too many chats open'),
          message: tr(
            'Hãy đóng bớt cuộc chat khác rồi thử lại.',
            'Close another chat and try again.',
          ),
          onRetry: _ctl.reconnect,
        ),
        _ => IdeMoreErrorView(
          error: st.link == IdeTalkLink.lost
              ? const IdeOffline()
              : const IdeError(),
          onRetry: _ctl.reconnect,
        ),
      };
    }
    final canSend = has('talk.send');
    final gone = st.link == IdeTalkLink.gone;
    return Column(
      children: [
        if (st.link == IdeTalkLink.lost || st.link == IdeTalkLink.connecting)
          _Banner(
            text: st.link == IdeTalkLink.lost
                ? tr(
                    'Mất kết nối, đang nối lại...',
                    'Disconnected, reconnecting...',
                  )
                : tr('Đang nối lại...', 'Reconnecting...'),
            action: st.link == IdeTalkLink.lost
                ? TextButton(
                    key: const Key('talk_reconnect'),
                    onPressed: _ctl.reconnect,
                    child: Text(tr('Nối lại', 'Retry')),
                  )
                : null,
          ),
        if (gone)
          _Banner(text: tr('Cuộc chat đã bị xoá.', 'This chat was deleted.')),
        Expanded(
          child: _Messages(
            talkId: widget.talkId,
            conv: conv,
            input: _input,
            canFile: has('talk.file'),
          ),
        ),
        if (conv.queue.isNotEmpty)
          _QueuePanel(
            conv: conv,
            st: st,
            onRun: has('talk.queue_run')
                ? () => unawaited(_run(() => _ctl.queueRun()))
                : null,
            onRemove: has('talk.unqueue')
                ? (id) => unawaited(_run(() => _ctl.unqueue(id)))
                : null,
          ),
        if (conv.isAgent && !gone)
          IdeTalkAgentBar(
            busy: st.isWorking('agent_run'),
            onRun: has('talk.agent_run') ? () => unawaited(_runAgent()) : null,
          )
        else if (canSend && !gone)
          IdeTalkComposer(
            controller: _input,
            working: conv.working,
            sending: st.isWorking('send'),
            canStop: has('talk.stop'),
            canAttach: has('talk.upload_slot'),
            onSend: _send,
            onStop: () => unawaited(_run(() => _ctl.stop())),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: IdeWb.warn.withValues(alpha: 0.16),
    padding: const EdgeInsets.symmetric(
      horizontal: WebTuiSpacing.lg,
      vertical: WebTuiSpacing.xs,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: IdeType.bodySmall.copyWith(color: IdeWb.textStrong),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class _Messages extends StatelessWidget {
  const _Messages({
    required this.talkId,
    required this.conv,
    required this.input,
    required this.canFile,
  });

  final String talkId;
  final IdeTalkConversation conv;
  final TextEditingController input;
  final bool canFile;

  @override
  Widget build(BuildContext context) {
    final msgs = conv.messages;
    if (msgs.isEmpty && conv.truncatedBefore == 0) {
      return WebTuiEmptyState(
        title: tr('Chưa có tin nhắn', 'No messages yet'),
        message: tr('Hãy nhắn cho AI.', 'Send the AI a message.'),
        icon: Icons.chat_bubble_outline_rounded,
      );
    }
    final extra = conv.truncatedBefore > 0 ? 1 : 0;
    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      itemCount: msgs.length + extra,
      separatorBuilder: (_, _) => const SizedBox(height: WebTuiSpacing.md),
      itemBuilder: (context, i) {
        if (i == msgs.length) {
          return Padding(
            key: const Key('talk_truncated'),
            padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
            child: Text(
              tr(
                'Tin cũ hơn đã bị lược (${conv.truncatedBefore} tin), xem trên máy tính.',
                'Older messages were trimmed (${conv.truncatedBefore}); see them on the computer.',
              ),
              textAlign: TextAlign.center,
              style: IdeType.bodySmall.copyWith(color: IdeWb.text),
            ),
          );
        }
        final m = msgs[msgs.length - 1 - i];
        return IdeTalkMessageTile(
          key: ValueKey(m.id),
          talkId: talkId,
          message: m,
          canDownload: canFile,
          onFollowup: (q) {
            final clean = ideTalkCleanText(q, keepLayout: true);
            input.text = clean;
            input.selection = TextSelection.collapsed(offset: clean.length);
          },
        );
      },
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.conv,
    required this.st,
    required this.onRun,
    required this.onRemove,
  });

  final IdeTalkConversation conv;
  final IdeTalkState st;
  final VoidCallback? onRun;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('talk_queue'),
      width: double.infinity,
      color: IdeWb.chip,
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.lg,
        vertical: WebTuiSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  conv.queuePaused
                      ? tr('Hàng chờ (đang tạm dừng)', 'Queue (paused)')
                      : tr('Hàng chờ', 'Queue'),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: IdeWb.text,
                  ),
                ),
              ),
              if (conv.queuePaused && onRun != null)
                TextButton(
                  key: const Key('talk_queue_run'),
                  onPressed: st.isWorking('queue_run') ? null : onRun,
                  child: Text(tr('Chạy tiếp', 'Resume')),
                ),
            ],
          ),
          for (final q in conv.queue)
            Row(
              children: [
                Expanded(
                  child: Text(
                    ideVisibleText(q.text),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IdeType.bodySmall.copyWith(color: IdeWb.textStrong),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    key: Key('talk_unqueue_${q.id}'),
                    tooltip: tr('Bỏ khỏi hàng chờ', 'Remove from queue'),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: st.isWorking('unqueue:${q.id}')
                        ? null
                        : () => onRemove!(q.id),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

final _ideTalkBadKeep = RegExp(
  r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f\u2028\u2029]|\p{Cf}',
  unicode: true,
);

/// Bỏ ký tự điều khiển / định dạng vô hình (Cf, đảo chiều chữ). [keepLayout]
/// giữ xuống dòng và tab (chép vào ô soạn); mặc định đổi chúng thành dấu cách.
String ideTalkCleanText(String raw, {bool keepLayout = false}) {
  if (keepLayout) return raw.replaceAll(_ideTalkBadKeep, '');
  return raw
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f-\u009f\u2028\u2029]'), ' ')
      .replaceAll(RegExp(r'\p{Cf}', unicode: true), '');
}
