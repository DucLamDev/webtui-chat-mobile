import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_dialogs.dart';
import '../../../../design_system/components/webtui_states.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../application/ide_ai_session_controller.dart';
import '../../application/ide_download_service.dart' show ideSafeFileName;
import '../controllers/ide_ai_controllers.dart';
import '../controllers/ide_controllers.dart';
import '../widgets/ai/ide_ai_activity_card.dart';
import '../widgets/ai/ide_ai_commands.dart';
import '../widgets/ai/ide_ai_composer.dart';
import '../widgets/ai/ide_ai_json.dart';
import '../widgets/ai/ide_ai_message_tile.dart';
import '../widgets/ai/ide_ai_panels.dart';
import '../widgets/ai/ide_approval_sheet.dart';
import '../widgets/ai/ide_session_settings_sheet.dart';
import '../widgets/files/ide_file_card.dart';
import '../widgets/ide_step_sheet.dart';

/// Màn trò chuyện với AI (Claude / Codex) trong một phiên IDE.
class IdeAiChatScreen extends ConsumerStatefulWidget {
  IdeAiChatScreen({
    required String sessionKey,
    this.picker,
    this.autoOpenApprovals = true,
    this.initialText = '',
    super.key,
  }) : target = IdeAiOpenTarget.existing(sessionKey);

  IdeAiChatScreen.newSession({
    required String kind,
    required String root,
    String? worktree,
    this.picker,
    this.autoOpenApprovals = true,
    this.initialText = '',
    super.key,
  }) : target = IdeAiOpenTarget.create(
         kind: kind,
         root: root,
         worktree: worktree ?? '',
       );

  final IdeAiOpenTarget target;

  /// Chữ điền sẵn vào ô soạn (vd `@đường-dẫn ` từ màn Tệp).
  final String initialText;

  /// Chỗ thay bộ chọn ảnh / tệp khi test.
  final IdeAttachmentPicker? picker;

  /// Tự mở bảng duyệt khi có thẻ duyệt mới.
  final bool autoOpenApprovals;

  @override
  ConsumerState<IdeAiChatScreen> createState() => _IdeAiChatScreenState();
}

class _IdeAiChatScreenState extends ConsumerState<IdeAiChatScreen> {
  late final IdeAiOpenTarget _target = widget.target;
  final _scroll = ScrollController();
  String? _highlight;
  bool _approvalOpen = false;
  int _lastApprovals = 0;
  bool _stick = true;
  int _lastCount = -1;
  String? _root;

  /// Phiên mới mà không có thư mục dự án: không tự mở phiên.
  bool get _invalidNew =>
      _target.sessionKey == null && _target.root.trim().isEmpty;

