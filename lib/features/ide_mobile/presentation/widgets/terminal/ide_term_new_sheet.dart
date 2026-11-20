import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_term.dart';
import '../../controllers/ide_controllers.dart';
import '../../screens/terminal/ide_terminal_tab.dart';
import '../ai/ide_new_session_sheet.dart';
import '../ide_wb.dart';

Future<void> showIdeTermNewSheet(BuildContext context, WidgetRef ref) {
  // Tab có thể bị đóng khi bảng còn mở: mở màn bằng ref của tab.
  return showWebTuiSheet<void>(
    context: context,
    builder: (sheetContext) => IdeTermNewSheet(
      onStart: (target) {
        Navigator.of(sheetContext).pop();
        unawaited(openIdeTerminal(context, ref, target));
      },
    ),
  );
}

/// Bảng "Terminal mới": dự án + kiểu (Shell / Claude / Codex / SSH).
class IdeTermNewSheet extends ConsumerStatefulWidget {
  const IdeTermNewSheet({required this.onStart, super.key});

  final ValueChanged<IdeTermOpenTarget> onStart;

  @override
  ConsumerState<IdeTermNewSheet> createState() => _State();
}

class _State extends ConsumerState<IdeTermNewSheet> {
  List<IdeProjectItem>? _projects;
  IdeTermTargets _targets = const IdeTermTargets();
  Object? _error;
  IdeProjectItem? _project;
  IdeTermKind _kind = IdeTermKind.shell;
  String? _alias;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rpc = ref.read(ideRpcClientProvider);
      final data = await rpc.call('projects.list', const {});
      final list = parseIdeProjects(data);
      var targets = const IdeTermTargets();
      final ready = ref.read(ideLinkStatusProvider).valueOrNull?.ready;
      if (ready == null || ready.hasOp('term.targets')) {
        try {
          targets = IdeTermTargets.parse(
            await rpc.call('term.targets', const {}),
          );
        } on Object {
          // Không lấy được máy SSH: vẫn mở Shell / Claude / Codex.
        }
      }
      if (!mounted) return;
      setState(() {
        _projects = list;
        _project = list.isEmpty ? null : list.first;
        _targets = targets;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<IdeTermHost> get _hosts => switch (_kind) {
    IdeTermKind.ssh => _targets.ssh,
    IdeTermKind.mySsh => _targets.mySsh,
    _ => const [],
  };

  bool get _needsHost => _kind == IdeTermKind.ssh || _kind == IdeTermKind.mySsh;

  bool get _canStart =>
      _project != null &&
      (!_needsHost || (_alias != null && _alias!.isNotEmpty));

  void _go() {
    final p = _project;
    if (p == null || !_canStart) return;
    widget.onStart(
      IdeTermOpenTarget.create(
        root: p.root,
        cmd: ideTermCmd(_kind, _alias ?? ''),
      ),
    );
  }

  void _pickKind(IdeTermKind kind) {
    setState(() {
      _kind = kind;
      final hosts = _hosts;
      _alias = hosts.isEmpty ? null : hosts.first.alias;
    });
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    final Widget body;
    if (_error != null) {
      body = WebTuiErrorState(
        title: tr('Không tải được dự án', 'Could not load projects'),
        message: tr('Hãy thử lại.', 'Please try again.'),
        onRetry: _load,
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
            WebTuiSheetHeader(title: tr('Terminal mới', 'New terminal')),
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
    final kinds = <(IdeTermKind, String)>[
      (IdeTermKind.shell, 'Shell'),
      (IdeTermKind.claude, 'Claude'),
      (IdeTermKind.codex, 'Codex'),
      if (_targets.ssh.isNotEmpty)
        (IdeTermKind.ssh, tr('SSH máy được cấp', 'SSH granted host')),
      if (_targets.mySsh.isNotEmpty)
        (IdeTermKind.mySsh, tr('SSH máy của tôi', 'SSH my host')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(tr('Dự án', 'Project')),
        DropdownButtonFormField<IdeProjectItem>(
          key: const Key('term_new_project'),
          initialValue: _project,
          isExpanded: true,
          items: [
            for (final p in projects)
              DropdownMenuItem(
                value: p,
                child: Text(p.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (p) => setState(() => _project = p),
        ),
        const SizedBox(height: WebTuiSpacing.md),
        _label(tr('Kiểu', 'Type')),
        RadioGroup<IdeTermKind>(
          groupValue: _kind,
          onChanged: (k) {
            if (k != null) _pickKind(k);
          },
          child: Column(
            key: const Key('term_new_kind'),
            children: [
              for (final (kind, label) in kinds)
                RadioListTile<IdeTermKind>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: kind,
                  title: Text(label),
                ),
            ],
          ),
        ),
        if (_needsHost) ...[
          const SizedBox(height: WebTuiSpacing.sm),
          _label(tr('Máy', 'Host')),
          DropdownButtonFormField<String>(
            key: const Key('term_new_host'),
            initialValue: _alias,
            isExpanded: true,
            items: [
              for (final h in _hosts)
                DropdownMenuItem(
                  value: h.alias,
                  child: Text(h.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _alias = v),
          ),
        ],
        const SizedBox(height: WebTuiSpacing.lg),
        FilledButton(
          key: const Key('term_new_start'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _canStart ? _go : null,
          child: Text(tr('Mở terminal', 'Open terminal')),
        ),
      ],
    );
  }

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.only(bottom: WebTuiSpacing.xs),
    child: Text(
      s,
      style: WebTuiTypography.labelSmall.copyWith(color: IdeWb.text),
    ),
  );
}
