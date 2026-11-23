import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_deploy.dart';
import '../../../domain/ide_project.dart';
import '../../../domain/ide_project_info.dart';
import '../../controllers/ide_project_ops_controllers.dart';
import '../../controllers/ide_term_controllers.dart';
import '../../widgets/ide_wb.dart';
import '../../widgets/projects/ide_project_ui.dart';

EdgeInsets _pad(BuildContext context) => EdgeInsets.fromLTRB(
  WebTuiSpacing.lg,
  0,
  WebTuiSpacing.lg,
  WebTuiSpacing.lg + MediaQuery.viewPaddingOf(context).bottom,
);

Widget _inlineError(String? text) => text == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
        child: Text(
          text,
          key: const Key('ide_sheet_error'),
          style: IdeType.bodySmall.copyWith(color: IdeWb.danger),
        ),
      );

// ---------------------------------------------------------------- Tạo PR

/// Sheet tạo PR; trả mã job `pr.create` (mở `/ide/jobs/<job>`).
Future<String?> showIdeCreatePrSheet(
  BuildContext context,
  IdeProject project,
) => showWebTuiSheet<String>(
  context: context,
  builder: (_) => IdeCreatePrSheet(project: project),
);

class IdeCreatePrSheet extends ConsumerStatefulWidget {
  const IdeCreatePrSheet({required this.project, super.key});

  final IdeProject project;

  @override
  ConsumerState<IdeCreatePrSheet> createState() => _CreatePrState();
}