  late final IdeStepPresenterLease _lease;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _stick = _scroll.position.maxScrollExtent - _scroll.offset < 80;
    });
    _lease = IdeStepPresenterLease(ref.read(ideStepPresenterProvider.notifier));
    final connection = ref.read(ideConnectionProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lease.acquire(context, () => mounted);
      if (!_invalidNew) connection.start();
    });
  }

  @override
  void dispose() {
    _lease.release();
    _scroll.dispose();
    super.dispose();
  }

  IdeAiSessionController get _c =>
      ref.read(ideAiSessionControllerProvider(_target).notifier);

  void _say(String text) {
    if (!mounted || text.isEmpty) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _leave() {
    if (!mounted) return;
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/ide');
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _onSnapshot(IdeAiSnapshot? before, IdeAiSnapshot now) {
    if (now.link == IdeAiLink.closed && before?.link != IdeAiLink.closed) {
      _say(_closedText(now.closedReason));
      if (now.closedReason != null && now.closedReason != 'ide_offline') {
        _leave();
      }
    }
    if (now.problem != null && now.problem!.seq != before?.problem?.seq) {
      _say(
        now.problem!.viewOnly
            ? tr(
                'Bạn đang chỉ xem. Bấm "Điều khiển từ đây" để thao tác.',
                'View only. Take control to act.',
              )
            : now.problem!.message,
      );
    }
    if (now.notice != null && now.noticeSeq != before?.noticeSeq) {
      _say(now.notice!);
    }
    final approvals = now.view.approvals.length;
    if (widget.autoOpenApprovals &&
        approvals > _lastApprovals &&
        now.canControl &&
        !_approvalOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openApprovals());
    }
    _lastApprovals = approvals;
  }

  String _closedText(String? reason) => switch (reason) {
    'revoked' || 'unauthorized' || 'session_revoked' => tr(
      'Máy này không còn quyền vào IDE. Hãy ghép nối lại.',
      'This device no longer has IDE access. Pair it again.',
    ),
    _ => tr('Phiên đã đóng.', 'The session has closed.'),
  };

  Future<void> _openApprovals() async {
    if (!mounted || _approvalOpen) return;
    _approvalOpen = true;
    // Hết việc chờ duyệt thì đóng bảng đúng một lần, và chỉ đóng chính bảng:
    // dựng lại nhiều lần (chữ AI đang chạy) không được đóng luôn màn chat.
    var closing = false;
    await showIdeApprovalSheet(
      context,
      (_) => Consumer(
        builder: (context, ref, _) {
          final snap = ref.watch(ideAiSessionControllerProvider(_target));
          final c = ref.read(ideAiSessionControllerProvider(_target).notifier);
          final approvals = snap.view.approvals;
          final pending = snap.view.planPending;
          if (approvals.isEmpty && !pending && !closing) {
            closing = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              final route = ModalRoute.of(context);
              if (route == null || !route.isActive) return;
              if (route.isCurrent) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).removeRoute(route);
              }
            });
          }
          return IdeApprovalSheet(
            approvals: approvals,
            planPending: pending,
            plan: snap.view.plan,
            canControl: snap.canControl,
            onAnswer: (id, {required allow, answers, deepen = false}) =>
                c.answer(id, allow: allow, answers: answers, deepen: deepen),
            onApprovePlan: (d) => c.approvePlan(decisions: d),
            onDeepenPlan: c.deepenPlan,
          );
        },
      ),
    );
    _approvalOpen = false;
  }

  Future<String> _resolveRoot() async {
    if (_target.root.isNotEmpty) return _target.root;
    if (_root != null) return _root!;
    final rpc = ref.read(ideRpcClientProvider);
    final sessions = await ref.read(ideAiSessionsProvider.future);
    String project = '';
    for (final s in sessions) {
      if (s.key == _target.sessionKey) project = s.project;
    }
    final data = await rpc.call('projects.list', const {});
    final items = aiList(data is Map ? data['items'] : null);
    for (final p in items) {
      if (aiStr(p['name']) == project && aiStr(p['root']).startsWith('/')) {
        return _root = aiStr(p['root']);
      }
    }
    throw StateError('Chưa biết thư mục dự án để đính kèm.');
  }

  Future<String> _upload(IdePickedFile file) async {
    final root = await _resolveRoot();
    final dir =
        '${root.endsWith('/') ? root.substring(0, root.length - 1) : root}/.vpsttt/dinh-kem';
    final result = await ref.read(ideRpcClientProvider).upload('files.put', {
      'dir': dir,
      'name': ideSafeFileName(file.name),
      'size': file.size,
      'mime': file.mime,
    }, file.read());
    final path = result is Map ? aiStr(result['path']) : '';
    if (!path.startsWith('/')) throw StateError('Không nhận được đường dẫn.');
    return path;
  }

  Future<List<String>> _findFiles(String query) async {
    final root = await _resolveRoot();
    final data = await ref.read(ideRpcClientProvider).call('files.find', {
      'root': root,
      'q': query,
    });
    final raw = data is Map ? (data['items'] ?? data['files']) : data;
    final out = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String) {
          out.add(e);
        } else if (e is Map && aiStr(e['path']).isNotEmpty) {
          out.add(aiStr(e['path']));
        }
      }
    }
    return out;
  }

  Future<void> _confirmRewind(String id, {required bool redo}) async {
    final c = _c;
    try {
      final dry = redo
          ? await c.redo(id, dry: true)
          : await c.rewind(id, dry: true);
      if (!mounted) return;
      final error = aiStr(dry['error']);
      if (error.isNotEmpty) return _say(error);
      if (dry['canRewind'] == false) {
        return _say(
          tr('Không quay lui được lượt này.', 'This turn cannot be rewound.'),
        );
      }
      final files = aiInt(dry['total']) > 0
          ? aiInt(dry['total'])
          : (dry['files'] is List ? (dry['files'] as List).length : 0);
      final ok = await showWebTuiConfirmDialog(
        context,
        title: redo
            ? tr('Làm lại lượt này?', 'Redo this turn?')
            : tr(
                'Quay lui về trước tin này?',
                'Rewind to before this message?',
              ),
        message: tr(
          '$files tệp sẽ đổi (+${aiInt(dry['insertions'])} / -${aiInt(dry['deletions'])} dòng).',
          '$files files change (+${aiInt(dry['insertions'])} / -${aiInt(dry['deletions'])} lines).',
        ),
        confirmLabel: redo ? tr('Làm lại', 'Redo') : tr('Quay lui', 'Rewind'),
        destructive: !redo,
      );
      if (!ok || !mounted) return;
      final done = redo
          ? await c.redo(id, dry: false)
          : await c.rewind(id, dry: false);
      final err = aiStr(done['error']);
      if (err.isNotEmpty) _say(err);
    } on Object {
      _say(
        tr(
          'Không thực hiện được. Thử lại sau.',
          'Could not do that. Try again.',
        ),
      );
    }
  }

  void _jumpTo(String id) {
    final messages = ref
        .read(ideAiSessionControllerProvider(_target))
        .view
        .messages;
    final i = messages.indexWhere((m) => aiStr(m['id']) == id);
    if (i < 0 || !_scroll.hasClients) return;
    setState(() => _highlight = id);
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      messages.length <= 1 ? 0 : max * i / (messages.length - 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Widget _noRoot(BuildContext context) => Scaffold(
    backgroundColor: WebTuiColors.chatBackground,
    appBar: AppBar(
      title: Text(tr('Phiên mới', 'New session')),
      leading: IconButton(
        key: const Key('ide_ai_no_root_back'),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: const Icon(Icons.arrow_back_rounded),
        tooltip: tr('Quay lại', 'Back'),
        onPressed: _leave,
      ),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                'Chưa chọn thư mục dự án nên không mở được phiên mới.',
                'No project folder selected, so a new session cannot open.',
              ),
              textAlign: TextAlign.center,
              key: const Key('ide_ai_no_root'),
            ),
            const SizedBox(height: WebTuiSpacing.md),
            FilledButton(
              onPressed: _leave,
              style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text(tr('Quay lại', 'Back')),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_invalidNew) return _noRoot(context);
    ref.listen<IdeAiSnapshot>(
      ideAiSessionControllerProvider(_target),
      _onSnapshot,
    );
    final snap = ref.watch(ideAiSessionControllerProvider(_target));
    final c = _c;
    final view = snap.view;
    final messages = view.messages;
    final activity = view.activity;
    final count = messages.length + activity.length;
    if (count != _lastCount) {
      _lastCount = count;
      if (_stick) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    }
    final approvals = view.approvals.length + (view.planPending ? 1 : 0);
    return Scaffold(
      backgroundColor: WebTuiColors.chatBackground,
      appBar: _header(context, snap),
      body: Column(
        children: [
          if (snap.link == IdeAiLink.reconnecting ||
              (snap.link == IdeAiLink.connecting && snap.hasState))
            IdeAiBanner(
              icon: Icons.sync_rounded,
              text: tr('Đang kết nối lại…', 'Reconnecting…'),
            ),
          if (snap.hasRoleFrame && !snap.role.control)
            IdeAiBanner(
              key: const Key('ide_ai_view_only'),
              icon: Icons.visibility_outlined,
              text: tr('Chỉ xem', 'View only'),
              action: tr('Điều khiển từ đây', 'Control from here'),
              onAction: c.claim,
            ),
          if (view.stall is Map)
            IdeAiBanner(
              key: const Key('ide_ai_stall'),
              icon: Icons.hourglass_bottom_rounded,
              tone: WebTuiColors.accentAmber,
              text: tr(
                'AI có vẻ đang kẹt${aiStr(aiMap(view.stall)['tool']).isEmpty ? '' : ' (${aiStr(aiMap(view.stall)['tool'])})'}.',
                'The AI seems stuck.',
              ),
              action: snap.canControl ? tr('Chạy lại', 'Retry') : null,
              onAction: () {
                final since = aiMap(view.stall)['since'];
                c.restart(since is num ? since : null);
              },
            ),
          if (view.suggestion.isNotEmpty && snap.canControl)
            IdeAiBanner(
              key: const Key('ide_ai_suggestion'),
              icon: Icons.lightbulb_outline_rounded,
              text: view.suggestion,
              action: tr('Gửi', 'Send'),
              onAction: () => c.send(view.suggestion),
            ),
          IdeAiPlanPanel(plan: view.plan),
          Expanded(child: _body(snap, c)),
          IdeAiQueuePanel(
            queue: view.queue,
            paused: view.queuePaused,
            canControl: snap.canControl,
            onRemove: c.unqueue,
            onSendNow: c.sendNow,
            onRun: c.queueRun,
          ),
          if (approvals > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.md,
                WebTuiSpacing.xs,
                WebTuiSpacing.md,
                0,
              ),
              child: FilledButton.icon(
                key: const Key('ide_ai_open_approvals'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: WebTuiColors.accentAmber,
                ),
                onPressed: _openApprovals,
                icon: const Icon(Icons.gpp_maybe_outlined),
                label: Text(
                  tr('Cần duyệt ($approvals)', 'Needs approval ($approvals)'),
                ),
              ),
            ),
          IdeAiComposer(
            initialText: widget.initialText,
            canControl: snap.canControl && snap.link != IdeAiLink.closed,
            busy: view.busy,
            commands: view.commands,
            changedPaths: [
              for (final ch in view.changes)
                if (aiStr(ch['path']).isNotEmpty) aiStr(ch['path']),
            ],
            findFiles: _findFiles,
            upload: _upload,
            picker: widget.picker,
            onSend: (text, attachments) {
              final id = c.send(text, attachments: attachments);
              if (id == null) {
                _say(
                  tr(
                    'Chưa kết nối, thử lại sau giây lát.',
                    'Not connected yet.',
                  ),
                );
              }
              _stick = true;
            },
            onStop: c.interrupt,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _header(BuildContext context, IdeAiSnapshot snap) {
    final view = snap.view;
    final kind = _target.kind;
    final project = _target.root.isEmpty ? '' : aiBaseName(_target.root);
    final model = aiStr(view.settings['model']);
    final status = view.approvals.isNotEmpty || view.planPending
        ? tr('Chờ bạn duyệt', 'Waiting for you')
        : view.busy
        ? tr('Đang chạy', 'Running')
        : tr('Sẵn sàng', 'Ready');
    final title = [
      if (project.isNotEmpty) project,
      if (kind.isNotEmpty) (kind == 'codex' ? 'Codex' : 'Claude'),
    ].join(' · ');
    return AppBar(
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? tr('Phiên AI', 'AI session') : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WebTuiTypography.titleMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
          Text(
            [if (model.isNotEmpty) model, status].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textMuted,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          key: const Key('ide_ai_more'),
          tooltip: tr('Cài đặt phiên', 'Session settings'),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: () => showIdeSessionSettings(
            context,
            target: _target,
            onJumpToMessage: _jumpTo,
          ),
          icon: const Icon(Icons.more_horiz_rounded),
        ),
      ],
    );
  }

  Widget _body(IdeAiSnapshot snap, IdeAiSessionController c) {
    final view = snap.view;
    if (!snap.hasState) {
      if (snap.link == IdeAiLink.closed) {
        return WebTuiErrorState(
          title: tr('Không mở được phiên', 'Could not open the session'),
          message: _closedText(snap.closedReason),
          onRetry: c.retryNow,
        );
      }
      return WebTuiLoadingState(
        message: tr('Đang mở phiên…', 'Opening session…'),
      );
    }
    final messages = view.messages;
    final activity = view.activity;
    if (messages.isEmpty && activity.isEmpty) {
      return WebTuiEmptyState(
        icon: Icons.smart_toy_outlined,
        title: tr('Chưa có tin nhắn', 'No messages yet'),
        message: tr(
          'Hãy nhắn cho AI việc bạn cần làm.',
          'Tell the AI what you need.',
        ),
      );
    }
    final lastId = messages.isEmpty ? '' : aiStr(messages.last['id']);
    final artifacts = [
      for (final a in view.artifacts)
        if (aiStr(a['path']).isNotEmpty) a,
    ];
    return ListView(
      key: const Key('ide_ai_list'),
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.md,
        vertical: WebTuiSpacing.sm,
      ),
      children: [
        for (final m in messages)
          IdeAiMessageTile(
            key: ValueKey('msg-${aiStr(m['id'])}'),
            message: m,
            streaming:
                view.busy &&
                aiStr(m['id']) == lastId &&
                aiStr(m['role']) != 'user',
            canControl: snap.canControl,
            highlighted: aiStr(m['id']) == _highlight,
            onFormSubmit: (r) {
              // Mất kết nối: ném lỗi để biểu mẫu mở lại, không hiện "Đã gửi".
              if (c.send(r) == null) {
                _say(tr('Chưa gửi được: mất kết nối.', 'Not sent: offline.'));
                throw StateError('offline');
              }
            },
            onRewind: (id) => _confirmRewind(id, redo: false),
            onRedo: (id) => _confirmRewind(id, redo: true),
          ),
        if (activity.isNotEmpty)
          _ActivityGroup(items: activity, busy: view.busy),
        for (final a in artifacts)
          Padding(
            padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
            child: IdeFileCard(path: aiStr(a['path'])),
          ),
      ],
    );
  }
}

/// Các thao tác của lượt: mở khi đang chạy, thu gọn khi xong.
class _ActivityGroup extends StatefulWidget {
  const _ActivityGroup({required this.items, required this.busy});

  final List<Map<String, Object?>> items;
  final bool busy;

  @override
  State<_ActivityGroup> createState() => _ActivityGroupState();
}

class _ActivityGroupState extends State<_ActivityGroup> {
  bool? _open;

  @override
  Widget build(BuildContext context) {
    final open = _open ?? widget.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const Key('ide_ai_activity_group'),
          onTap: () => setState(() => _open = !open),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: WebTuiColors.textMuted,
                ),
                Text(
                  tr(
                    'Thao tác (${widget.items.length})',
                    'Actions (${widget.items.length})',
                  ),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open)
          for (final item in widget.items)
            IdeAiActivityCard(
              key: ValueKey('act-${aiStr(item['id'])}'),
              item: item,
            ),
      ],
    );
  }
}
