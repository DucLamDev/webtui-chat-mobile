import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_dialogs.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_ai_session_controller.dart';
import '../../controllers/ide_ai_controllers.dart';
import '../ide_wb.dart';
import 'ide_ai_json.dart';
import 'ide_approval_sheet.dart' show IdeDiffView;

const ideEffortLevels = ['low', 'medium', 'high', 'xhigh', 'max'];

/// (mode, tên, mô tả); `team` = Đội AI (mode plan + team). Không có `auto`:
/// điện thoại không được bật chế độ đó ([ideAiPhoneBlockedModes]).
const _modes = <(String, String, String)>[
  ('ask', 'Hỏi trước', 'Mỗi thao tác đều hỏi bạn.'),
  ('edits', 'Tự sửa tệp', 'Tự sửa tệp, chạy lệnh vẫn hỏi.'),
  ('custom', 'Tuỳ chỉnh', 'Theo danh sách công cụ / lệnh đã cho phép.'),
  ('plan', 'Lập kế hoạch', 'AI lập kế hoạch, bạn duyệt rồi mới làm.'),
  ('team', 'Đội AI', 'Lập kế hoạch rồi giao cả đội làm.'),
  ('all', 'Cho phép hết', 'Không hỏi gì: chỉ dùng khi thật tin tưởng.'),
];

Future<void> showIdeSessionSettings(
  BuildContext context, {
  required IdeAiOpenTarget target,
  ValueChanged<String>? onJumpToMessage,
}) => showWebTuiSheet<void>(
  context: context,
  builder: (_) =>
      IdeSessionSettingsSheet(target: target, onJumpToMessage: onJumpToMessage),
);

/// Bảng cài đặt và điều khiển phiên (nút ⋯).
class IdeSessionSettingsSheet extends ConsumerWidget {
  const IdeSessionSettingsSheet({
    required this.target,
    this.onJumpToMessage,
    super.key,
  });

