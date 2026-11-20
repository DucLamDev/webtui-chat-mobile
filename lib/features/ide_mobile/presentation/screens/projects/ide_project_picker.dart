import 'package:flutter/material.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_project.dart';
import '../../widgets/ide_wb.dart';

/// Nhóm hiển thị của một dự án: dự án riêng tách khỏi ba kiểu còn lại.
enum IdeProjectGroup { git, vps, local, my }

IdeProjectGroup ideProjectGroup(IdeProject p) {
  if (p.my) return IdeProjectGroup.my;
  return switch (p.kind) {
    IdeProjectKind.git => IdeProjectGroup.git,
    IdeProjectKind.vps => IdeProjectGroup.vps,
    IdeProjectKind.local => IdeProjectGroup.local,
  };
}

String ideProjectGroupLabel(IdeProjectGroup g) => switch (g) {
  IdeProjectGroup.git => tr('Có repo (Git)', 'With a repo (Git)'),
  IdeProjectGroup.vps => tr('Máy chủ VPS', 'VPS servers'),
  IdeProjectGroup.local => tr('Chỉ trên Dev VPS', 'Dev VPS only'),
  IdeProjectGroup.my => tr('Dự án riêng', 'Private projects'),
};

/// Lọc theo tên / nhãn / nhánh (không phân biệt hoa thường) rồi nhóm theo kiểu.
Map<IdeProjectGroup, List<IdeProject>> ideGroupProjects(
  List<IdeProject> all,
  String query,
) {
  final q = query.trim().toLowerCase();
  final out = <IdeProjectGroup, List<IdeProject>>{};
  for (final g in IdeProjectGroup.values) {
    final items = [
      for (final p in all)
        if (ideProjectGroup(p) == g &&
            (q.isEmpty ||
                p.title.toLowerCase().contains(q) ||
                p.name.toLowerCase().contains(q) ||
                p.branch.toLowerCase().contains(q)))
          p,
    ];
    if (items.isNotEmpty) out[g] = items;
  }
  return out;
}

/// Bảng trượt chọn dự án: ô tìm + nhóm theo kiểu.
Future<IdeProject?> showIdeProjectPicker(
  BuildContext context, {
  required List<IdeProject> projects,
  required String currentName,
}) {
  return showWebTuiSheet<IdeProject>(
    context: context,
    builder: (_) => _PickerSheet(projects: projects, currentName: currentName),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.projects, required this.currentName});

  final List<IdeProject> projects;
  final String currentName;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final groups = ideGroupProjects(widget.projects, _query);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          WebTuiSheetHeader(title: tr('Chọn dự án', 'Choose a project')),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              0,
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
            ),
            child: WebTuiSearchBar(
              hintText: tr('Tìm dự án', 'Search projects'),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? WebTuiEmptyState(
                    key: const Key('ide_picker_empty'),
                    title: tr('Không có dự án nào khớp', 'No matching project'),
                    message: tr('Thử gõ tên khác.', 'Try a different name.'),
                    icon: Icons.search_off_rounded,
                  )
                : ListView(
                    children: [
                      for (final e in groups.entries) ...[
                        WebTuiSectionLabel(ideProjectGroupLabel(e.key)),
                        for (final p in e.value)
                          ListTile(
                            key: Key('ide_pick_${p.name}'),
                            minTileHeight: 56,
                            selected: p.name == widget.currentName,
                            title: Text(
                              p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: p.branch.isEmpty
                                ? null
                                : Text(
                                    p.branch,
                                    style: IdeType.bodySmall.copyWith(
                                      color: IdeWb.text2,
                                    ),
                                  ),
                            trailing: p.name == widget.currentName
                                ? Icon(
                                    Icons.check_rounded,
                                    color: IdeWb.accentInk,
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(p),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
