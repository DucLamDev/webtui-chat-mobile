import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';

/// Dự án trong `projects.list`.
class IdeProjectItem {
  const IdeProjectItem({
    required this.name,
    required this.root,
    this.git = false,
  });
  final String name;
  final String root;
  final bool git;
}

class IdeWorktreeItem {
  const IdeWorktreeItem({
    required this.name,
    required this.branch,
    required this.kind,
    this.dirty = false,
  });
  final String name;
  final String branch;
  final String kind;
  final bool dirty;
}

List<IdeProjectItem> parseIdeProjects(Object? data) {
  final items = data is Map ? data['items'] : null;
  if (items is! List) return const [];
  return [
    for (final e in items)
      if (e is Map && e['root'] is String && (e['root'] as String).isNotEmpty)
        IdeProjectItem(
          name: e['name'] is String && (e['name'] as String).isNotEmpty
              ? e['name'] as String
              : e['root'] as String,
          root: e['root'] as String,
          git: e['git'] == true,
        ),
  ];
}

List<IdeWorktreeItem> parseIdeWorktrees(Object? data) {
  final items = data is Map ? data['items'] : null;
  if (items is! List) return const [];
  return [
    for (final e in items)
      if (e is Map && e['name'] is String)
        IdeWorktreeItem(
          name: e['name'] as String,
          branch: e['branch'] is String ? e['branch'] as String : '',
          kind: e['kind'] is String ? e['kind'] as String : '',
          dirty: e['dirty'] == true,
        ),
  ];
}

/// Đường dẫn mở phiên mới (query đã mã hoá). [worktree]: tên có sẵn,
/// `new` = tạo mới, null = làm ngay trên thư mục dự án.
String ideNewSessionLocation({
  required String kind,
  required String root,
  String? worktree,
}) => Uri(
  path: '/ide/ai/new',
  queryParameters: {
    'kind': kind,
    'root': root,
    if (worktree != null && worktree.isNotEmpty) 'worktree': worktree,
  },
).toString();

Future<void> showIdeNewSessionSheet(BuildContext context) =>
    showWebTuiSheet<void>(
      context: context,
      builder: (_) => const IdeNewSessionSheet(),
    );

class IdeNewSessionSheet extends ConsumerStatefulWidget {
  const IdeNewSessionSheet({super.key});

  @override
  ConsumerState<IdeNewSessionSheet> createState() => _State();
}

class _State extends ConsumerState<IdeNewSessionSheet> {
  List<IdeProjectItem>? _projects;
  List<IdeWorktreeItem> _worktrees = const [];
  bool _loadingTrees = false;
  Object? _error;
  IdeProjectItem? _project;
  String _kind = 'claude';
  // null = thư mục dự án, 'new' = tạo mới, còn lại = tên worktree có sẵn.
  String? _worktree;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProjects());
  }

  Future<void> _loadProjects() async {
    setState(() => _error = null);
    try {
      final data = await ref
          .read(ideRpcClientProvider)
          .call('projects.list', const {});
      if (!mounted) return;
      final list = parseIdeProjects(data);
      setState(() {
        _projects = list;
        _project = list.isEmpty ? null : list.first;
      });
      await _loadTrees();
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadTrees() async {
    final p = _project;
    if (p == null) return;
    setState(() {
      _loadingTrees = true;
      _worktree = null;
      _worktrees = const [];
    });
    try {
      final data = await ref.read(ideRpcClientProvider).call('ai.worktrees', {
        'root': p.root,
      });
      if (mounted && _project == p) {
        setState(() => _worktrees = parseIdeWorktrees(data));
      }
    } on Object {
      // Không lấy được worktree: vẫn cho mở trên thư mục dự án / tạo mới.
    } finally {
      if (mounted) setState(() => _loadingTrees = false);
    }
  }

  void _go() {
    final p = _project;
    if (p == null) return;
    final loc = ideNewSessionLocation(
      kind: _kind,
      root: p.root,
      worktree: _worktree,
    );
    Navigator.of(context).pop();
    unawaited(GoRouter.of(context).push(loc));
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    final Widget body;
    if (_error != null) {
      body = WebTuiErrorState(
        title: tr('Không tải được dự án', 'Could not load projects'),
        message: tr('Hãy thử lại.', 'Please try again.'),
        onRetry: _loadProjects,
      );
    } else if (projects == null) {
      body = WebTuiLoadingState(
        message: tr('Đang tải dự án...', 'Loading projects...'),
      );
    } else if (projects.isEmpty) {
      body = WebTuiEmptyState(
        title: tr('Chưa có dự án', 'No projects'),
        message: tr('IDE chưa mở dự án nào.', 'The IDE has no projects yet.'),
        icon: Icons.folder_off_outlined,
      );
    } else {
      body = _form(projects);
    }
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WebTuiSheetHeader(title: tr('Phiên AI mới', 'New AI session')),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                0,
                WebTuiSpacing.lg,
                WebTuiSpacing.lg,
              ),
              child: body,
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(List<IdeProjectItem> projects) {
    final trees = _worktrees
        .where((w) => w.kind.isEmpty || w.kind == _kind)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(tr('Dự án', 'Project')),
        DropdownButtonFormField<IdeProjectItem>(
          key: const Key('ide_new_project'),
          initialValue: _project,
          isExpanded: true,
          items: [
            for (final p in projects)
              DropdownMenuItem(
                value: p,
                child: Text(p.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (p) {
            setState(() => _project = p);
            unawaited(_loadTrees());
          },
        ),
        const SizedBox(height: WebTuiSpacing.md),
        _label(tr('Trợ lý', 'Assistant')),
        SegmentedButton<String>(
          key: const Key('ide_new_kind'),
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 44)),
          ),
          segments: const [
            ButtonSegment(value: 'claude', label: Text('Claude')),
            ButtonSegment(value: 'codex', label: Text('Codex')),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() {
            _kind = s.first;
            _worktree = null;
          }),
        ),
        const SizedBox(height: WebTuiSpacing.md),
        _label(tr('Thư mục làm việc', 'Working folder')),
        RadioGroup<String?>(
          groupValue: _worktree,
          onChanged: (v) => setState(() => _worktree = v),
          child: Column(
            children: [
              _radio(null, tr('Thư mục dự án', 'Project folder')),
              for (final w in trees)
                _radio(
                  w.name,
                  w.name,
                  sub: [
                    if (w.branch.isNotEmpty) w.branch,
                    if (w.dirty) tr('đang sửa dở', 'uncommitted'),
                  ].join(' · '),
                ),
              _radio('new', tr('Tạo worktree mới', 'Create a new worktree')),
            ],
          ),
        ),
        if (_loadingTrees) const LinearProgressIndicator(),
        const SizedBox(height: WebTuiSpacing.md),
        FilledButton(
          key: const Key('ide_new_start'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _project == null ? null : _go,
          child: Text(tr('Bắt đầu', 'Start')),
        ),
      ],
    );
  }

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
    child: Text(
      s,
      style: WebTuiTypography.labelSmall.copyWith(
        color: WebTuiColors.textSecondary,
      ),
    ),
  );

  Widget _radio(String? value, String title, {String sub = ''}) =>
      RadioListTile<String?>(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        title: Text(title, overflow: TextOverflow.ellipsis),
        subtitle: sub.isEmpty
            ? null
            : Text(sub, overflow: TextOverflow.ellipsis),
      );
}
