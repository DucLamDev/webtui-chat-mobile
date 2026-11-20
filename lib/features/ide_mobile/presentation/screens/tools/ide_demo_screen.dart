import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_demo_models.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_project.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';
import 'ide_demo_dialogs.dart';
import 'ide_tools_common.dart';

/// Web demo và database của dự án (Phụ lục C1).
class IdeDemoScreen extends StatelessWidget {
  const IdeDemoScreen({this.project, super.key});

  final String? project;

  @override
  Widget build(BuildContext context) {
    return IdeMorePage(
      title: tr('Web & DB', 'Web & DB'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) => _DemoLoader(project: p),
      ),
    );
  }
}

class _DemoLoader extends ConsumerWidget {
  const _DemoLoader({required this.project});

  final IdeProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ideToolsHas(ref, 'demo.status')) return ideToolsUnsupported();
    return IdeLoader<IdeDemoStatus>(
      load: () => ref.read(ideToolsServiceProvider).demoStatus(project.name),
      builder: (context, st, reload) =>
          _DemoView(project: project, status: st, reload: reload),
    );
  }
}

class _DemoView extends ConsumerStatefulWidget {
  const _DemoView({
    required this.project,
    required this.status,
    required this.reload,
  });

  final IdeProject project;
  final IdeDemoStatus status;
  final Future<void> Function() reload;

  @override
  ConsumerState<_DemoView> createState() => _DemoViewState();
}

class _DemoViewState extends ConsumerState<_DemoView> {
  bool _busy = false;

