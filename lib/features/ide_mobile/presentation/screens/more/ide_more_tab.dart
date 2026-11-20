import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_project.dart';
import '../../../domain/ide_ready.dart';
import '../../controllers/ide_controllers.dart';
import '../../controllers/ide_project_controllers.dart';
import 'ide_more_common.dart';

class _Entry {
  const _Entry(this.key, this.op, this.icon, this.path, {this.project = false});

  final String key;

  /// `op` phải có trong `ready.ops` thì mục mới hiện.
  final String op;
  final IconData icon;
  final String path;

  /// Mục theo dự án: gửi kèm `?project=`.
  final bool project;

  String get title => switch (key) {
    'tasks' => tr('Việc cần làm', 'Tasks'),
    'ailog' => tr('Nhật ký AI', 'AI log'),
    'oplog' => tr('Nhật ký thao tác', 'Activity log'),
    'notes' => tr('Ghi chú dự án', 'Project notes'),
    'report' => tr('Báo cáo', 'Report'),
    'kientruc' => tr('Kiến trúc', 'Architecture'),
    _ => tr('Changelog nền tảng', 'Platform changelog'),
  };
}

/// Các mục của giai đoạn này; mục giai đoạn sau (Skill, AI Agent, Web & DB,
/// Giám sát, Máy chủ của tôi, Chat thường, Hồ sơ, Màn hình app, Studio video)
/// thêm vào đây khi có `op` tương ứng.
const _entries = [
  _Entry('tasks', 'tasks.list', Icons.task_alt_rounded, '/ide/tasks'),
  _Entry(
    'ailog',
    'ailog.list',
    Icons.smart_toy_outlined,
    '/ide/ailog',
    project: true,
  ),
  _Entry(
    'oplog',
    'oplog.list',
    Icons.history_rounded,
    '/ide/oplog',
    project: true,
  ),
  _Entry(
    'notes',
    'notes.list',
    Icons.sticky_note_2_outlined,
    '/ide/notes',
    project: true,
  ),
  _Entry(
    'report',
    'report.self',
    Icons.assessment_outlined,
    '/ide/report',
    project: true,
  ),
  _Entry(
    'kientruc',
    'kientruc.read',
    Icons.account_tree_outlined,
    '/ide/kientruc',
    project: true,
  ),
  _Entry(
    'changelog',
    'changelog.read',
    Icons.new_releases_outlined,
    '/ide/changelog',
  ),
];

/// Danh sách mục của tab Thêm hiện được với [ready] (đã lọc theo `op`).
List<String> ideMoreVisibleKeys(IdeReady ready) => [
  for (final e in _entries)
    if (ready.hasOp(e.op)) e.key,
];

/// Tab Thêm: lưới mục, chỉ hiện mục IDE có `op`; thanh chọn dự án gọn cho các
/// mục theo dự án.
class IdeMoreTab extends ConsumerWidget {
  const IdeMoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(ideLinkStatusProvider).valueOrNull?.ready;
    final entries = [
      for (final e in _entries)
        if (ready != null && ready.hasOp(e.op)) e,
    ];
    if (entries.isEmpty) {
      return WebTuiEmptyState(
        title: tr('Chưa có mục nào', 'Nothing here yet'),
        message: tr(
          'Bản IDE trên máy tính chưa có chức năng cho mục này. Hãy cập nhật IDE.',
          'The desktop IDE has no features for this section. Update the IDE.',
        ),
        icon: Icons.apps_rounded,
      );
    }
    final needsProject = entries.any((e) => e.project);
    final current = needsProject
        ? ref.watch(ideCurrentProjectProvider).valueOrNull
        : null;
    final projects = ref.watch(ideProjectsProvider).valueOrNull ?? const [];
    return ListView(
      key: const Key('ide_more_grid'),
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        if (needsProject && current != null) ...[
          IdeProjectBar(
            projects: projects,
            current: current,
            onPick: (p) =>
                ref.read(ideSelectedProjectNameProvider.notifier).state =
                    p.name,
          ),
          const SizedBox(height: WebTuiSpacing.md),
        ],
        // Chữ hệ thống cỡ lớn: mỗi mục một hàng (biểu tượng + tên) để tên
        // không bị ngắt giữa từ; chiều cao theo nội dung nên không tràn.
        if (_bigText(context))
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
              child: _Tile(
                entry: e,
                row: true,
                onTap: () => _open(context, e, current),
              ),
            )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: WebTuiSpacing.md,
            crossAxisSpacing: WebTuiSpacing.md,
            childAspectRatio: 1.45,
            children: [
              for (final e in entries)
                _Tile(entry: e, onTap: () => _open(context, e, current)),
            ],
          ),
      ],
    );
  }

  void _open(BuildContext context, _Entry e, IdeProject? current) {
    final project = current?.name;
    context.push(
      e.project && project != null
          ? Uri(path: e.path, queryParameters: {'project': project}).toString()
          : e.path,
    );
  }
}

bool _bigText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13;

class _Tile extends StatelessWidget {
  const _Tile({required this.entry, required this.onTap, this.row = false});

  final _Entry entry;
  final VoidCallback onTap;
  final bool row;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: entry.title,
      excludeSemantics: true,
      child: InkWell(
        key: Key('ide_more_${entry.key}'),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          decoration: BoxDecoration(
            color: WebTuiColors.surface,
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            border: Border.all(color: WebTuiColors.border),
          ),
          child: Flex(
            direction: row ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: row
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Icon(entry.icon, size: 28, color: WebTuiColors.primary),
              const SizedBox(width: WebTuiSpacing.md, height: WebTuiSpacing.sm),
              Flexible(
                child: Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.titleMedium.copyWith(
                    color: WebTuiColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
