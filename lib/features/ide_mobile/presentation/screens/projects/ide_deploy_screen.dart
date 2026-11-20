import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_deploy.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_project.dart';
import '../../controllers/ide_controllers.dart';
import '../../controllers/ide_project_controllers.dart';
import '../../controllers/ide_project_ops_controllers.dart';
import '../../widgets/ide_step_sheet.dart';
import '../../widgets/ide_wb.dart';
import '../../widgets/projects/ide_preview_view.dart';
import '../../widgets/projects/ide_project_ui.dart';
import 'ide_deploy_history_sheet.dart';

enum _PreviewPhase { idle, running, done, failed }

/// Triển khai một dự án: chọn máy đích, xem trước, triển khai, kéo về, lịch sử.
class IdeDeployScreen extends ConsumerStatefulWidget {
  const IdeDeployScreen({required this.project, this.target, super.key});

  final String project;
  final String? target;

  @override
  ConsumerState<IdeDeployScreen> createState() => _DeployState();
}

class _DeployState extends ConsumerState<IdeDeployScreen> {
  late final IdeStepPresenterLease _lease;
  Timer? _expiry;
  String _target = '';
  _PreviewPhase _phase = _PreviewPhase.idle;
  String _liveLog = '';
  String _failure = '';
  String _failedJob = '';
  IdePreviewRecord? _record;
  bool _running = false;
  bool _pulling = false;
  IdeRunResult? _runResult;
  String _runJob = '';
  String _runFailure = '';

  bool _has(String op) =>
      ref.read(ideLinkStatusProvider).valueOrNull?.ready?.hasOp(op) ?? false;

  @override
  void initState() {
    super.initState();
    _target = widget.target ?? '';
    _lease = IdeStepPresenterLease(ref.read(ideStepPresenterProvider.notifier));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lease.acquire(context, () => mounted);
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _lease.release();
    super.dispose();
  }

  IdeProject? _find(List<IdeProject> list) {
    for (final p in list) {
      if (p.name == widget.project) return p;
    }
    return null;
  }

  String _effectiveTarget(IdeProject p) {
    if (p.my) return '';
    if (p.targets.any((t) => t.name == _target)) return _target;
    return p.targets.isEmpty ? '' : p.targets.first.name;
  }