  String get _name => widget.project.name;
  IdeDemoStatus get _st => widget.status;

  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } on Object catch (e) {
      if (mounted) ideToolsError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openJob(String job) async {
    if (!mounted) return;
    await context.push<Object?>('/ide/jobs/$job');
    if (mounted) await widget.reload();
  }

  Future<void> _apply(String op) async {
    final input = await showDemoConfigSheet(
      context,
      status: _st,
      isGit: widget.project.isGit,
      editing: op == 'demo.set',
    );
    if (input == null || !mounted) return;
    await _guard(() async {
      final job = await ref
          .read(ideToolsServiceProvider)
          .demoApply(
            op,
            _name,
            server: _st.my ? null : input.server,
            root: input.root,
            public: input.public,
            branch: widget.project.isGit ? input.branch : null,
          );
      await _openJob(job);
    });
  }

  Future<void> _job(String op) => _guard(() async {
    final job = await ref.read(ideToolsServiceProvider).demoJob(op, _name);
    await _openJob(job);
  });

  Future<void> _disable() async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Tắt web demo?', 'Turn off the web demo?'),
      message: _name,
      confirmLabel: tr('Tắt', 'Turn off'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _guard(() async {
      final msg = await ref
          .read(ideToolsServiceProvider)
          .demoSimple('demo.disable', _name);
      if (!mounted) return;
      ideToolsSnack(
        context,
        msg.isEmpty ? tr('Đã tắt', 'Turned off') : ideVisibleText(msg),
      );
      await widget.reload();
    });
  }

  Future<void> _dbCreate() => _guard(() async {
    final msg = await ref
        .read(ideToolsServiceProvider)
        .demoSimple('demo.db_create', _name);
    if (!mounted) return;
    ideToolsSnack(
      context,
      msg.isEmpty
          ? tr('Đã tạo database', 'Database created')
          : ideVisibleText(msg),
    );
    await widget.reload();
  });

  Future<void> _dbDrop() async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Xoá database?', 'Delete the database?'),
      message: tr(
        'Toàn bộ dữ liệu của $_name sẽ mất, không khôi phục được.',
        'All data of $_name will be lost for good.',
      ),
      confirmLabel: tr('Xoá', 'Delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _guard(() async {
      final msg = await ref
          .read(ideToolsServiceProvider)
          .demoSimple('demo.db_drop', _name);
      if (!mounted) return;
      ideToolsSnack(
        context,
        msg.isEmpty
            ? tr('Đã xoá database', 'Database deleted')
            : ideVisibleText(msg),
      );
      await widget.reload();
    });
  }

  /// Mật khẩu đi thẳng từ lời đáp vào hộp thoại, không qua state của màn này.
  Future<void> _dbShow() => _guard(() async {
    final secret = await ref.read(ideToolsServiceProvider).demoDbShow(_name);
    if (!mounted) return;
    await showDbSecretDialog(context, secret);
  });

  Future<void> _log() => _guard(() async {
    final text = await ref.read(ideToolsServiceProvider).demoLog(_name);
    if (!mounted) return;
    await showDemoLogSheet(context, text);
  });

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final manage = st.canManage;
    bool has(String op) => ideToolsHas(ref, op);
    final enabled = st.enabled;
    final canEnable = manage && !enabled && has('demo.enable') && st.eligible;
    final canSet = manage && enabled && has('demo.set');
    final canDisable = manage && enabled && has('demo.disable');
    final canUpdate = manage && enabled && st.canUpdate && has('demo.update');
    final canSync = manage && enabled && st.my && has('demo.sync');
    final canDbCreate = manage && !st.hasDb && has('demo.db_create');
    final canDbShow = st.hasDb && has('demo.db_show');
    final canDbDrop = manage && st.my && st.hasDb && has('demo.db_drop');
    final canLog = has('demo.log');
    final muted = IdeType.bodySmall.copyWith(color: IdeWb.text2);
    return RefreshIndicator(
      onRefresh: widget.reload,
      child: ListView(
        key: const Key('ide_demo_view'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          WebTuiSpacing.lg,
          WebTuiSpacing.sm,
          WebTuiSpacing.lg,
          WebTuiSpacing.xxl,
        ),
        children: [
          IdeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: WebTuiSpacing.sm,
                  runSpacing: WebTuiSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      tr('Web demo', 'Web demo'),
                      style: IdeType.titleMedium.copyWith(
                        color: IdeWb.textStrong,
                      ),
                    ),
                    IdeTag(
                      enabled ? tr('Đang bật', 'On') : tr('Đang tắt', 'Off'),
                      color: enabled ? IdeWb.ok : IdeWb.text,
                    ),
                    if (enabled && st.public)
                      IdeTag(tr('Công khai', 'Public'), color: IdeWb.warn),
                  ],
                ),
                if (!manage)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                    child: Text(
                      tr(
                        'Chỉ trưởng / phó dự án hoặc quản trị mới bật, sửa, tắt được.',
                        'Only project leads or admins can change this.',
                      ),
                      style: muted,
                    ),
                  ),
                if (st.my && !st.eligible && st.why.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                    child: Text(ideVisibleText(st.why), style: muted),
                  ),
                const SizedBox(height: WebTuiSpacing.xs),
                if (st.url != null) _CopyRow(label: 'URL', value: st.url!),
                if (enabled && st.server.isNotEmpty)
                  ToolInfoRow(tr('Máy chủ web', 'Web server'), st.server),
                if (enabled && st.root.isNotEmpty)
                  ToolInfoRow(
                    tr('Thư mục gốc', 'Root'),
                    ideVisibleText(st.root),
                  ),
                if (enabled && st.branch.isNotEmpty)
                  ToolInfoRow(tr('Nhánh', 'Branch'), ideVisibleText(st.branch)),
                if (enabled && st.sha.isNotEmpty)
                  ToolInfoRow(
                    tr('Bản mã', 'Revision'),
                    ideVisibleText(
                      st.sha.length > 10 ? st.sha.substring(0, 10) : st.sha,
                    ),
                  ),
                if (st.updatedAt != null)
                  ToolInfoRow(
                    tr('Cập nhật', 'Updated'),
                    ideFormatDateTime(st.updatedAt!),
                  ),
                if (st.phpVersion.isNotEmpty)
                  ToolInfoRow('PHP', ideVisibleText(st.phpVersion)),
                if (st.syncError.isNotEmpty)
                  Text(
                    '! ${ideVisibleText(st.syncError)}',
                    style: IdeType.bodySmall.copyWith(color: IdeWb.danger),
                  ),
                if (st.my && st.limitMax != null && st.limitUsed != null)
                  ToolInfoRow(
                    tr('Đã dùng', 'Used'),
                    '${st.limitUsed}/${st.limitMax}',
                  ),
                if (canEnable || canSet || canDisable || canUpdate || canSync)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                    child: Wrap(
                      spacing: WebTuiSpacing.sm,
                      runSpacing: WebTuiSpacing.xs,
                      children: [
                        if (canEnable)
                          FilledButton(
                            key: const Key('ide_demo_enable'),
                            style: ideToolsFilledBtn(),
                            onPressed: _busy
                                ? null
                                : () => _apply('demo.enable'),
                            child: Text(tr('Bật web demo', 'Turn on')),
                          ),
                        if (canSet)
                          OutlinedButton(
                            key: const Key('ide_demo_set'),
                            style: ideToolsBtn(),
                            onPressed: _busy ? null : () => _apply('demo.set'),
                            child: Text(tr('Sửa cấu hình', 'Edit settings')),
                          ),
                        if (canUpdate)
                          OutlinedButton(
                            key: const Key('ide_demo_update'),
                            style: ideToolsBtn(),
                            onPressed: _busy ? null : () => _job('demo.update'),
                            child: Text(tr('Cập nhật mã', 'Update code')),
                          ),
                        if (canSync)
                          OutlinedButton(
                            key: const Key('ide_demo_sync'),
                            style: ideToolsBtn(),
                            onPressed: _busy ? null : () => _job('demo.sync'),
                            child: Text(tr('Đồng bộ', 'Sync')),
                          ),
                        if (canDisable)
                          OutlinedButton(
                            key: const Key('ide_demo_disable'),
                            style: ideToolsBtn(color: IdeWb.danger),
                            onPressed: _busy ? null : _disable,
                            child: Text(tr('Tắt', 'Turn off')),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          IdeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: WebTuiSpacing.sm,
                  runSpacing: WebTuiSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      tr('Database', 'Database'),
                      style: IdeType.titleMedium.copyWith(
                        color: IdeWb.textStrong,
                      ),
                    ),
                    IdeTag(
                      st.hasDb ? tr('Đã có', 'Exists') : tr('Chưa có', 'None'),
                      color: st.hasDb ? IdeWb.ok : IdeWb.text,
                    ),
                  ],
                ),
                if (st.dbName.isNotEmpty)
                  ToolInfoRow(tr('Tên', 'Name'), ideVisibleText(st.dbName)),
                if (st.pmaUrl != null)
                  _CopyRow(label: 'phpMyAdmin', value: st.pmaUrl!),
                if (canDbCreate || canDbShow || canDbDrop)
                  Padding(
                    padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                    child: Wrap(
                      spacing: WebTuiSpacing.sm,
                      runSpacing: WebTuiSpacing.xs,
                      children: [
                        if (canDbCreate)
                          FilledButton(
                            key: const Key('ide_demo_db_create'),
                            style: ideToolsFilledBtn(),
                            onPressed: _busy ? null : _dbCreate,
                            child: Text(tr('Tạo database', 'Create database')),
                          ),
                        if (canDbShow)
                          OutlinedButton(
                            key: const Key('ide_demo_db_show'),
                            style: ideToolsBtn(),
                            onPressed: _busy ? null : _dbShow,
                            child: Text(tr('Xem mật khẩu', 'Show password')),
                          ),
                        if (canDbDrop)
                          OutlinedButton(
                            key: const Key('ide_demo_db_drop'),
                            style: ideToolsBtn(color: IdeWb.danger),
                            onPressed: _busy ? null : _dbDrop,
                            child: Text(tr('Xoá database', 'Delete database')),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (canLog)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('ide_demo_log'),
                  style: ideToolsBtn(),
                  onPressed: _busy ? null : _log,
                  icon: const Icon(Icons.notes_rounded, size: 18),
                  label: Text(tr('Xem nhật ký', 'View log')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: ToolInfoRow(label, value)),
      IconButton(
        tooltip: tr('Chép', 'Copy'),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: const Icon(Icons.copy_rounded, size: 18),
        onPressed: () => ideToolsCopy(context, value),
      ),
    ],
  );
}
