import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/my_note.dart';
import '../controllers/my_notes_list_controller.dart';
import 'my_note_widgets.dart';

/// Quản lý thư mục cơ bản: tạo (ở gốc / bên trong), đổi tên, xoá.
Future<void> showMyNoteFolderSheet(
  BuildContext context, {
  required String workspaceId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: WebTuiColors.surface,
    builder: (_) => _MyNoteFolderSheet(workspaceId: workspaceId),
  );
}

class _MyNoteFolderSheet extends ConsumerWidget {
  const _MyNoteFolderSheet({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = myNotesListControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final nodes = flattenMyNoteFolderTree(state.folderTree);
    final readOnly = state.isOffline;

    Future<void> run(Future<String?> Function() action, String done) async {
      final error = await action();
      if (!context.mounted) return;
      showMyNoteSnack(context, error ?? done);
    }

    Future<void> create({String? parentId}) async {
      final name = await showMyNoteTextDialog(
        context,
        title: parentId == null ? 'Thư mục mới' : 'Thư mục con mới',
        label: 'Tên thư mục',
        confirmLabel: 'Tạo',
        maxLength: MyNoteLimits.folderNameMaxLength,
      );
      if (name == null || !context.mounted) return;
      await run(
        () => controller.createFolder(name, parentId: parentId),
        'Đã tạo thư mục.',
      );
    }

    Future<void> rename(MyNoteFolder folder) async {
      final name = await showMyNoteTextDialog(
        context,
        title: 'Đổi tên thư mục',
        label: 'Tên thư mục',
        confirmLabel: 'Lưu',
        initialValue: folder.name,
        maxLength: MyNoteLimits.folderNameMaxLength,
      );
      if (name == null || !context.mounted) return;
      await run(
        () => controller.renameFolder(folder.id, name),
        'Đã đổi tên thư mục.',
      );
    }

    Future<void> delete(MyNoteFolder folder) async {
      final confirmed = await confirmMyNoteAction(
        context,
        title: 'Xoá thư mục?',
        message:
            'Xoá "${folder.name}". Các ghi chú trong thư mục sẽ chuyển về '
            '"Chưa xếp thư mục", không bị xoá.',
        confirmLabel: 'Xoá',
      );
      if (!confirmed || !context.mounted) return;
      await run(() => controller.deleteFolder(folder.id), 'Đã xoá thư mục.');
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                0,
                WebTuiSpacing.lg,
                WebTuiSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Thư mục My Note',
                      style: WebTuiTypography.titleMedium.copyWith(
                        color: WebTuiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('my_notes_folder_create'),
                    onPressed: readOnly ? null : () => create(),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Thư mục mới'),
                  ),
                ],
              ),
            ),
            if (readOnly)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
                child: MyNotesOfflineBanner(),
              ),
            if (nodes.isEmpty)
              Padding(
                padding: const EdgeInsets.all(WebTuiSpacing.lg),
                child: Text(
                  'Chưa có thư mục nào.',
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final node in nodes)
                      ListTile(
                        contentPadding: EdgeInsets.only(
                          left: WebTuiSpacing.lg + (node.depth - 1) * 20,
                          right: WebTuiSpacing.xs,
                        ),
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(node.folder.name),
                        subtitle: Text('${node.folder.noteCount} ghi chú'),
                        trailing: readOnly
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: 'Thao tác thư mục',
                                onSelected: (value) {
                                  switch (value) {
                                    case 'child':
                                      create(parentId: node.folder.id);
                                    case 'rename':
                                      rename(node.folder);
                                    case 'delete':
                                      delete(node.folder);
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (node.depth < MyNoteLimits.folderMaxDepth)
                                    const PopupMenuItem(
                                      value: 'child',
                                      child: Text('Thêm thư mục con'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Đổi tên'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Xoá'),
                                  ),
                                ],
                              ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: WebTuiSpacing.md),
          ],
        ),
      ),
    );
  }
}
