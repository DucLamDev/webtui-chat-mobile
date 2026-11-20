import 'package:flutter/material.dart';

import '../../../../../design_system/components/webtui_dialogs.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../ide_wb.dart';
import '../markdown/ide_markdown.dart';
import 'ide_ai_json.dart';
import 'ide_plan_decisions.dart';

/// Loại thẻ duyệt.
enum IdeApprovalKind { command, edit, question, plan, other }

IdeApprovalKind ideApprovalKind(Map<String, Object?> a) {
  final method = aiStr(a['method']);
  final params = aiMap(a['params']);
  if (method == 'claude/permission') {
    final tool = aiStr(params['tool_name']);
    if (tool == 'AskUserQuestion') return IdeApprovalKind.question;
    if (tool == 'ExitPlanMode') return IdeApprovalKind.plan;
    if (tool == 'Bash') return IdeApprovalKind.command;
    if (const {'Edit', 'Write', 'MultiEdit', 'NotebookEdit'}.contains(tool)) {
      return IdeApprovalKind.edit;
    }
    return IdeApprovalKind.other;
  }
  if (method.contains('commandExecution')) return IdeApprovalKind.command;
  if (method.contains('fileChange')) return IdeApprovalKind.edit;
  if (method.contains('requestUserInput')) return IdeApprovalKind.question;
  return IdeApprovalKind.other;
}

/// Câu hỏi trong một thẻ hỏi: (khoá trả lời, nội dung, chọn nhiều?, lựa chọn).
final class IdeAskQuestion {
  const IdeAskQuestion(this.key, this.text, this.multi, this.options);
  final String key;
  final String text;
  final bool multi;
  final List<({String label, String description})> options;
}

List<IdeAskQuestion> ideAskQuestions(Map<String, Object?> approval) {
  final params = aiMap(approval['params']);
  final claude = aiStr(approval['method']) == 'claude/permission';
  final raw = claude
      ? aiList(aiMap(params['input'])['questions'])
      : aiList(params['questions']);
  final out = <IdeAskQuestion>[];
  for (var i = 0; i < raw.length; i++) {
    final q = raw[i];
    final header = aiStr(q['header']);
    final key = claude ? (header.isEmpty ? '$i' : header) : aiStr(q['id']);
    out.add(
      IdeAskQuestion(
        key.isEmpty ? '$i' : key,
        aiStr(q['question']),
        aiBool(q['multiSelect']),
        [
          for (final o in aiList(q['options']))
            (label: aiStr(o['label']), description: aiStr(o['description'])),
        ],
      ),
    );
  }
  return out;
}

/// Bảng duyệt: danh sách thẻ đang chờ + kế hoạch sau lượt. Không giữ state
/// IDE: mọi nút gọi lại hàm truyền vào, nên dùng được trong Consumer.
class IdeApprovalSheet extends StatelessWidget {
  const IdeApprovalSheet({
    required this.approvals,
    required this.onAnswer,
    this.planPending = false,
    this.plan,
    this.onApprovePlan,
    this.onDeepenPlan,
    this.canControl = true,
    super.key,
  });

  final List<Map<String, Object?>> approvals;
  final bool planPending;
  final Object? plan;
  final bool canControl;

  /// `answers`: câu trả lời cho thẻ hỏi; `deepen`: "Làm rõ thêm".
  final void Function(
    String id, {
    required bool allow,
    Map<String, String>? answers,
    bool deepen,
  })
  onAnswer;
  final void Function(List<String> decisions)? onApprovePlan;
  final VoidCallback? onDeepenPlan;

