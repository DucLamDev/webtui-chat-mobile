import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/my_note.dart';
import '../controllers/my_notes_list_controller.dart';
import 'my_note_folder_sheet.dart';

/// Số bộ lọc đang bật (thư mục, tag, ghim) — dùng cho dấu trên nút "Lọc".
int myNoteActiveFilterCount(MyNoteFilter filter) =>
    (filter.folderId != null ? 1 : 0) +
    (filter.tag != null ? 1 : 0) +
    (filter.pinnedOnly ? 1 : 0);

/// Bảng "Lọc": ghim, thư mục, tag và lối vào quản lý thư mục.
Future<void> showMyNoteFilterSheet(
  BuildContext context, {
  required String workspaceId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: WebTuiColors.surface,
    builder: (_) => _MyNoteFilterSheet(workspaceId: workspaceId),
  );
}

class _MyNoteFilterSheet extends ConsumerWidget {
  const _MyNoteFilterSheet({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = myNotesListControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final filter = state.filter;
    final nodes = flattenMyNoteFolderTree(state.folderTree);

    Widget section(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
        WebTuiSpacing.lg,
        WebTuiSpacing.xs,
      ),
      child: Text(
        label,
        style: WebTuiTypography.labelSmall.copyWith(
          color: WebTuiColors.textMuted,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          key: const Key('my_notes_filter_sheet'),
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lọc ghi chú',
                      style: WebTuiTypography.titleMedium.copyWith(
                        color: WebTuiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (myNoteActiveFilterCount(filter) > 0)
                    TextButton(
                      key: const Key('my_notes_filter_clear'),
                      onPressed: () {
                        unawaited(controller.setFolder(null));
                        unawaited(controller.setTag(null));
                        unawaited(controller.setPinnedOnly(false));
                      },
                      child: const Text('Xoá lọc'),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              key: const Key('my_notes_pinned_filter'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: WebTuiSpacing.lg,
              ),
              secondary: const Icon(Icons.push_pin_outlined),
              title: const Text('Chỉ ghi chú đã ghim'),
              value: filter.pinnedOnly,
              onChanged: (value) => unawaited(controller.setPinnedOnly(value)),
            ),
            section('THƯ MỤC'),
            ListTile(
              leading: const Icon(Icons.all_inbox_outlined),
              title: const Text('Mọi thư mục'),
              selected: filter.folderId == null,
              trailing: filter.folderId == null
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => unawaited(controller.setFolder(null)),
            ),
            ListTile(
              key: const Key('my_notes_folder_root_filter'),
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Chưa xếp thư mục'),
              selected: filter.folderId == myNoteRootFolderFilter,
              trailing: filter.folderId == myNoteRootFolderFilter
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () =>
                  unawaited(controller.setFolder(myNoteRootFolderFilter)),
            ),
            for (final node in nodes)
              ListTile(
                contentPadding: EdgeInsets.only(
                  left: WebTuiSpacing.lg + (node.depth - 1) * 20,
                  right: WebTuiSpacing.lg,
                ),
                leading: const Icon(Icons.folder_outlined),
                title: Text(node.folder.name),
                selected: filter.folderId == node.folder.id,
                trailing: filter.folderId == node.folder.id
                    ? const Icon(Icons.check_rounded)
                    : Text('${node.folder.noteCount}'),
                onTap: () => unawaited(controller.setFolder(node.folder.id)),
              ),
            if (!state.isOffline)
              ListTile(
                key: const Key('my_notes_manage_folders'),
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Quản lý thư mục'),
                onTap: () => unawaited(
                  showMyNoteFolderSheet(context, workspaceId: workspaceId),
                ),
              ),
            if (state.tags.isNotEmpty) ...[
              section('TAG'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.lg,
                ),
                child: Wrap(
                  spacing: WebTuiSpacing.xs,
                  runSpacing: WebTuiSpacing.xs,
                  children: [
                    for (final tag in state.tags)
                      FilterChip(
                        label: Text('#${tag.tag} (${tag.count})'),
                        selected: filter.tag == tag.tag,
                        onSelected: (selected) => unawaited(
                          controller.setTag(selected ? tag.tag : null),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              child: FilledButton(
                key: const Key('my_notes_filter_done'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Xong'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
