import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/my_note.dart';
import '../controllers/my_notes_list_controller.dart';
import 'my_note_widgets.dart';

/// Số bộ lọc đang bật (thư mục, tag, ghim) — dùng cho dấu trên nút "Lọc".
int myNoteActiveFilterCount(MyNoteFilter filter) =>
    (filter.folderId != null ? 1 : 0) +
    (filter.tag != null ? 1 : 0) +
    (filter.pinnedOnly ? 1 : 0);

/// Bảng "Lọc" duy nhất: ghim, thư mục (chọn, tạo, đổi tên, xoá ngay trong
/// danh sách) và thẻ.
Future<void> showMyNoteFilterSheet(
  BuildContext context, {
  required String workspaceId,
}) {
  return showWebTuiSheet<void>(
    context: context,
    builder: (_) => _MyNoteFilterSheet(workspaceId: workspaceId),
  );
}

class _MyNoteFilterSheet extends ConsumerStatefulWidget {
  const _MyNoteFilterSheet({required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<_MyNoteFilterSheet> createState() => _MyNoteFilterSheetState();
}

class _MyNoteFilterSheetState extends ConsumerState<_MyNoteFilterSheet> {
  /// Thư mục đang mở hàng thao tác (đổi tên / thư mục con / xoá).
  String? _openFolderId;

  MyNotesListController get _controller =>
      ref.read(myNotesListControllerProvider(widget.workspaceId).notifier);

  Future<void> _run(Future<String?> Function() action, String done) async {
    final error = await action();
    if (!mounted) return;
    showMyNoteSnack(context, error ?? done);
  }

  Future<void> _create({String? parentId}) async {
    final name = await showMyNoteTextDialog(
      context,
      title: parentId == null
          ? tr('Thư mục mới', 'New folder')
          : tr('Thư mục con mới', 'New subfolder'),
      label: tr('Tên thư mục', 'Folder name'),
      confirmLabel: tr('Tạo', 'Create'),
      icon: WebTuiIcons.folderPlus,
      maxLength: MyNoteLimits.folderNameMaxLength,
    );
    if (name == null || !mounted) return;
    await _run(
      () => _controller.createFolder(name, parentId: parentId),
      tr('Đã tạo thư mục.', 'Folder created.'),
    );
  }

  Future<void> _rename(MyNoteFolder folder) async {
    final name = await showMyNoteTextDialog(
      context,
      title: tr('Đổi tên thư mục', 'Rename folder'),
      label: tr('Tên thư mục', 'Folder name'),
      confirmLabel: tr('Lưu', 'Save'),
      icon: WebTuiIcons.folderEdit,
      initialValue: folder.name,
      maxLength: MyNoteLimits.folderNameMaxLength,
    );
    if (name == null || !mounted) return;
    await _run(
      () => _controller.renameFolder(folder.id, name),
      tr('Đã đổi tên thư mục.', 'Folder renamed.'),
    );
  }

  Future<void> _delete(MyNoteFolder folder) async {
    final confirmed = await confirmMyNoteAction(
      context,
      title: tr('Xoá thư mục?', 'Delete folder?'),
      message: tr(
        'Xoá "${folder.name}". Các ghi chú trong thư mục sẽ chuyển về "Chưa xếp thư mục", không bị xoá.',
        'Delete "${folder.name}". Notes in this folder will move to "No folder" and won\'t be deleted.',
      ),
      confirmLabel: tr('Xoá', 'Delete'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _openFolderId = null);
    await _run(
      () => _controller.deleteFolder(folder.id),
      tr('Đã xoá thư mục.', 'Folder deleted.'),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WebTuiSpacing.xl,
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

  Widget _check() =>
      Icon(WebTuiIcons.check, size: 20, color: WebTuiColors.primary);

  Widget _folderActions(MyNoteFolderNode node) {
    return Padding(
      padding: EdgeInsets.only(
        left: WebTuiSpacing.xl + 12 + (node.depth - 1) * 16,
        right: WebTuiSpacing.lg,
        bottom: WebTuiSpacing.xs,
      ),
      child: Wrap(
        key: Key('my_notes_folder_actions_${node.folder.id}'),
        spacing: WebTuiSpacing.xs,
        children: [
          ActionChip(
            avatar: const Icon(WebTuiIcons.edit, size: 16),
            label: Text(tr('Đổi tên', 'Rename')),
            onPressed: () => unawaited(_rename(node.folder)),
          ),
          if (node.depth < MyNoteLimits.folderMaxDepth)
            ActionChip(
              avatar: const Icon(WebTuiIcons.folderPlus, size: 16),
              label: Text(tr('Thư mục con', 'Subfolder')),
              onPressed: () => unawaited(_create(parentId: node.folder.id)),
            ),
          ActionChip(
            avatar: Icon(
              WebTuiIcons.delete,
              size: 16,
              color: WebTuiColors.danger,
            ),
            label: Text(
              tr('Xoá', 'Delete'),
              style: TextStyle(color: WebTuiColors.danger),
            ),
            onPressed: () => unawaited(_delete(node.folder)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myNotesListControllerProvider(widget.workspaceId));
    final controller = _controller;
    final filter = state.filter;
    final nodes = flattenMyNoteFolderTree(state.folderTree);
    final editable = !state.isOffline;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: ListView(
        key: const Key('my_notes_filter_sheet'),
        shrinkWrap: true,
        children: [
          WebTuiSheetHeader(
            title: tr('Lọc ghi chú', 'Filter notes'),
            trailing: myNoteActiveFilterCount(filter) > 0
                ? TextButton(
                    key: const Key('my_notes_filter_clear'),
                    onPressed: () {
                      unawaited(controller.setFolder(null));
                      unawaited(controller.setTag(null));
                      unawaited(controller.setPinnedOnly(false));
                    },
                    child: Text(tr('Xoá lọc', 'Clear filters')),
                  )
                : null,
          ),
          WebTuiSheetActionTile(
            key: const Key('my_notes_pinned_filter'),
            icon: WebTuiIcons.pin,
            title: tr('Chỉ ghi chú đã ghim', 'Pinned notes only'),
            selected: filter.pinnedOnly,
            onTap: () =>
                unawaited(controller.setPinnedOnly(!filter.pinnedOnly)),
            trailing: IgnorePointer(
              child: Switch(
                value: filter.pinnedOnly,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) {},
              ),
            ),
          ),
          _section(tr('THƯ MỤC', 'FOLDERS')),
          WebTuiSheetActionTile(
            icon: WebTuiIcons.sharedFiles,
            title: tr('Mọi thư mục', 'All folders'),
            selected: filter.folderId == null,
            trailing: filter.folderId == null ? _check() : null,
            onTap: () => unawaited(controller.setFolder(null)),
          ),
          WebTuiSheetActionTile(
            key: const Key('my_notes_folder_root_filter'),
            icon: WebTuiIcons.file,
            title: tr('Chưa xếp thư mục', 'No folder'),
            selected: filter.folderId == myNoteRootFolderFilter,
            trailing: filter.folderId == myNoteRootFolderFilter
                ? _check()
                : null,
            onTap: () =>
                unawaited(controller.setFolder(myNoteRootFolderFilter)),
          ),
          for (final node in nodes) ...[
            Padding(
              padding: EdgeInsets.only(left: (node.depth - 1) * 16.0),
              child: WebTuiSheetActionTile(
                key: Key('my_notes_folder_${node.folder.id}'),
                icon: WebTuiIcons.folderOpen,
                title: node.folder.name,
                subtitle: tr(
                  '${node.folder.noteCount} ghi chú',
                  '${node.folder.noteCount} notes',
                ),
                selected: filter.folderId == node.folder.id,
                onTap: () => unawaited(controller.setFolder(node.folder.id)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (filter.folderId == node.folder.id) _check(),
                    if (editable)
                      IconButton(
                        key: Key('my_notes_folder_more_${node.folder.id}'),
                        tooltip: tr('Thao tác thư mục', 'Folder actions'),
                        icon: const Icon(WebTuiIcons.more, size: 20),
                        onPressed: () => setState(
                          () => _openFolderId = _openFolderId == node.folder.id
                              ? null
                              : node.folder.id,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (editable && _openFolderId == node.folder.id)
              _folderActions(node),
          ],
          if (editable)
            WebTuiSheetActionTile(
              key: const Key('my_notes_folder_create'),
              icon: WebTuiIcons.folderPlus,
              title: tr('Thư mục mới', 'New folder'),
              onTap: () => unawaited(_create()),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
              child: MyNotesOfflineBanner(),
            ),
          if (state.tags.isNotEmpty) ...[
            _section('THẺ'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.xl),
              child: Wrap(
                spacing: WebTuiSpacing.xs,
                runSpacing: WebTuiSpacing.xs,
                children: [
                  for (final tag in state.tags)
                    FilterChip(
                      visualDensity: VisualDensity.compact,
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
    );
  }
}