  final IdeAiOpenTarget target;
  final ValueChanged<String>? onJumpToMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(ideAiSessionControllerProvider(target));
    final c = ref.read(ideAiSessionControllerProvider(target).notifier);
    final view = snap.view;
    final settings = view.settings;
    final perms = aiMap(settings['permissions']);
    final mode = aiStr(perms['mode']);
    final team = perms['team'] == true;
    final modelId = aiStr(settings['model']);
    final models = view.models;
    final model = models.cast<Map<String, Object?>?>().firstWhere(
      (m) => aiStr(m!['id']) == modelId,
      orElse: () => null,
    );
    final efforts = model == null || aiList(model['efforts']).isNotEmpty
        ? ideEffortLevels
        : [for (final e in (model['efforts'] as List? ?? const [])) '$e'];
    final effortList = model != null && model['efforts'] is List
        ? [for (final e in model['efforts'] as List) '$e']
        : efforts;
    final canControl = snap.canControl;
    final isCodex = target.kind == 'codex' || settings.containsKey('context');
    final usedPct = view.context['percent'] ?? view.context['pct'];
    final modeKey = mode == 'plan' && team ? 'team' : mode;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            WebTuiSheetHeader(title: tr('Cài đặt phiên', 'Session settings')),
            if (!canControl)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.lg,
                  vertical: WebTuiSpacing.sm,
                ),
                child: Text(
                  tr(
                    'Chỉ xem: hãy điều khiển từ đây để đổi cài đặt.',
                    'View only: take control to change settings.',
                  ),
                  style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
                ),
              ),
            _label(tr('Model', 'Model')),
            WebTuiSheetActionTile(
              key: const Key('ide_set_model'),
              icon: Icons.memory_rounded,
              title: modelId.isEmpty ? tr('Mặc định', 'Default') : modelId,
              subtitle: tr('Chạm để đổi model', 'Tap to change model'),
              onTap: !canControl
                  ? () {}
                  : () => _pickModel(context, c, models, modelId),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
              child: Wrap(
                spacing: WebTuiSpacing.sm,
                children: [
                  for (final e in ['', ...effortList])
                    ChoiceChip(
                      key: Key('ide_set_effort_$e'),
                      label: Text(e.isEmpty ? tr('Mặc định', 'Default') : e),
                      selected: aiStr(settings['effort']) == e,
                      onSelected: canControl
                          ? (_) => c.configure({'effort': e})
                          : null,
                    ),
                ],
              ),
            ),
            if (view.fastAllowed)
              SwitchListTile(
                key: const Key('ide_set_fast'),
                title: Text(tr('Chế độ nhanh', 'Fast mode')),
                value: aiBool(settings['fast']),
                onChanged: canControl ? (v) => c.configure({'fast': v}) : null,
              ),
            if (isCodex) ...[
              _label(tr('Ngữ cảnh', 'Context')),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.lg,
                ),
                child: Wrap(
                  spacing: WebTuiSpacing.sm,
                  children: [
                    for (final v in const ['', '512k', 'max'])
                      ChoiceChip(
                        key: Key('ide_set_context_$v'),
                        label: Text(v.isEmpty ? tr('Mặc định', 'Default') : v),
                        selected: aiStr(settings['context']) == v,
                        onSelected: canControl
                            ? (_) => c.configure({'context': v})
                            : null,
                      ),
                  ],
                ),
              ),
            ],
            SwitchListTile(
              key: const Key('ide_set_autosave'),
              title: Text(tr('Tự lưu ảnh AI tạo', 'Auto-save AI images')),
              value: aiBool(settings['autoSaveImages']),
              onChanged: canControl
                  ? (v) => c.configure({'autoSaveImages': v})
                  : null,
            ),
            _label(tr('Quyền của AI', 'AI permissions')),
            // Phiên đang `auto` (đặt từ máy tính): hiện đúng, không chọn lại được.
            if (modeKey == 'auto')
              WebTuiSheetActionTile(
                key: const Key('ide_set_mode_auto'),
                icon: Icons.lock_outline_rounded,
                title: tr('Tự động', 'Auto'),
                subtitle: tr(
                  'Đang bật từ máy tính. Điện thoại không bật được chế độ này.',
                  'Turned on from the computer. Phones cannot turn this on.',
                ),
                selected: true,
                onTap: null,
              ),
            for (final m in _modes)
              WebTuiSheetActionTile(
                key: Key('ide_set_mode_${m.$1}'),
                icon: m.$1 == 'all'
                    ? Icons.warning_amber_rounded
                    : Icons.shield_outlined,
                title: tr(m.$2, m.$2),
                subtitle: m.$3,
                selected: modeKey == m.$1,
                tone: m.$1 == 'all'
                    ? WebTuiDialogTone.danger
                    : WebTuiDialogTone.normal,
                onTap: !canControl
                    ? () {}
                    : () => _setMode(context, c, perms, m.$1),
              ),
            _label(tr('Cuộc trò chuyện', 'Conversation')),
            WebTuiSheetActionTile(
              key: const Key('ide_set_account'),
              icon: Icons.swap_horiz_rounded,
              title: tr('Đổi tài khoản AI', 'Change AI account'),
              subtitle: aiStr(view.accountActual).isEmpty
                  ? null
                  : aiStr(view.accountActual),
              onTap: !canControl ? () {} : () => _changeAccount(context, c),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_set_new'),
              icon: Icons.add_comment_outlined,
              title: tr('Chat mới', 'New chat'),
              onTap: !canControl
                  ? () {}
                  : () async {
                      final nav = Navigator.of(context);
                      final ok = await showWebTuiConfirmDialog(
                        context,
                        title: tr('Bắt đầu chat mới?', 'Start a new chat?'),
                        message: tr(
                          'Cuộc trò chuyện hiện tại sẽ được lưu vào lịch sử.',
                          'The current conversation is saved to history.',
                        ),
                        confirmLabel: tr('Chat mới', 'New chat'),
                      );
                      if (ok) {
                        c.reset();
                        nav.pop();
                      }
                    },
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_set_history'),
              icon: Icons.history_rounded,
              title: tr('Lịch sử cuộc trò chuyện', 'Conversation history'),
              onTap: () => _history(context, c, view.busy, canControl),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_set_search'),
              icon: Icons.search_rounded,
              title: tr('Tìm trong phiên / dự án', 'Search session / project'),
              onTap: () => _search(context, c),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_set_compact'),
              icon: Icons.compress_rounded,
              title: tr('Thu gọn ngữ cảnh', 'Compact context'),
              subtitle: usedPct == null
                  ? null
                  : tr('Đã dùng $usedPct%', 'Used $usedPct%'),
              onTap: !canControl
                  ? () {}
                  : () {
                      c.compact();
                      Navigator.of(context).pop();
                    },
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_set_restart'),
              icon: Icons.replay_rounded,
              title: tr('Chạy lại khi lỗi', 'Retry after error'),
              onTap: !canControl
                  ? () {}
                  : () {
                      final stall = view.stall;
                      final since = stall is Map ? stall['since'] : null;
                      c.restart(since is num ? since : null);
                      Navigator.of(context).pop();
                    },
            ),
            _label(tr('Việc đang chạy', 'Running work')),
            WebTuiSheetActionTile(
              key: const Key('ide_set_tasks'),
              icon: Icons.terminal_rounded,
              title: tr('Việc nền', 'Background tasks'),
              subtitle: '${view.tasks.length + view.background.length}',
              onTap: () => _tasks(context, c, [
                ...view.tasks,
                ...view.background,
              ], canControl),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_set_changes'),
              icon: Icons.difference_outlined,
              title: tr('Thay đổi trong lượt', 'Changes this turn'),
              subtitle: '${view.changes.length}',
              onTap: () => _changes(context, view.changes),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_set_usage'),
              icon: Icons.data_usage_rounded,
              title: tr('Mức dùng', 'Usage'),
              onTap: () => _usage(context, view.usage, view.quota),
            ),
            const SizedBox(height: WebTuiSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WebTuiSpacing.lg,
      WebTuiSpacing.md,
      WebTuiSpacing.lg,
      WebTuiSpacing.xs,
    ),
    child: Text(
      t,
      style: WebTuiTypography.labelSmall.copyWith(color: IdeWb.text2),
    ),
  );

  Future<void> _pickModel(
    BuildContext context,
    IdeAiSessionController c,
    List<Map<String, Object?>> models,
    String current,
  ) async {
    if (models.isEmpty) c.models();
    await showWebTuiSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            WebTuiSheetHeader(title: tr('Chọn model', 'Choose model')),
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.all(WebTuiSpacing.lg),
                child: Text(tr('Đang lấy danh sách model…', 'Loading models…')),
              ),
            WebTuiSheetActionTile(
              icon: Icons.auto_awesome_rounded,
              title: tr('Mặc định', 'Default'),
              selected: current.isEmpty,
              onTap: () {
                c.configure({'model': ''});
                Navigator.of(sheet).pop();
              },
            ),
            for (final m in models)
              WebTuiSheetActionTile(
                key: Key('ide_model_${aiStr(m['id'])}'),
                icon: Icons.memory_rounded,
                title: aiStr(m['name']).isEmpty
                    ? aiStr(m['id'])
                    : aiStr(m['name']),
                subtitle: aiStr(m['id']),
                selected: aiStr(m['id']) == current,
                onTap: () {
                  c.configure({'model': aiStr(m['id'])});
                  Navigator.of(sheet).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setMode(
    BuildContext context,
    IdeAiSessionController c,
    Map<String, Object?> perms,
    String key,
  ) async {
    if (key == 'all') {
      for (final step in [1, 2]) {
        if (!context.mounted) return;
        final ok = await showWebTuiConfirmDialog(
          context,
          title: step == 1
              ? tr('Cho phép AI làm mọi thứ?', 'Let the AI do everything?')
              : tr('Chắc chắn chưa?', 'Are you sure?'),
          message: step == 1
              ? tr(
                  'AI sẽ chạy lệnh và sửa tệp mà không hỏi bạn.',
                  'The AI will run commands and edit files without asking.',
                )
              : tr(
                  'Bấm xác nhận lần nữa để bật "Cho phép hết".',
                  'Confirm again to enable "Allow all".',
                ),
          confirmLabel: step == 1
              ? tr('Tiếp tục', 'Continue')
              : tr('Bật', 'Enable'),
          destructive: true,
        );
        if (!ok) return;
      }
    }
    final isTeam = key == 'team';
    c.configure({
      'permissions': {
        'mode': isTeam ? 'plan' : key,
        'tools': perms['tools'] is List ? perms['tools'] : const <Object?>[],
        'commands': perms['commands'] is List
            ? perms['commands']
            : const <Object?>[],
        if (isTeam) 'team': true,
      },
    });
  }

  Future<void> _changeAccount(
    BuildContext context,
    IdeAiSessionController c,
  ) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Đổi tài khoản AI', 'Change AI account')),
        content: TextField(
          key: const Key('ide_account_field'),
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr('Tên tài khoản', 'Account name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: Text(tr('Huỷ', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(ctrl.text.trim()),
            child: Text(tr('Đổi', 'Change')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty) c.changeAccount(name);
  }

  Future<void> _history(
    BuildContext context,
    IdeAiSessionController c,
    bool busy,
    bool canControl,
  ) async {
    await showWebTuiSheet<void>(
      context: context,
      builder: (sheet) => _FutureList(
        title: tr('Lịch sử cuộc trò chuyện', 'History'),
        future: c.history(),
        empty: tr('Chưa có cuộc trò chuyện nào.', 'No conversations yet.'),
        itemsOf: (r) => aiList(r['entries'] ?? r['items']),
        itemBuilder: (e) => WebTuiSheetActionTile(
          key: Key('ide_history_${aiStr(e['id'])}'),
          icon: Icons.chat_bubble_outline_rounded,
          title: aiStr(e['title']).isEmpty
              ? tr('(không tên)', '(untitled)')
              : aiStr(e['title']),
          subtitle: aiStr(e['preview']),
          onTap: () {
            if (busy) {
              ScaffoldMessenger.maybeOf(sheet)?.showSnackBar(
                SnackBar(
                  content: Text(
                    tr(
                      'Đang chạy: hãy bấm Dừng trước.',
                      'Busy: press Stop first.',
                    ),
                  ),
                ),
              );
              return;
            }
            if (!canControl) return;
            c.load(aiStr(e['id']));
            Navigator.of(sheet).pop();
          },
        ),
      ),
    );
  }

  Future<void> _search(BuildContext context, IdeAiSessionController c) async {
    await showWebTuiSheet<void>(
      context: context,
      builder: (sheet) => _SearchBody(
        controller: c,
        onPick: (id) {
          Navigator.of(sheet).pop();
          Navigator.of(context).pop();
          onJumpToMessage?.call(id);
        },
      ),
    );
  }

  Future<void> _tasks(
    BuildContext context,
    IdeAiSessionController c,
    List<Map<String, Object?>> tasks,
    bool canControl,
  ) async {
    await showWebTuiSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            WebTuiSheetHeader(title: tr('Việc nền', 'Background tasks')),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(WebTuiSpacing.lg),
                child: Text(tr('Không có việc nền.', 'No background tasks.')),
              ),
            for (final t in tasks)
              WebTuiSheetActionTile(
                icon: Icons.terminal_rounded,
                title: aiStr(t['title']).isEmpty
                    ? (aiStr(t['command']).isEmpty
                          ? aiStr(t['id'])
                          : aiStr(t['command']))
                    : aiStr(t['title']),
                subtitle: aiStr(t['status']),
                trailing: canControl && aiStr(t['status']) == 'running'
                    ? IconButton(
                        key: Key('ide_task_stop_${aiStr(t['id'])}'),
                        tooltip: tr('Dừng', 'Stop'),
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: () => c.stopTask(aiStr(t['id'])),
                        icon: const Icon(Icons.stop_circle_outlined),
                      )
                    : null,
                onTap: () => _taskLog(context, c, aiStr(t['id'])),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _taskLog(
    BuildContext context,
    IdeAiSessionController c,
    String id,
  ) => showWebTuiSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: FutureBuilder<Map<String, Object?>>(
        future: c.taskLog(id),
        builder: (context, snap) {
          final text = snap.hasError
              ? tr('Không đọc được nhật ký.', 'Could not read the log.')
              : snap.hasData
              ? aiStr(snap.data!['text'] ?? snap.data!['log'])
              : tr('Đang tải…', 'Loading…');
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(WebTuiSpacing.lg),
            children: [
              WebTuiSheetHeader(title: tr('Nhật ký việc nền', 'Task log')),
              SelectableText(
                text,
                style: IdeType.bodySmall.copyWith(
                  fontFamily: WebTuiTypography.monoFamily,
                  color: IdeWb.textStrong,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _changes(
    BuildContext context,
    List<Map<String, Object?>> changes,
  ) => showWebTuiSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
        children: [
          WebTuiSheetHeader(
            title: tr('Thay đổi trong lượt', 'Changes this turn'),
          ),
          if (changes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              child: Text(tr('Chưa sửa tệp nào.', 'No files changed.')),
            ),
          for (final ch in changes)
            Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${aiStr(ch['path'])}  +${aiInt(ch['added'])} -${aiInt(ch['removed'])}',
                    style: IdeType.bodyMedium.copyWith(color: IdeWb.textStrong),
                  ),
                  if (aiStr(ch['diff']).isNotEmpty)
                    IdeDiffView(diff: aiStr(ch['diff'])),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _usage(
    BuildContext context,
    Map<String, Object?> usage,
    Map<String, Object?> quota,
  ) => showWebTuiSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
        children: [
          WebTuiSheetHeader(title: tr('Mức dùng', 'Usage')),
          if (usage.isEmpty && quota.isEmpty)
            Padding(
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              child: Text(tr('Chưa có số liệu.', 'No data yet.')),
            ),
          for (final e in {...usage, ...quota}.entries)
            ListTile(
              dense: true,
              title: Text(e.key),
              trailing: Text(
                '${e.value is Map || e.value is List ? '' : e.value}',
              ),
            ),
        ],
      ),
    ),
  );
}

/// Danh sách tải bằng Future: đang tải / lỗi / rỗng / dữ liệu.
class _FutureList extends StatelessWidget {
  const _FutureList({
    required this.title,
    required this.future,
    required this.empty,
    required this.itemsOf,
    required this.itemBuilder,
  });

  final String title;
  final Future<Map<String, Object?>> future;
  final String empty;
  final List<Map<String, Object?>> Function(Map<String, Object?>) itemsOf;
  final Widget Function(Map<String, Object?>) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Map<String, Object?>>(
        future: future,
        builder: (context, snap) {
          Widget body;
          if (snap.hasError) {
            body = Padding(
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              child: Text(
                tr(
                  'Không tải được. Thử lại sau.',
                  'Could not load. Try again.',
                ),
              ),
            );
          } else if (!snap.hasData) {
            body = const Padding(
              padding: EdgeInsets.all(WebTuiSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            );
          } else {
            final items = itemsOf(snap.data!);
            body = items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(WebTuiSpacing.lg),
                    child: Text(empty),
                  )
                : Column(children: [for (final e in items) itemBuilder(e)]);
          }
          return ListView(
            shrinkWrap: true,
            children: [
              WebTuiSheetHeader(title: title),
              body,
            ],
          );
        },
      ),
    );
  }
}

class _SearchBody extends StatefulWidget {
  const _SearchBody({required this.controller, required this.onPick});

  final IdeAiSessionController controller;
  final ValueChanged<String> onPick;

  @override
  State<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends State<_SearchBody> {
  final _q = TextEditingController();
  String _scope = 'session';
  Future<Map<String, Object?>>? _future;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _run() {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() => _future = widget.controller.search(q, scope: _scope));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
        children: [
          WebTuiSheetHeader(title: tr('Tìm kiếm', 'Search')),
          TextField(
            key: const Key('ide_search_field'),
            controller: _q,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: tr('Gõ từ khoá', 'Type a keyword'),
              suffixIcon: IconButton(
                tooltip: tr('Tìm', 'Search'),
                onPressed: _run,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Wrap(
            spacing: WebTuiSpacing.sm,
            children: [
              ChoiceChip(
                label: Text(tr('Phiên này', 'This session')),
                selected: _scope == 'session',
                onSelected: (_) => setState(() => _scope = 'session'),
              ),
              ChoiceChip(
                label: Text(tr('Cả dự án', 'Whole project')),
                selected: _scope == 'project',
                onSelected: (_) => setState(() => _scope = 'project'),
              ),
            ],
          ),
          if (_future != null)
            FutureBuilder<Map<String, Object?>>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text(tr('Không tìm được.', 'Search failed.'));
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(WebTuiSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final hits = aiList(
                  snap.data!['results'] ??
                      snap.data!['items'] ??
                      snap.data!['hits'],
                );
                if (hits.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(WebTuiSpacing.lg),
                    child: Text(tr('Không thấy kết quả.', 'No results.')),
                  );
                }
                return Column(
                  children: [
                    for (final h in hits)
                      ListTile(
                        minTileHeight: 52,
                        title: Text(
                          aiStr(h['text']).isEmpty
                              ? aiStr(h['snippet'])
                              : aiStr(h['text']),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () =>
                            widget.onPick(aiStr(h['id'] ?? h['message'])),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