  @override
  Widget build(BuildContext context) {
    final batchable = [
      for (final a in approvals)
        if (a['irreversible'] != true &&
            const {
              IdeApprovalKind.command,
              IdeApprovalKind.edit,
            }.contains(ideApprovalKind(a)))
          aiStr(a['id']),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            0,
            WebTuiSpacing.lg,
            WebTuiSpacing.lg,
          ),
          children: [
            WebTuiSheetHeader(
              title: tr('Cần duyệt', 'Needs approval'),
              subtitle: approvals.isEmpty && !planPending
                  ? tr('Không còn gì chờ duyệt.', 'Nothing waiting.')
                  : null,
            ),
            if (!canControl)
              Padding(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                child: Text(
                  tr(
                    'Chỉ xem: hãy bấm "Điều khiển từ đây" để duyệt.',
                    'View only: take control to approve.',
                  ),
                  style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
                ),
              ),
            if (batchable.length >= 2 && canControl)
              Padding(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                child: OutlinedButton(
                  key: const Key('ide_approval_batch'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    for (final id in batchable) {
                      onAnswer(id, allow: true);
                    }
                  },
                  child: Text(
                    tr(
                      'Cho phép cả loạt (${batchable.length})',
                      'Allow all (${batchable.length})',
                    ),
                  ),
                ),
              ),
            for (final a in approvals)
              Padding(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
                child: IdeApprovalCard(
                  key: ValueKey('approval-${aiStr(a['id'])}'),
                  approval: a,
                  canControl: canControl,
                  onAnswer: onAnswer,
                ),
              ),
            if (planPending && canControl && onApprovePlan != null)
              _PlanPendingCard(
                plan: plan,
                onApprove: onApprovePlan!,
                onDeepen: onDeepenPlan,
              ),
          ],
        ),
      ),
    );
  }
}

/// Mở bảng duyệt; [builder] nên bọc Consumer để cập nhật theo state.
Future<void> showIdeApprovalSheet(
  BuildContext context,
  WidgetBuilder builder,
) => showWebTuiSheet<void>(context: context, builder: builder);

class IdeApprovalCard extends StatefulWidget {
  const IdeApprovalCard({
    required this.approval,
    required this.onAnswer,
    this.canControl = true,
    super.key,
  });

  final Map<String, Object?> approval;
  final bool canControl;
  final void Function(
    String id, {
    required bool allow,
    Map<String, String>? answers,
    bool deepen,
  })
  onAnswer;

  @override
  State<IdeApprovalCard> createState() => _IdeApprovalCardState();
}

class _IdeApprovalCardState extends State<IdeApprovalCard> {
  final Map<String, Set<String>> _picked = {};
  final Map<String, TextEditingController> _free = {};

