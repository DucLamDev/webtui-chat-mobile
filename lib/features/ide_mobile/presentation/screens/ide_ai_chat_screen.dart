import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_dialogs.dart';
import '../../../../design_system/components/webtui_states.dart';
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
import '../widgets/ai/ide_ai_workbar.dart';
import '../widgets/ai/ide_approval_sheet.dart';
import '../widgets/ai/ide_session_settings_sheet.dart';
import '../widgets/files/ide_file_card.dart';
import '../widgets/ide_step_sheet.dart';
import '../widgets/ide_wb.dart';

/// Màn trò chuyện với AI (Claude / Codex) trong một phiên IDE.
class IdeAiChatScreen extends ConsumerStatefulWidget {
  IdeAiChatScreen({
    required String sessionKey,
    this.picker,
    this.autoOpenApprovals = true,
    this.initialText = '',
    this.info,
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
  }) : info = null,
       target = IdeAiOpenTarget.create(
         kind: kind,
         root: root,
         worktree: worktree ?? '',
       );

  final IdeAiOpenTarget target;

  /// Tên, loại AI, dự án của phiên (có khi mở từ danh sách phiên) để đầu
  /// trang hiện ngay; mở từ thông báo thì null.
  final IdeAiSessionItem? info;

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
  bool _showDown = false;
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
      final down = _scroll.position.maxScrollExtent - _scroll.offset > 400;
      if (down != _showDown) setState(() => _showDown = down);
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
    'forbidden' => tr(
      'Tài khoản hoặc địa chỉ máy chủ này chưa được phép dùng IDE.',
      'Your account or this server address is not allowed to use the IDE.',
    ),
    'wrong_user' => tr(
      'Máy này ghép IDE bằng tài khoản chat khác. Hãy gắn lại.',
      'This phone was paired with another chat account. Pair it again.',
    ),
    'session_expired' || 'no_session' => tr(
      'Phiên đăng nhập đã hết hạn. Đăng nhập lại rồi thử lại.',
      'Your session has expired. Sign in again, then retry.',
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
    backgroundColor: IdeWb.bg,
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
      backgroundColor: IdeWb.bg,
      appBar: _header(context, snap),
      // Đo chiều cao thật của vùng nội dung (đã trừ bàn phím) để ô gõ giãn có
      // giới hạn, không đẩy tràn khi bàn phím mở.
      body: LayoutBuilder(
        builder: (context, box) => Column(
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
                tone: IdeWb.warn,
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
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _body(snap, c)),
                  if (_showDown)
                    Positioned(
                      right: WebTuiSpacing.md,
                      bottom: WebTuiSpacing.sm,
                      child: _downButton(),
                    ),
                ],
              ),
            ),
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
                    backgroundColor: IdeWb.warn,
                  ),
                  onPressed: _openApprovals,
                  icon: const Icon(Icons.gpp_maybe_outlined),
                  label: Text(
                    tr('Cần duyệt ($approvals)', 'Needs approval ($approvals)'),
                  ),
                ),
              ),
            IdeAiComposer(
              top: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IdeAiWorkbar(
                    busy: view.busy,
                    waiting: approvals > 0,
                    startedAt: view.startedAt,
                    finishedAt: view.finishedAt,
                    tokens: ideAiTurnTokens(view.usage),
                  ),
                  IdeAiPlanPanel(plan: view.plan),
                ],
              ),
              tools: _tools(snap),
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
              maxInputHeight: box.maxHeight * 0.35,
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() => showIdeSessionSettings(
    context,
    target: _target,
    onJumpToMessage: _jumpTo,
  );

  /// Chip hàng dưới thẻ ô nhập (như IDE web): mô hình, % ngữ cảnh, chế độ.
  /// Chạm chip nào cũng mở Cài đặt phiên để đổi.
  List<Widget> _tools(IdeAiSnapshot snap) {
    final view = snap.view;
    final model = aiStr(view.settings['model']);
    final perms = aiMap(view.settings['permissions']);
    final pct = ideAiContextPercent(view.context);
    final mode = ideAiModeLabel(
      aiStr(perms['mode']),
      team: perms['team'] == true,
    );
    final modelLabel = model.isEmpty
        ? tr('Mặc định', 'Default')
        : _modelName(model);
    return [
      IdeAiChip(
        key: const Key('ide_ai_model_chip'),
        label: modelLabel,
        semantics: tr(
          'Model: $modelLabel. Chạm để đổi',
          'Model: $modelLabel. Tap to change',
        ),
        onTap: _openSettings,
      ),
      if (pct != null)
        IdeAiChip(
          key: const Key('ide_ai_context_chip'),
          label: '$pct%',
          leading: IdeAiContextBar(percent: pct),
          semantics: tr('Đã dùng $pct% ngữ cảnh', '$pct% of context used'),
          onTap: _openSettings,
        ),
      IdeAiChip(
        key: const Key('ide_ai_mode_chip'),
        label: mode,
        icon: Icons.bolt_rounded,
        accent: true,
        semantics: tr(
          'Chế độ: $mode. Chạm để đổi',
          'Mode: $mode. Tap to change',
        ),
        onTap: _openSettings,
      ),
    ];
  }

  /// "claude-opus-5-5" → "Opus 5.5"; tên lạ giữ nguyên.
  static String _modelName(String id) {
    final m = RegExp(r'^claude-([a-z]+)-(\d+)-(\d+)').firstMatch(id);
    if (m == null) return id;
    final n = m.group(1)!;
    return '${n[0].toUpperCase()}${n.substring(1)} ${m.group(2)}.${m.group(3)}';
  }

  Widget _downButton() => Material(
    color: IdeWb.bar,
    shape: CircleBorder(side: BorderSide(color: IdeWb.borderStrong)),
    elevation: 2,
    child: IconButton(
      key: const Key('ide_ai_scroll_down'),
      tooltip: tr('Xuống tin mới nhất', 'Jump to latest'),
      color: IdeWb.text,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: () {
        _stick = true;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      },
      icon: const Icon(Icons.arrow_downward_rounded, size: 20),
    ),
  );

  /// Thanh phiên như tab phiên của IDE web: biểu tượng AI, tên phiên + dự án,
  /// trạng thái (chấm màu), nút ⋯.
  PreferredSizeWidget _header(BuildContext context, IdeAiSnapshot snap) {
    final view = snap.view;
    final info = widget.info;
    final kind = info != null && info.kind.isNotEmpty
        ? info.kind
        : _target.kind;
    final project = info != null && info.project.isNotEmpty
        ? info.project
        : _target.root.isEmpty
        ? ''
        : aiBaseName(_target.root);
    final topic = info?.title.trim() ?? '';
    final waiting = view.approvals.isNotEmpty || view.planPending;
    final (status, dot) = snap.link == IdeAiLink.closed
        ? (tr('Đã đóng', 'Closed'), IdeWb.text2)
        : waiting
        ? (tr('Chờ bạn duyệt', 'Waiting for you'), IdeWb.warn)
        : view.busy
        ? (tr('Đang chạy', 'Running'), IdeWb.accentInk)
        : (tr('Sẵn sàng', 'Ready'), IdeWb.ok);
    final name = kind == 'codex' ? 'Codex' : 'Claude';
    // Cao theo cỡ chữ máy: tiêu đề + dòng trạng thái + lề, tối thiểu 52.
    final scaler = MediaQuery.textScalerOf(context);
    final textH = scaler.scale(14) * 1.3 + 1 + scaler.scale(11) * 1.2;
    final barH = textH + 12 > 52 ? (textH + 12).ceilToDouble() : 52.0;
    return PreferredSize(
      preferredSize: Size.fromHeight(barH),
      child: Material(
        color: IdeWb.bar,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: IdeWb.border)),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: barH,
              child: Row(
                children: [
                  IconButton(
                    key: const Key('ide_ai_back'),
                    tooltip: tr('Quay lại', 'Back'),
                    color: IdeWb.text,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: () => Navigator.of(context).canPop()
                        ? Navigator.of(context).pop()
                        : _leave(),
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  ),
                  _AgentMark(codex: kind == 'codex'),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          topic.isNotEmpty
                              ? topic
                              : project.isEmpty
                              ? name
                              : '$name · $project',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: IdeType.titleMedium.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: IdeWb.textStrong,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: dot,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                // Đã có tên phiên ở trên thì dòng dưới ghi
                                // thêm loại AI và dự án.
                                topic.isEmpty
                                    ? status
                                    : [
                                        status,
                                        name,
                                        if (project.isNotEmpty) project,
                                      ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WebTuiTypography.labelSmall.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: IdeWb.text2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('ide_ai_more'),
                    tooltip: tr('Cài đặt phiên', 'Session settings'),
                    color: IdeWb.text,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: _openSettings,
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                  const SizedBox(width: WebTuiSpacing.xs),
                ],
              ),
            ),
          ),
        ),
      ),
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
                  color: IdeWb.text2,
                ),
                Text(
                  tr(
                    'Thao tác (${widget.items.length})',
                    'Actions (${widget.items.length})',
                  ),
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: IdeWb.text2,
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

/// Dấu của trợ lý: ✳ cam cho Claude, ◎ cho Codex (như tab phiên IDE web).
class _AgentMark extends StatelessWidget {
  const _AgentMark({required this.codex});

  final bool codex;

  @override
  Widget build(BuildContext context) {
    final color = codex ? IdeWb.codex : IdeWb.claude;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        codex ? Icons.blur_circular_rounded : Icons.emergency_rounded,
        size: 17,
        color: color,
      ),
    );
  }
}