class _CreatePrState extends ConsumerState<IdeCreatePrSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _draft = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final job = await ref
          .read(ideProjectServiceProvider)
          .createPr(
            widget.project.name,
            title: _title.text,
            body: _body.text,
            draft: _draft,
          );
      if (mounted) Navigator.of(context).pop(job);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ideProjectErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: _pad(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WebTuiSheetHeader(
              title: tr('Tạo PR', 'Create PR'),
              subtitle: tr(
                'Gửi các thay đổi của nhánh hiện tại để người khác duyệt.',
                'Send this branch for review.',
              ),
            ),
            TextField(
              key: const Key('ide_pr_title'),
              controller: _title,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: tr(
                  'Tiêu đề (bỏ trống để tự đặt)',
                  'Title (optional)',
                ),
              ),
            ),
            TextField(
              key: const Key('ide_pr_body'),
              controller: _body,
              maxLength: 4000,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: tr('Nội dung', 'Description'),
              ),
            ),
            SwitchListTile(
              key: const Key('ide_pr_draft'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Bản nháp', 'Draft')),
              subtitle: Text(
                tr('Chưa sẵn sàng để gộp.', 'Not ready to merge yet.'),
              ),
              value: _draft,
              onChanged: _busy ? null : (v) => setState(() => _draft = v),
            ),
            _inlineError(_error),
            const SizedBox(height: WebTuiSpacing.md),
            SizedBox(
              width: double.infinity,
              child: IdeProjectButton(
                key: const Key('ide_pr_submit'),
                primary: true,
                icon: Icons.call_merge_rounded,
                label: _busy
                    ? tr('Đang gửi...', 'Sending...')
                    : tr('Tạo PR', 'Create PR'),
                onPressed: _busy ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Gộp PR

/// Kết quả bấm "Gộp PR" cho tab xử lý tiếp.
final class IdeMergeOutcome {
  const IdeMergeOutcome({
    required this.number,
    required this.job,
    required this.ok,
    this.result = const IdeMergeResult(),
    this.failure = '',
  });

  final int number;
  final String job;
  final bool ok;
  final IdeMergeResult result;
  final String failure;
}

Future<IdeMergeOutcome?> showIdeMergePrSheet(
  BuildContext context,
  IdeProject project,
) => showWebTuiSheet<IdeMergeOutcome>(
  context: context,
  isDismissible: false,
  builder: (_) => IdeMergePrSheet(project: project),
);

class IdeMergePrSheet extends ConsumerStatefulWidget {
  const IdeMergePrSheet({required this.project, super.key});

  final IdeProject project;

  @override
  ConsumerState<IdeMergePrSheet> createState() => _MergePrState();
}

class _MergePrState extends ConsumerState<IdeMergePrSheet> {
  final _number = TextEditingController();
  bool _busy = false;
  bool _disposed = false;
  String? _error;

  @override
  void dispose() {
    _disposed = true;
    _number.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final n = ideParsePrNumber(_number.text);
    if (n == null) {
      setState(
        () => _error = tr(
          'Nhập số PR (số nguyên dương).',
          'Enter a PR number (positive integer).',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final svc = ref.read(ideProjectServiceProvider);
    try {
      final job = await svc.merge(widget.project.name, n);
      final out = await svc.waitJob(
        job,
        poll: ref.read(ideProjectPollIntervalProvider),
        isCancelled: () => _disposed,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        IdeMergeOutcome(
          number: n,
          job: job,
          ok: out.ok,
          result: IdeMergeResult.parse(out.result),
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ideProjectErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: _pad(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WebTuiSheetHeader(
              title: tr('Gộp PR', 'Merge PR'),
              subtitle: tr(
                'Cần xác nhận bằng vân tay. Dự án bật hàng chờ thì PR được xếp hàng.',
                'Needs fingerprint confirmation. With a queue the PR is queued.',
              ),
            ),
            TextField(
              key: const Key('ide_merge_number'),
              controller: _number,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Số PR', 'PR number')),
            ),
            _inlineError(_error),
            const SizedBox(height: WebTuiSpacing.md),
            if (_busy)
              IdeProgressLine(text: tr('Đang gộp PR...', 'Merging PR...'))
            else
              Row(
                children: [
                  Expanded(
                    child: IdeProjectButton(
                      key: const Key('ide_merge_cancel'),
                      icon: Icons.close_rounded,
                      label: tr('Đóng', 'Close'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: WebTuiSpacing.md),
                  Expanded(
                    child: IdeProjectButton(
                      key: const Key('ide_merge_submit'),
                      primary: true,
                      icon: Icons.call_merge_rounded,
                      label: tr('Gộp PR', 'Merge PR'),
                      onPressed: _submit,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- Chuyển sang Git

/// Kiểm tra rồi chuyển dự án sang Git; trả mã job `to_git.apply`.
Future<String?> showIdeToGitSheet(BuildContext context, IdeProject project) =>
    showWebTuiSheet<String>(
      context: context,
      builder: (_) => IdeToGitSheet(project: project),
    );

class IdeToGitSheet extends ConsumerStatefulWidget {
  const IdeToGitSheet({required this.project, super.key});

  final IdeProject project;

  @override
  ConsumerState<IdeToGitSheet> createState() => _ToGitState();
}

class _ToGitState extends ConsumerState<IdeToGitSheet> {
  IdeToGitCheck? _check;
  Object? _loadError;
  bool _loading = true;
  bool _applying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final c = await ref
          .read(ideProjectServiceProvider)
          .toGitCheck(widget.project.name);
      if (mounted) {
        setState(() {
          _check = c;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _apply() async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Chuyển dự án sang Git?', 'Move project to Git?'),
      message: tr(
        'Dự án sẽ có repo riêng và dùng Tạo PR / Gộp PR thay cho triển khai cũ.',
        'The project gets its own repo and uses PRs instead of the old deploy.',
      ),
      confirmLabel: tr('Chuyển sang Git', 'Move to Git'),
      cancelLabel: tr('Để sau', 'Later'),
      icon: Icons.merge_type_rounded,
    );
    if (!ok || !mounted) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final job = await ref
          .read(ideProjectServiceProvider)
          .startJob('to_git.apply', {
            'project': widget.project.name,
            if (_check?.repoName.isNotEmpty ?? false)
              'repo_name': _check!.repoName,
          });
      if (mounted) Navigator.of(context).pop(job);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _applying = false;
          _error = ideProjectErrorText(e);
        });
      }
    }
  }

  (IconData, Color) _levelView(IdeCheckLevel l) => switch (l) {
    IdeCheckLevel.ok => (Icons.check_circle_rounded, IdeWb.ok),
    IdeCheckLevel.warn => (Icons.warning_amber_rounded, IdeWb.warn),
    IdeCheckLevel.bad => (Icons.cancel_rounded, IdeWb.danger),
  };

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final Widget body;
    if (_loading) {
      body = SizedBox(
        height: 160,
        child: WebTuiLoadingState(
          message: tr('Đang kiểm tra dự án...', 'Checking the project...'),
        ),
      );
    } else if (_loadError != null) {
      body = SizedBox(
        height: 240,
        child: ideProjectErrorView(_loadError!, onRetry: _load),
      );
    } else if (check == null || check.rows.isEmpty) {
      body = SizedBox(
        height: 160,
        child: WebTuiEmptyState(
          title: tr('Chưa có mục kiểm tra', 'Nothing to check'),
          message: tr('IDE không trả kết quả.', 'The IDE returned nothing.'),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in check.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _levelView(r.level).$1,
                    size: 20,
                    color: _levelView(r.level).$2,
                  ),
                  const SizedBox(width: WebTuiSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: IdeType.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: IdeWb.textStrong,
                          ),
                        ),
                        if (r.detail.isNotEmpty)
                          Text(
                            r.detail,
                            style: IdeType.bodySmall.copyWith(
                              color: IdeWb.text,
                            ),
                          ),
                        if (r.fix.isNotEmpty && r.level != IdeCheckLevel.ok)
                          Text(
                            tr('Cách sửa: ', 'Fix: ') + r.fix,
                            style: IdeType.bodySmall.copyWith(
                              color: IdeWb.text2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: WebTuiSpacing.md),
          if (!check.ok)
            Text(
              tr(
                'Còn mục chưa đạt, hãy sửa rồi kiểm tra lại.',
                'Some checks failed: fix them and check again.',
              ),
              key: const Key('ide_to_git_blocked'),
              style: IdeType.bodySmall.copyWith(color: IdeWb.danger),
            ),
          _inlineError(_error),
          const SizedBox(height: WebTuiSpacing.sm),
          Row(
            children: [
              Expanded(
                child: IdeProjectButton(
                  key: const Key('ide_to_git_recheck'),
                  icon: Icons.refresh_rounded,
                  label: tr('Kiểm tra lại', 'Check again'),
                  onPressed: _applying ? null : _load,
                ),
              ),
              const SizedBox(width: WebTuiSpacing.md),
              Expanded(
                child: IdeProjectButton(
                  key: const Key('ide_to_git_apply'),
                  primary: true,
                  icon: Icons.merge_type_rounded,
                  label: tr('Chuyển sang Git', 'Move to Git'),
                  onPressed: check.ok && !_applying ? _apply : null,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return SingleChildScrollView(
      child: Padding(
        padding: _pad(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WebTuiSheetHeader(
              title: tr('Chuyển sang Git', 'Move to Git'),
              subtitle: widget.project.title,
            ),
            body,
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------- Máy đích riêng

Future<void> showIdeMyTargetSheet(BuildContext context, IdeProject project) =>
    showWebTuiSheet<void>(
      context: context,
      builder: (_) => IdeMyTargetSheet(project: project),
    );

class IdeMyTargetSheet extends ConsumerStatefulWidget {
  const IdeMyTargetSheet({required this.project, super.key});

  final IdeProject project;

  @override
  ConsumerState<IdeMyTargetSheet> createState() => _MyTargetState();
}

class _MyTargetState extends ConsumerState<IdeMyTargetSheet> {
  IdeMyTarget? _target;
  Object? _loadError;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _server;
  final _path = TextEditingController();
  bool _auto = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final t = await ref
          .read(ideProjectServiceProvider)
          .myTarget(widget.project.name);
      if (!mounted) return;
      setState(() {
        _target = t;
        _loading = false;
        if (t != null) {
          _path.text = t.path;
          _auto = t.auto;
          _server = t.ref;
        }
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ideProjectSnack(context, done);
      await _load();
    } on Object catch (e) {
      if (mounted) setState(() => _error = ideProjectErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() {
    final server = _server;
    final path = _path.text.trim();
    if (server == null || server.isEmpty || path.isEmpty) {
      setState(
        () => _error = tr(
          'Chọn máy và nhập thư mục trên máy đó.',
          'Pick a server and enter its folder.',
        ),
      );
      return Future.value();
    }
    return _run(
      () => ref.read(ideProjectServiceProvider).call('targets.set', {
        'project': widget.project.name,
        'server': server,
        'path': path,
        'auto': _auto,
      }),
      tr('Đã lưu máy đích', 'Target saved'),
    );
  }

  Future<void> _remove() async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Gỡ máy đích?', 'Remove the target?'),
      message: tr(
        'Dự án sẽ không còn máy để đồng bộ. Cần xác nhận bằng vân tay.',
        'The project will have no server to sync to. Needs fingerprint.',
      ),
      confirmLabel: tr('Gỡ', 'Remove'),
      cancelLabel: tr('Giữ lại', 'Keep'),
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    await _run(
      () => ref.read(ideProjectServiceProvider).call('targets.remove', {
        'project': widget.project.name,
      }),
      tr('Đã gỡ máy đích', 'Target removed'),
    );
  }

  Future<void> _toggleAuto(bool on) {
    return _run(
      () => ref.read(ideProjectServiceProvider).call('targets.auto', {
        'project': widget.project.name,
        'on': on,
      }),
      on
          ? tr('Đã bật tự đồng bộ', 'Auto sync on')
          : tr('Đã tắt tự đồng bộ', 'Auto sync off'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(ideTermTargetsProvider);
    final Widget body;
    if (_loading) {
      body = SizedBox(
        height: 160,
        child: WebTuiLoadingState(
          message: tr('Đang tải máy đích...', 'Loading target...'),
        ),
      );
    } else if (_loadError != null) {
      body = SizedBox(
        height: 240,
        child: ideProjectErrorView(_loadError!, onRetry: _load),
      );
    } else {
      final hosts = servers.valueOrNull?.mySsh ?? const [];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_target == null)
            Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
              child: Text(
                tr('Chưa đặt máy đích.', 'No target set yet.'),
                key: const Key('ide_target_none'),
                style: IdeType.bodyMedium.copyWith(color: IdeWb.text),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
              child: Text(
                '${_target!.ref} · ${_target!.path}'
                '${_target!.last.isEmpty ? '' : '\n${tr('Lần cuối', 'Last')}: ${_target!.last}'}',
                key: const Key('ide_target_current'),
                style: IdeType.bodyMedium.copyWith(color: IdeWb.textStrong),
              ),
            ),
          if (servers.isLoading)
            IdeProgressLine(
              text: tr('Đang tải danh sách máy...', 'Loading servers...'),
            )
          else if (hosts.isEmpty)
            Text(
              tr(
                'Chưa có máy riêng nào để chọn. Hãy thêm máy ở trang quản lý.',
                'No private server to choose yet.',
              ),
              key: const Key('ide_target_no_hosts'),
              style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
            )
          else
            DropdownButtonFormField<String>(
              key: const Key('ide_target_server'),
              initialValue: hosts.any((h) => h.alias == _server)
                  ? _server
                  : null,
              decoration: InputDecoration(labelText: tr('Máy chủ', 'Server')),
              items: [
                for (final h in hosts)
                  DropdownMenuItem(value: h.alias, child: Text(h.label)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _server = v),
            ),
          TextField(
            key: const Key('ide_target_path'),
            controller: _path,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: tr('Thư mục trên máy đó', 'Folder on that server'),
            ),
          ),
          SwitchListTile(
            key: const Key('ide_target_auto'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Tự đồng bộ', 'Auto sync')),
            value: _auto,
            onChanged: _busy
                ? null
                : (v) {
                    setState(() => _auto = v);
                    if (_target != null) unawaited(_toggleAuto(v));
                  },
          ),
          _inlineError(_error),
          const SizedBox(height: WebTuiSpacing.sm),
          Row(
            children: [
              if (_target != null) ...[
                Expanded(
                  child: IdeProjectButton(
                    key: const Key('ide_target_remove'),
                    danger: true,
                    icon: Icons.delete_outline_rounded,
                    label: tr('Gỡ máy đích', 'Remove'),
                    onPressed: _busy ? null : _remove,
                  ),
                ),
                const SizedBox(width: WebTuiSpacing.md),
              ],
              Expanded(
                child: IdeProjectButton(
                  key: const Key('ide_target_save'),
                  primary: true,
                  icon: Icons.save_outlined,
                  label: tr('Lưu', 'Save'),
                  onPressed: _busy ? null : _save,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return SingleChildScrollView(
      child: Padding(
        padding: _pad(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WebTuiSheetHeader(
              title: tr('Máy đích', 'Target server'),
              subtitle: widget.project.title,
            ),
            body,
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------- Xin quyền máy chủ tạm

Future<void> showIdeVpsRequestSheet(BuildContext context, IdeProject project) =>
    showWebTuiSheet<void>(
      context: context,
      builder: (_) => IdeVpsRequestSheet(project: project),
    );

class IdeVpsRequestSheet extends ConsumerStatefulWidget {
  const IdeVpsRequestSheet({required this.project, super.key});

  final IdeProject project;

  @override
  ConsumerState<IdeVpsRequestSheet> createState() => _VpsRequestState();
}

class _VpsRequestState extends ConsumerState<IdeVpsRequestSheet> {
  final _reason = TextEditingController();
  late String _target = widget.project.targets.isEmpty
      ? ''
      : widget.project.targets.first.name;
  int _hours = 1;
  bool _busy = false;
  String? _error;
  List<IdeVpsRequest>? _requests;
  Object? _listError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadList());
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    try {
      final l = await ref.read(ideProjectServiceProvider).vpsRequests();
      if (mounted) {
        setState(() {
          _requests = l;
          _listError = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _listError = e);
    }
  }

  Future<void> _submit() async {
    final bad = ideVpsRequestError(hours: _hours, reason: _reason.text);
    if (_target.isEmpty || bad != null) {
      setState(
        () => _error = bad == 'hours'
            ? tr('Số giờ từ 1 đến 8.', 'Hours must be 1 to 8.')
            : tr(
                'Lý do cần từ 5 đến 300 ký tự.',
                'The reason needs 5 to 300 characters.',
              ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(ideProjectServiceProvider).call('vps.request', {
        'project': widget.project.name,
        'target': _target,
        'hours': _hours,
        'reason': _reason.text.trim(),
      });
      if (!mounted) return;
      ideProjectSnack(context, tr('Đã gửi yêu cầu', 'Request sent'));
      _reason.clear();
      await _loadList();
    } on Object catch (e) {
      if (mounted) setState(() => _error = ideProjectErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(String s) => switch (s) {
    'approved' => tr('Đã duyệt', 'Approved'),
    'rejected' => tr('Từ chối', 'Rejected'),
    _ => tr('Chờ duyệt', 'Pending'),
  };

  @override
  Widget build(BuildContext context) {
    final mine = [
      for (final r in _requests ?? const <IdeVpsRequest>[])
        if (r.project == widget.project.name) r,
    ];
    return SingleChildScrollView(
      child: Padding(
        padding: _pad(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WebTuiSheetHeader(
              title: tr('Xin quyền máy chủ tạm', 'Request temporary access'),
              subtitle: tr(
                'Quản trị duyệt thì bạn vào được máy chủ trong số giờ đã xin.',
                'Once approved you can use the server for the hours requested.',
              ),
            ),
            DropdownButtonFormField<String>(
              key: const Key('ide_vps_target'),
              initialValue: _target.isEmpty ? null : _target,
              decoration: InputDecoration(labelText: tr('Máy chủ', 'Server')),
              items: [
                for (final t in widget.project.targets)
                  DropdownMenuItem(value: t.name, child: Text(t.title)),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _target = v ?? ''),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            Row(
              children: [
                Text(tr('Số giờ', 'Hours')),
                const Spacer(),
                IconButton(
                  key: const Key('ide_vps_hours_minus'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: _hours > 1 && !_busy
                      ? () => setState(() => _hours--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Text('$_hours', key: const Key('ide_vps_hours')),
                IconButton(
                  key: const Key('ide_vps_hours_plus'),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: _hours < 8 && !_busy
                      ? () => setState(() => _hours++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            TextField(
              key: const Key('ide_vps_reason'),
              controller: _reason,
              enabled: !_busy,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: tr('Lý do (5–300 ký tự)', 'Reason (5-300 chars)'),
              ),
            ),
            _inlineError(_error),
            const SizedBox(height: WebTuiSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: IdeProjectButton(
                key: const Key('ide_vps_submit'),
                primary: true,
                icon: Icons.vpn_key_outlined,
                label: tr('Gửi yêu cầu', 'Send request'),
                onPressed: _busy ? null : _submit,
              ),
            ),
            const SizedBox(height: WebTuiSpacing.lg),
            Text(
              tr('Yêu cầu của dự án này', 'Requests for this project'),
              style: IdeType.titleMedium.copyWith(color: IdeWb.textStrong),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
            if (_listError != null)
              Text(
                ideProjectErrorText(_listError!),
                key: const Key('ide_vps_list_error'),
                style: IdeType.bodySmall.copyWith(color: IdeWb.danger),
              )
            else if (_requests == null)
              IdeProgressLine(text: tr('Đang tải...', 'Loading...'))
            else if (mine.isEmpty)
              Text(
                tr('Chưa có yêu cầu nào.', 'No requests yet.'),
                key: const Key('ide_vps_list_empty'),
                style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
              )
            else
              for (final r in mine)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 48,
                  title: Text('${r.target} · ${r.hours} ${tr('giờ', 'h')}'),
                  subtitle: Text(
                    '${r.reason}\n${ideFormatUnix(r.at)}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: WebTuiStatusPill(
                    label: _statusLabel(r.status),
                    color: switch (r.status) {
                      'approved' => IdeWb.ok,
                      'rejected' => IdeWb.danger,
                      _ => IdeWb.warn,
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