  @override
  void dispose() {
    for (final c in _free.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _id => aiStr(widget.approval['id']);
  bool get _irreversible => widget.approval['irreversible'] == true;

  Map<String, String> _answers(List<IdeAskQuestion> qs) {
    final out = <String, String>{};
    for (final q in qs) {
      final parts = [..._picked[q.key] ?? <String>{}];
      final free = _free[q.key]?.text.trim() ?? '';
      if (free.isNotEmpty) parts.add(free);
      if (parts.isNotEmpty) out[q.key] = parts.join(', ');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final kind = ideApprovalKind(widget.approval);
    final params = aiMap(widget.approval['params']);
    final input = aiMap(params['input']);
    final qs = kind == IdeApprovalKind.question
        ? ideAskQuestions(widget.approval)
        : const <IdeAskQuestion>[];
    final body = switch (kind) {
      IdeApprovalKind.command => _command(params, input),
      IdeApprovalKind.edit => _edit(params, input),
      IdeApprovalKind.question => _questions(qs),
      IdeApprovalKind.plan => _planText(aiStr(input['plan'])),
      IdeApprovalKind.other => _other(params),
    };
    final title = switch (kind) {
      IdeApprovalKind.command => tr('Chạy lệnh', 'Run command'),
      IdeApprovalKind.edit => tr('Sửa tệp', 'Edit files'),
      IdeApprovalKind.question => tr('AI hỏi bạn', 'AI asks you'),
      IdeApprovalKind.plan => tr('Kế hoạch', 'Plan'),
      IdeApprovalKind.other => tr('Xin quyền', 'Permission'),
    };
    return Container(
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: IdeWb.bar,
        border: Border.all(color: _irreversible ? IdeWb.danger : IdeWb.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: IdeType.titleMedium.copyWith(color: IdeWb.textStrong),
                ),
              ),
              if (_irreversible)
                Container(
                  key: const Key('ide_approval_important'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: WebTuiSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: IdeWb.danger,
                    borderRadius: BorderRadius.circular(WebTuiRadii.xs),
                  ),
                  child: Text(
                    tr('Quan trọng', 'Important'),
                    style: WebTuiTypography.labelSmall.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          body,
          if (widget.canControl) ...[
            const SizedBox(height: WebTuiSpacing.md),
            _actions(kind, qs),
          ],
        ],
      ),
    );
  }

  Widget _actions(IdeApprovalKind kind, List<IdeAskQuestion> qs) {
    final allowLabel = _irreversible
        ? tr('Đồng ý bằng vân tay', 'Approve with fingerprint')
        : kind == IdeApprovalKind.question
        ? tr('Gửi trả lời', 'Send answer')
        : kind == IdeApprovalKind.plan
        ? tr('Duyệt kế hoạch', 'Approve plan')
        : tr('Cho phép', 'Allow');
    return Wrap(
      spacing: WebTuiSpacing.sm,
      runSpacing: WebTuiSpacing.sm,
      children: [
        FilledButton.icon(
          key: Key('ide_approval_allow_$_id'),
          style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
          onPressed: () => widget.onAnswer(
            _id,
            allow: true,
            answers: kind == IdeApprovalKind.question ? _answers(qs) : null,
          ),
          icon: Icon(
            _irreversible ? Icons.fingerprint_rounded : Icons.check_rounded,
          ),
          label: Text(allowLabel),
        ),
        if (kind == IdeApprovalKind.question || kind == IdeApprovalKind.plan)
          OutlinedButton(
            key: Key('ide_approval_deepen_$_id'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(44, 48)),
            onPressed: () => widget.onAnswer(
              _id,
              allow: true,
              deepen: true,
              answers: kind == IdeApprovalKind.question ? _answers(qs) : null,
            ),
            child: Text(tr('Làm rõ thêm', 'Clarify more')),
          ),
        OutlinedButton(
          key: Key('ide_approval_deny_$_id'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(44, 48)),
          onPressed: () => widget.onAnswer(_id, allow: false),
          child: Text(tr('Từ chối', 'Deny')),
        ),
      ],
    );
  }

  Widget _mono(String text) => Container(
    padding: const EdgeInsets.all(WebTuiSpacing.sm),
    decoration: BoxDecoration(
      color: IdeWb.chip,
      borderRadius: BorderRadius.circular(WebTuiRadii.sm),
    ),
    child: SelectableText(
      text,
      style: IdeType.bodySmall.copyWith(
        fontFamily: WebTuiTypography.monoFamily,
        color: IdeWb.textStrong,
      ),
    ),
  );

  Widget _command(Map<String, Object?> params, Map<String, Object?> input) {
    final cmd = aiStr(input['command']).isNotEmpty
        ? aiStr(input['command'])
        : aiStr(params['command']);
    final cwd = aiStr(params['cwd']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mono(cmd),
        if (cwd.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
            child: Text(
              cwd,
              style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
            ),
          ),
      ],
    );
  }

  Widget _edit(Map<String, Object?> params, Map<String, Object?> input) {
    final changes = aiList(widget.approval['changes'] ?? params['changes']);
    final files = <(String, String)>[];
    for (final c in changes) {
      files.add((aiStr(c['path']), aiStr(c['diff'])));
    }
    if (files.isEmpty) {
      final path = aiStr(input['file_path']).isNotEmpty
          ? aiStr(input['file_path'])
          : aiStr(params['path']);
      final old = aiStr(input['old_string']);
      final neu = aiStr(input['new_string']).isNotEmpty
          ? aiStr(input['new_string'])
          : aiStr(input['content']);
      final diff = [
        for (final l in old.isEmpty ? const <String>[] : old.split('\n')) '-$l',
        for (final l in neu.isEmpty ? const <String>[] : neu.split('\n')) '+$l',
      ].join('\n');
      files.add((path, diff));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in files) ...[
          if (f.$1.isNotEmpty)
            Text(
              f.$1,
              style: IdeType.bodyMedium.copyWith(color: IdeWb.textStrong),
            ),
          if (f.$2.isNotEmpty) IdeDiffView(diff: f.$2),
          const SizedBox(height: WebTuiSpacing.xs),
        ],
      ],
    );
  }

  Widget _planText(String plan) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 260),
    child: SingleChildScrollView(child: IdeMarkdown(text: plan)),
  );

  Widget _other(Map<String, Object?> params) {
    final text = [
      aiStr(widget.approval['method']),
      aiStr(params['tool_name']),
      aiStr(params['reason']),
    ].where((e) => e.isNotEmpty).join('\n');
    return _mono(text);
  }

  Widget _questions(List<IdeAskQuestion> qs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final q in qs) ...[
          Text(
            q.text,
            style: IdeType.bodyMedium.copyWith(color: IdeWb.textStrong),
          ),
          for (final o in q.options) _option(q, o.label, o.description),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
            child: TextField(
              key: Key('ide_ask_free_${q.key}'),
              controller: _free.putIfAbsent(q.key, TextEditingController.new),
              decoration: InputDecoration(
                hintText: tr('Hoặc tự gõ câu trả lời', 'Or type your own'),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
        ],
      ],
    );
  }

  Widget _option(IdeAskQuestion q, String label, String description) {
    final set = _picked.putIfAbsent(q.key, () => <String>{});
    final on = set.contains(label);
    return InkWell(
      key: Key('ide_ask_option_${q.key}_$label'),
      borderRadius: BorderRadius.circular(WebTuiRadii.sm),
      onTap: () => setState(() {
        if (q.multi) {
          on ? set.remove(label) : set.add(label);
        } else {
          set
            ..clear()
            ..add(label);
        }
      }),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
        child: Row(
          children: [
            Icon(
              q.multi
                  ? (on
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded)
                  : (on
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded),
              color: on ? IdeWb.accentInk : IdeWb.text2,
            ),
            const SizedBox(width: WebTuiSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: IdeType.bodyMedium.copyWith(color: IdeWb.textStrong),
                  ),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diff tô màu: dòng `+` xanh, `-` đỏ, `@@` nhạt.
class IdeDiffView extends StatelessWidget {
  const IdeDiffView({required this.diff, super.key});

  final String diff;

  @override
  Widget build(BuildContext context) {
    final lines = diff.split('\n');
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: IdeWb.chip,
        borderRadius: BorderRadius.circular(WebTuiRadii.sm),
      ),
      // Nền xanh / đỏ phủ cả dòng: cột rộng ít nhất bằng khung, dòng dài thì
      // cuộn ngang.
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final l in lines)
                      Container(
                        color: l.startsWith('+') && !l.startsWith('+++')
                            ? IdeWb.ok.withValues(alpha: 0.18)
                            : l.startsWith('-') && !l.startsWith('---')
                            ? IdeWb.danger.withValues(alpha: 0.18)
                            : null,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          l.isEmpty ? ' ' : l,
                          style: IdeType.bodySmall.copyWith(
                            fontFamily: WebTuiTypography.monoFamily,
                            fontSize: 12,
                            color: l.startsWith('@@')
                                ? IdeWb.text2
                                : IdeWb.textStrong,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanPendingCard extends StatefulWidget {
  const _PlanPendingCard({
    required this.plan,
    required this.onApprove,
    this.onDeepen,
  });

  final Object? plan;
  final void Function(List<String> decisions) onApprove;
  final VoidCallback? onDeepen;

  @override
  State<_PlanPendingCard> createState() => _PlanPendingCardState();
}

class _PlanPendingCardState extends State<_PlanPendingCard> {
  late final List<IdePlanDecision> _decisions;
  late final List<TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    final text = widget.plan is String ? widget.plan! as String : '';
    _decisions = ideParsePlanDecisions(text);
    _ctrls = [
      for (final d in _decisions) TextEditingController(text: d.proposal),
    ];
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.plan is String ? widget.plan! as String : '';
    return Container(
      key: const Key('ide_plan_pending'),
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: IdeWb.bar,
        border: Border.all(color: IdeWb.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Kế hoạch chờ duyệt', 'Plan waiting for approval'),
            style: IdeType.titleMedium.copyWith(color: IdeWb.textStrong),
          ),
          if (text.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(child: IdeMarkdown(text: text)),
            ),
          for (var i = 0; i < _decisions.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
              child: TextField(
                controller: _ctrls[i],
                decoration: InputDecoration(
                  labelText: _decisions[i].question,
                  isDense: true,
                ),
              ),
            ),
          const SizedBox(height: WebTuiSpacing.md),
          Wrap(
            spacing: WebTuiSpacing.sm,
            runSpacing: WebTuiSpacing.sm,
            children: [
              FilledButton(
                key: const Key('ide_plan_approve'),
                style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                onPressed: () =>
                    widget.onApprove([for (final c in _ctrls) c.text.trim()]),
                child: Text(tr('Duyệt kế hoạch', 'Approve plan')),
              ),
              if (widget.onDeepen != null)
                OutlinedButton(
                  key: const Key('ide_plan_deepen'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 48),
                  ),
                  onPressed: widget.onDeepen,
                  child: Text(tr('Làm rõ thêm', 'Clarify more')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