  Future<void> _preview(IdeProject p) async {
    final ops = IdeDeployOps.of(p);
    final target = _effectiveTarget(p);
    final svc = ref.read(ideProjectServiceProvider);
    setState(() {
      _phase = _PreviewPhase.running;
      _record = null;
      _liveLog = '';
      _failure = '';
      _failedJob = '';
      _runResult = null;
      _runFailure = '';
    });
    String? job;
    try {
      job = await svc.startJob(ops.preview, {
        'project': p.name,
        if (!ops.isMy && target.isNotEmpty) 'target': target,
      });
      final out = await svc.waitJob(
        job,
        poll: ref.read(ideProjectPollIntervalProvider),
        isCancelled: () => !mounted,
        onLog: (l) {
          if (mounted) setState(() => _liveLog = l);
        },
      );
      if (!mounted) return;
      final parsed = out.ok ? IdeDeployPreview.tryParse(out.result) : null;
      if (parsed == null) {
        setState(() {
          _phase = _PreviewPhase.failed;
          _failedJob = job!;
          _failure = out.ok
              ? tr(
                  'IDE trả bản xem trước không đọc được.',
                  'The IDE returned an unreadable preview.',
                )
              : _lastLines(out.log, out.result);
        });
        return;
      }
      final record = IdePreviewRecord(
        jobId: job,
        project: p.name,
        target: target,
        at: ref.read(ideProjectNowProvider)(),
        preview: parsed,
      );
      setState(() {
        _record = record;
        _phase = _PreviewPhase.done;
      });
      _armExpiry(record);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _PreviewPhase.failed;
        _failedJob = job ?? '';
        _failure = ideProjectErrorText(e);
      });
    }
  }

  String _lastLines(String log, Object? result) {
    if (result is Map && result['message'] is String) {
      final m = result['message'] as String;
      if (m.isNotEmpty) return m;
    }
    final cut = log.length > 4000 ? log.substring(log.length - 4000) : log;
    final lines = cut.trim().split('\n');
    final tail = lines.length > 6 ? lines.sublist(lines.length - 6) : lines;
    final text = tail.join('\n').trim();
    return text.isEmpty
        ? tr(
            'Xem trước chưa xong, hãy xem log.',
            'Preview failed, see the log.',
          )
        : text;
  }

  void _armExpiry(IdePreviewRecord r) {
    _expiry?.cancel();
    final left = r.at
        .add(ideDeployPreviewMaxAge)
        .difference(ref.read(ideProjectNowProvider)());
    _expiry = Timer(left.isNegative ? Duration.zero : left, () {
      if (mounted) setState(() {});
    });
  }

  IdeDeployBlock _block(IdeProject p) => ideDeployBlock(
    _record,
    project: p.name,
    target: _effectiveTarget(p),
    now: ref.read(ideProjectNowProvider)(),
  );

  Future<void> _deploy(IdeProject p) async {
    final record = _record;
    if (record == null || _block(p) != IdeDeployBlock.none || _running) return;
    var allowMany = false;
    if (record.preview.deleteMany) {
      final n = record.preview.counts['D'] ?? 0;
      final more = record.preview.truncated;
      final ok = await showWebTuiConfirmDialog(
        context,
        title: tr('Xoá nhiều tệp trên máy chủ?', 'Delete many files?'),
        message: tr(
          more
              ? 'Lần triển khai này xoá ít nhất $n tệp trên máy chủ (danh sách chưa hiện hết, hãy xem log đầy đủ). Bạn đã xem kỹ và chắc chắn muốn tiếp tục?'
              : 'Lần triển khai này xoá $n tệp trên máy chủ. Bạn đã xem kỹ danh sách và chắc chắn muốn tiếp tục?',
          more
              ? 'This deploy deletes at least $n files on the server (list incomplete, check the full log). Have you reviewed it and want to continue?'
              : 'This deploy deletes $n files on the server. Have you reviewed the list and want to continue?',
        ),
        confirmLabel: tr('Vẫn triển khai', 'Deploy anyway'),
        cancelLabel: tr('Dừng lại', 'Stop'),
        destructive: true,
        icon: Icons.delete_forever_rounded,
      );
      if (!ok || !mounted) return;
      allowMany = true;
    }
    final ops = IdeDeployOps.of(p);
    final svc = ref.read(ideProjectServiceProvider);
    setState(() {
      _running = true;
      _runResult = null;
      _runFailure = '';
      _runJob = '';
    });
    String? job;
    try {
      job = await svc.startJob(ops.run, {
        'project': p.name,
        if (!ops.isMy && record.target.isNotEmpty) 'target': record.target,
        'preview': record.jobId,
        if (allowMany) 'allow_many_delete': true,
      });
      // Mỗi bản xem trước chỉ dùng một lần.
      if (mounted) setState(() => _record = record.markUsed());
      _runJob = job;
      final out = await svc.waitJob(
        job,
        poll: ref.read(ideProjectPollIntervalProvider),
        isCancelled: () => !mounted,
      );
      if (!mounted) return;
      final r = IdeRunResult.parse(out.result);
      setState(() {
        _running = false;
        _runResult = out.ok && (out.result == null || r.ok)
            ? IdeRunResult(
                ok: true,
                message: r.message.isNotEmpty
                    ? r.message
                    : tr('Đã triển khai xong.', 'Deployed.'),
              )
            : null;
        _runFailure = _runResult == null
            ? (r.message.isNotEmpty ? r.message : _lastLines(out.log, null))
            : '';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _runFailure = ideProjectErrorText(e);
        // Bản xem trước cũ / đã dùng: bắt xem trước lại.
        if (e is IdeConflict) _record = record.markUsed();
      });
      if (e is IdeCancelled) setState(() => _runFailure = '');
      ideProjectSnack(context, ideProjectErrorText(e));
    }
  }

  Future<void> _pull(IdeProject p) async {
    if (_pulling) return;
    setState(() => _pulling = true);
    try {
      await _pullInner(p);
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  Future<void> _pullInner(IdeProject p) async {
    final ops = IdeDeployOps.of(p);
    final choice = await showWebTuiSheet<bool>(
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          0,
          0,
          0,
          WebTuiSpacing.lg + MediaQuery.viewPaddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WebTuiSheetHeader(
              title: tr('Kéo về', 'Pull'),
              subtitle: tr(
                'Lấy các tệp đang chạy trên máy chủ về Dev VPS.',
                'Bring the files from the server back to the Dev VPS.',
              ),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_pull_all'),
              icon: Icons.download_rounded,
              title: tr('Kéo tất cả', 'Pull everything'),
              onTap: () => Navigator.of(ctx).pop(false),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_pull_newer'),
              icon: Icons.update_rounded,
              title: tr('Chỉ tệp máy chủ mới hơn', 'Only newer server files'),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    // Số tệp đang sửa dở trên Dev VPS (nếu hỏi được) để người dùng cân nhắc.
    var dirty = 0;
    try {
      dirty = (await ref.read(ideProjectServiceProvider).info(p.name)).dirty;
    } on Object {
      dirty = 0;
    }
    if (!mounted) return;
    final dirtyVi = dirty > 0
        ? ' Hiện có $dirty tệp đang thay đổi trên Dev VPS.'
        : '';
    final dirtyEn = dirty > 0
        ? ' $dirty files are currently changed on the Dev VPS.'
        : '';
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Kéo về từ máy chủ?', 'Pull from the server?'),
      message: tr(
        'Các tệp trên Dev VPS sẽ bị thay bằng bản trên máy chủ, có thể làm mất phần người khác đang sửa dở.$dirtyVi',
        'Files on the Dev VPS will be replaced by the server copies; work in progress by others may be lost.$dirtyEn',
      ),
      confirmLabel: choice
          ? tr('Kéo tệp mới hơn', 'Pull newer files')
          : tr('Kéo tất cả', 'Pull everything'),
      cancelLabel: tr('Huỷ', 'Cancel'),
      destructive: true,
      icon: Icons.download_rounded,
    );
    if (!ok || !mounted) return;
    final target = _effectiveTarget(p);
    final job = await ideProjectGuard(
      context,
      () => ref.read(ideProjectServiceProvider).startJob(ops.pull, {
        'project': p.name,
        if (!ops.isMy && target.isNotEmpty) 'target': target,
        if (choice) 'newer': true,
      }),
    );
    if (job != null && mounted) unawaited(context.push('/ide/jobs/$job'));
  }

  Future<void> _history(IdeProject p) async {
    final job = await showIdeDeployHistorySheet(
      context,
      project: p,
      target: _effectiveTarget(p),
    );
    if (job != null && mounted) unawaited(context.push('/ide/jobs/$job'));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      ideLinkStatusProvider,
    ); // giữ nguồn trạng thái sống, đổi op thì dựng lại
    final projects = ref.watch(ideProjectsProvider);
    final p = projects.valueOrNull == null ? null : _find(projects.value!);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          p == null
              ? tr('Triển khai', 'Deploy')
              : '${tr('Triển khai', 'Deploy')} · ${p.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (p != null && _has(IdeDeployOps.of(p).history))
            IconButton(
              key: const Key('ide_deploy_history'),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: tr('Lịch sử', 'History'),
              onPressed: () => _history(p),
              icon: const Icon(Icons.history_rounded),
            ),
        ],
      ),
      body: projects.when(
        loading: () => WebTuiLoadingState(
          message: tr('Đang tải dự án...', 'Loading project...'),
        ),
        error: (e, _) => ideProjectErrorView(
          e,
          onRetry: () => ref.invalidate(ideProjectsProvider),
        ),
        data: (_) => p == null
            ? WebTuiEmptyState(
                key: const Key('ide_deploy_no_project'),
                title: tr('Không tìm thấy dự án', 'Project not found'),
                message: tr(
                  'Dự án này không còn trong danh sách của bạn.',
                  'This project is no longer in your list.',
                ),
                icon: Icons.search_off_rounded,
              )
            : _content(p),
      ),
    );
  }

  Widget _content(IdeProject p) {
    final ops = IdeDeployOps.of(p);
    if (!_has(ops.preview)) {
      return WebTuiEmptyState(
        key: const Key('ide_deploy_unsupported'),
        title: tr('IDE chưa hỗ trợ triển khai', 'Deploy is not supported'),
        message: tr(
          'Bản IDE trên máy tính chưa có chức năng này. Hãy cập nhật IDE.',
          'The IDE on your computer lacks this. Please update it.',
        ),
        icon: Icons.upgrade_rounded,
      );
    }
    final target = _effectiveTarget(p);
    final block = _block(p);
    final canPull =
        _has(ops.pull) && (ops.isMy || p.kind == IdeProjectKind.vps);
    final running = _phase == _PreviewPhase.running;
    return ListView(
      padding: const EdgeInsets.only(top: WebTuiSpacing.md, bottom: 96),
      children: [
        if (p.targets.length > 1 && !ops.isMy)
          IdeProjectCard(
            title: tr('Máy đích', 'Target'),
            child: Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.sm,
              children: [
                for (final t in p.targets)
                  ChoiceChip(
                    key: Key('ide_deploy_target_${t.name}'),
                    label: Text(t.title),
                    selected: t.name == target,
                    onSelected: running || _running
                        ? null
                        : (_) => setState(() => _target = t.name),
                  ),
              ],
            ),
          )
        else if (p.targets.length == 1 && !ops.isMy)
          IdeProjectCard(
            child: Text(
              '${tr('Máy đích', 'Target')}: ${p.targets.first.title}',
              key: const Key('ide_deploy_target_single'),
              style: IdeType.bodyMedium.copyWith(color: IdeWb.textStrong),
            ),
          ),
        IdeProjectCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: WebTuiSpacing.sm,
                runSpacing: WebTuiSpacing.sm,
                children: [
                  IdeProjectButton(
                    key: const Key('ide_deploy_preview'),
                    icon: Icons.visibility_outlined,
                    label: tr('Xem trước', 'Preview'),
                    onPressed: running || _running ? null : () => _preview(p),
                  ),
                  IdeProjectButton(
                    key: const Key('ide_deploy_run'),
                    primary: true,
                    icon: Icons.rocket_launch_outlined,
                    label: ops.sync
                        ? tr('Đồng bộ', 'Sync')
                        : tr('Triển khai', 'Deploy'),
                    onPressed:
                        block == IdeDeployBlock.none && !running && !_running
                        ? () => _deploy(p)
                        : null,
                  ),
                  if (canPull)
                    IdeProjectButton(
                      key: const Key('ide_deploy_pull'),
                      icon: Icons.download_rounded,
                      label: tr('Kéo về', 'Pull'),
                      onPressed: running || _running || _pulling
                          ? null
                          : () => _pull(p),
                    ),
                ],
              ),
              if (block != IdeDeployBlock.none && !running)
                Padding(
                  padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                  child: Text(
                    ideDeployBlockText(block) ?? '',
                    key: const Key('ide_deploy_block'),
                    style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
                  ),
                ),
            ],
          ),
        ),
        if (_running || _runResult != null || _runFailure.isNotEmpty)
          IdeProjectCard(
            title: tr('Kết quả triển khai', 'Deploy result'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_running)
                  IdeProgressLine(
                    text: tr('Đang triển khai...', 'Deploying...'),
                  )
                else if (_runResult != null)
                  Text(
                    _runResult!.message,
                    key: const Key('ide_deploy_ok'),
                    style: IdeType.bodyMedium.copyWith(color: IdeWb.ok),
                  )
                else
                  Text(
                    _runFailure,
                    key: const Key('ide_deploy_failed'),
                    style: IdeType.bodyMedium.copyWith(color: IdeWb.danger),
                  ),
                if (_runJob.isNotEmpty)
                  TextButton(
                    key: const Key('ide_deploy_run_job'),
                    onPressed: () => context.push('/ide/jobs/$_runJob'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(tr('Xem log', 'View log')),
                  ),
              ],
            ),
          ),
        if (running)
          IdeProjectCard(
            title: tr('Đang xem trước', 'Previewing'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IdeProgressLine(
                  text: tr(
                    'Đang so sánh với máy chủ...',
                    'Comparing with the server...',
                  ),
                ),
                if (_liveLog.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                    child: Text(
                      (_liveLog.length > 2000
                              ? _liveLog.substring(_liveLog.length - 2000)
                              : _liveLog)
                          .trim()
                          .split('\n')
                          .reversed
                          .take(4)
                          .toList()
                          .reversed
                          .join('\n'),
                      style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
                    ),
                  ),
              ],
            ),
          ),
        if (_phase == _PreviewPhase.failed)
          IdeProjectCard(
            title: tr('Xem trước chưa được', 'Preview failed'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _failure,
                  key: const Key('ide_preview_failed'),
                  style: IdeType.bodyMedium.copyWith(color: IdeWb.danger),
                ),
                Row(
                  children: [
                    TextButton(
                      key: const Key('ide_preview_retry'),
                      onPressed: () => _preview(p),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      child: Text(tr('Thử lại', 'Retry')),
                    ),
                    if (_failedJob.isNotEmpty)
                      TextButton(
                        onPressed: () => context.push('/ide/jobs/$_failedJob'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                        ),
                        child: Text(tr('Xem log', 'View log')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (_phase == _PreviewPhase.done && _record != null)
          IdeProjectCard(
            title: tr('Bản xem trước', 'Preview'),
            child: IdePreviewView(preview: _record!.preview),
          ),
        if (_phase == _PreviewPhase.idle)
          Padding(
            padding: const EdgeInsets.all(WebTuiSpacing.xl),
            child: Text(
              tr(
                'Bấm "Xem trước" để biết những tệp nào sẽ đổi trên máy chủ, rồi mới triển khai.',
                'Tap "Preview" to see which files change on the server first.',
              ),
              key: const Key('ide_deploy_idle'),
              textAlign: TextAlign.center,
              style: IdeType.bodyMedium.copyWith(color: IdeWb.text),
            ),
          ),
      ],
    );
  }
}
