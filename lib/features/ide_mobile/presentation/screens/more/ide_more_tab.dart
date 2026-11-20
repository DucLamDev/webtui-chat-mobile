import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_project.dart';
import '../../../domain/ide_ready.dart';
import '../../controllers/ide_controllers.dart';
import '../../controllers/ide_project_controllers.dart';
import '../../widgets/ide_wb.dart';
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
    'talk' => tr('Chat thường', 'Chat'),
    'skills' => tr('Skill', 'Skills'),
    'agents' => tr('AI Agent', 'AI agents'),
    'demo' => tr('Web & DB', 'Web & DB'),
    'monitor' => tr('Giám sát', 'Monitoring'),
    'appscreen' => tr('Màn hình app', 'App screen'),
    'video' => tr('Studio video', 'Video studio'),
    'servers' => tr('Máy chủ của tôi', 'My servers'),
    'profile' => tr('Hồ sơ', 'Profile'),
    'devices' => tr('Điện thoại đã gắn', 'Linked phones'),
    _ => tr('Changelog nền tảng', 'Platform changelog'),
  };
}

/// Các mục GĐ3 + GĐ4 (Phụ lục B, C); mục chỉ hiện khi IDE có `op` tương ứng.
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
  _Entry('talk', 'talk.list', Icons.forum_outlined, '/ide/talk'),
  _Entry(
    'skills',
    'skills.list',
    Icons.extension_outlined,
    '/ide/skills',
    project: true,
  ),
  _Entry(
    'agents',
    'agents.session',
    Icons.hub_outlined,
    '/ide/agents',
    project: true,
  ),
  _Entry(
    'demo',
    'demo.status',
    Icons.language_rounded,
    '/ide/demo',
    project: true,
  ),
  _Entry(
    'monitor',
    'monitor.list',
    Icons.monitor_heart_outlined,
    '/ide/monitor',
    project: true,
  ),
  _Entry(
    'appscreen',
    'appscreen.status',
    Icons.phone_iphone_rounded,
    '/ide/appscreen',
    project: true,
  ),
  _Entry(
    'video',
    'video.list',
    Icons.movie_outlined,
    '/ide/video',
    project: true,
  ),
  _Entry('servers', 'servers.list', Icons.dns_outlined, '/ide/servers'),
  _Entry(
    'profile',
    'profile.show',
    Icons.person_outline_rounded,
    '/ide/profile',
  ),
  _Entry('devices', 'devices.list', Icons.devices_rounded, '/ide/devices'),
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
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
              child: _Tile(
                entry: e,
                row: true,
                onTap: () => _open(context, e, current),
              ),
            )
        else
          // 3 cột ô nhỏ để thấy hết các mục trong một màn như IDE web.
          // padding zero: không cộng thêm vùng an toàn lần nữa (khoảng trống).
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: WebTuiSpacing.sm,
            crossAxisSpacing: WebTuiSpacing.sm,
            childAspectRatio: 1.15,
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
          padding: const EdgeInsets.all(WebTuiSpacing.sm + 2),
          decoration: BoxDecoration(
            color: IdeWb.bg,
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            border: Border.all(color: IdeWb.border),
          ),
          child: Flex(
            direction: row ? Axis.horizontal : Axis.vertical,
            mainAxisAlignment: row
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            crossAxisAlignment: row
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: IdeWb.accentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(entry.icon, size: 18, color: IdeWb.accentInk),
              ),
              const SizedBox(width: WebTuiSpacing.md, height: WebTuiSpacing.sm),
              Flexible(
                child: Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: IdeType.bodyMedium.copyWith(
                    color: IdeWb.textStrong,
                    fontWeight: FontWeight.w600,
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
