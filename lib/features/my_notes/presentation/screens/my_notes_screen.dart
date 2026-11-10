import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/my_note.dart';
import '../controllers/my_notes_access_provider.dart';
import '../controllers/my_notes_list_controller.dart';
import '../widgets/my_note_folder_sheet.dart';
import '../widgets/my_note_widgets.dart';

/// Đường dẫn mở một ghi chú (`new` = ghi chú mới).
String myNoteLocation({
  required String workspaceId,
  required String noteId,
  String? folderId,
}) {
  return Uri(
    path: '/my-notes/${Uri.encodeComponent(noteId)}',
    queryParameters: {
      'workspaceId': workspaceId,
      if (folderId != null && folderId.isNotEmpty) 'folderId': folderId,
    },
  ).toString();
}

/// Sổ ghi chú cá nhân My Note: danh sách, lọc, tìm, thư mục.
class MyNotesScreen extends ConsumerWidget {
  const MyNotesScreen({this.workspaceId, super.key});

  final String? workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(myNotesEnabledProvider);
    final resolvedWorkspaceId = resolveMyNotesWorkspaceId(ref, workspaceId);
    final ready = enabled && resolvedWorkspaceId.isNotEmpty;
    return Scaffold(
      backgroundColor: WebTuiColors.background,
      appBar: AppBar(
        title: const Text('My Note'),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (ready)
            IconButton(
              key: const Key('my_notes_manage_folders'),
              tooltip: 'Quản lý thư mục',
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () => showMyNoteFolderSheet(
                context,
                workspaceId: resolvedWorkspaceId,
              ),
            ),
        ],
      ),
      floatingActionButton: ready
          ? _NewNoteButton(workspaceId: resolvedWorkspaceId)
          : null,
      body: SafeArea(
        top: false,
        child: !enabled
            ? const _MyNotesDisabled()
            : resolvedWorkspaceId.isEmpty
            ? const WebTuiEmptyState(
                title: 'Chưa chọn workspace',
                message: 'Chọn workspace trước khi mở My Note.',
                icon: Icons.sticky_note_2_outlined,
              )
            : _MyNotesBody(workspaceId: resolvedWorkspaceId),
      ),
    );
  }
}

String resolveMyNotesWorkspaceId(WidgetRef ref, String? workspaceId) {
  final requested = workspaceId?.trim() ?? '';
  if (requested.isNotEmpty) return requested;
  return ref
          .watch(
            workspaceControllerProvider.select(
              (state) => state.activeWorkspace?.id,
            ),
          )
          ?.trim() ??
      '';
}

class _MyNotesDisabled extends StatelessWidget {
  const _MyNotesDisabled();

  @override
  Widget build(BuildContext context) {
    return const WebTuiEmptyState(
      key: Key('my_notes_disabled'),
      title: 'My Note chưa được bật',
      message: myNotesDisabledMessage,
      icon: Icons.sticky_note_2_outlined,
    );
  }
}

class _NewNoteButton extends ConsumerWidget {
  const _NewNoteButton({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myNotesListControllerProvider(workspaceId));
    if (state.featureDisabled) return const SizedBox.shrink();
    return FloatingActionButton.extended(
      key: const Key('my_notes_new'),
      onPressed: () {
        if (state.isOffline) {
          showMyNoteSnack(
            context,
            'Bạn đang ngoại tuyến. Kết nối lại để tạo ghi chú mới.',
          );
          return;
        }
        final folder = state.filter.folderId;
        unawaited(
          context.push(
            myNoteLocation(
              workspaceId: workspaceId,
              noteId: 'new',
              folderId: folder == myNoteRootFolderFilter ? null : folder,
            ),
          ),
        );
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('Ghi chú mới'),
    );
  }
}

class _MyNotesBody extends ConsumerWidget {
  const _MyNotesBody({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = myNotesListControllerProvider(workspaceId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    if (state.featureDisabled) return const _MyNotesDisabled();

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if ((notification is ScrollUpdateNotification ||
                  notification is OverscrollNotification) &&
              notification.metrics.extentAfter < 480) {
            unawaited(controller.loadMore());
          }
          return false;
        },
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (state.isOffline)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  WebTuiSpacing.lg,
                  WebTuiSpacing.md,
                  WebTuiSpacing.lg,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: MyNotesOfflineBanner(cachedAt: state.cachedAt),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  WebTuiSpacing.lg,
                  WebTuiSpacing.md,
                  WebTuiSpacing.lg,
                  WebTuiSpacing.sm,
                ),
                child: WebTuiSearchBar(
                  hintText: 'Tìm trong tiêu đề, nội dung...',
                  debounceDuration: const Duration(milliseconds: 350),
                  onChanged: (value) => unawaited(controller.setQuery(value)),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _FilterBar(
                state: state,
                controller: controller,
                workspaceId: workspaceId,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: WebTuiSpacing.sm)),
            ..._content(context, state, controller),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    MyNotesListState state,
    MyNotesListController controller,
  ) {
    if (state.isLoading && state.items.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: WebTuiLoadingState(message: 'Đang tải ghi chú...'),
        ),
      ];
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: WebTuiErrorState(
            title: 'Chưa tải được My Note',
            message: state.errorMessage!,
            onRetry: () => unawaited(controller.refresh()),
          ),
        ),
      ];
    }
    if (state.hasLoaded && state.items.isEmpty) {
      final filtered = !state.filter.isDefault;
      return [
        SliverToBoxAdapter(
          child: WebTuiEmptyState(
            key: const Key('my_notes_empty'),
            title: filtered ? 'Không có ghi chú phù hợp' : 'Chưa có ghi chú',
            message: filtered
                ? 'Thử bỏ bớt bộ lọc hoặc đổi từ khoá tìm kiếm.'
                : 'Ghi lại ý tưởng, việc cần nhớ, hoặc nhấn giữ một tin nhắn '
                      'để lưu vào My Note.',
            icon: Icons.sticky_note_2_outlined,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
        sliver: SliverList.separated(
          itemCount: state.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: WebTuiSpacing.sm),
          itemBuilder: (context, index) {
            final note = state.items[index];
            return _NoteTile(
              note: note,
              folderName: state.folderById(note.folderId)?.name,
              onTap: () => unawaited(
                context.push(
                  myNoteLocation(workspaceId: workspaceId, noteId: note.id),
                ),
              ),
              onLongPress: state.isOffline
                  ? null
                  : () => _showNoteActions(context, note, controller),
            );
          },
        ),
      ),
      if (state.isLoadingMore)
        const SliverToBoxAdapter(
          child: WebTuiLoadingState(message: 'Đang tải thêm...'),
        ),
      if (state.loadMoreErrorMessage != null)
        SliverToBoxAdapter(
          child: Center(
            child: TextButton.icon(
              onPressed: () => unawaited(controller.loadMore()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tải thêm lỗi, thử lại'),
            ),
          ),
        ),
    ];
  }

  Future<void> _showNoteActions(
    BuildContext context,
    MyNoteSummary note,
    MyNotesListController controller,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: WebTuiColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                note.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              ),
              title: Text(note.pinned ? 'Bỏ ghim' : 'Ghim lên đầu'),
              onTap: () => Navigator.of(sheetContext).pop('pin'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: WebTuiColors.danger,
              ),
              title: const Text(
                'Xoá ghi chú',
                style: TextStyle(color: WebTuiColors.danger),
              ),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    String? error;
    if (action == 'pin') {
      error = await controller.togglePin(note);
    } else if (action == 'delete') {
      final confirmed = await confirmMyNoteAction(
        context,
        title: 'Xoá ghi chú?',
        message: 'Ghi chú "${note.displayTitle}" sẽ bị xoá khỏi My Note.',
        confirmLabel: 'Xoá',
      );
      if (!confirmed) return;
      error = await controller.deleteNote(note);
      if (error == null && context.mounted) {
        showMyNoteSnack(context, 'Đã xoá ghi chú.');
      }
    }
    if (error != null && context.mounted) showMyNoteSnack(context, error);
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.state,
    required this.controller,
    required this.workspaceId,
  });

  final MyNotesListState state;
  final MyNotesListController controller;
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    final filter = state.filter;
    final folderLabel = switch (filter.folderId) {
      null => 'Mọi thư mục',
      myNoteRootFolderFilter => 'Chưa xếp thư mục',
      final id => state.folderById(id)?.name ?? 'Thư mục',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
      child: Row(
        children: [
          InputChip(
            key: const Key('my_notes_folder_filter'),
            avatar: const Icon(Icons.folder_outlined, size: 18),
            label: Text(folderLabel),
            selected: filter.folderId != null,
            onPressed: () => _pickFolder(context),
            onDeleted: filter.folderId == null
                ? null
                : () => unawaited(controller.setFolder(null)),
          ),
          const SizedBox(width: WebTuiSpacing.xs),
          FilterChip(
            key: const Key('my_notes_pinned_filter'),
            avatar: const Icon(Icons.push_pin_outlined, size: 18),
            label: const Text('Đã ghim'),
            selected: filter.pinnedOnly,
            onSelected: (value) => unawaited(controller.setPinnedOnly(value)),
          ),
          for (final tag in state.tags) ...[
            const SizedBox(width: WebTuiSpacing.xs),
            FilterChip(
              label: Text('#${tag.tag} (${tag.count})'),
              selected: filter.tag == tag.tag,
              onSelected: (selected) =>
                  unawaited(controller.setTag(selected ? tag.tag : null)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFolder(BuildContext context) async {
    final nodes = flattenMyNoteFolderTree(state.folderTree);
    final picked = await showModalBottomSheet<_FolderChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: WebTuiColors.surface,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.all_inbox_outlined),
                title: const Text('Mọi thư mục'),
                selected: state.filter.folderId == null,
                onTap: () =>
                    Navigator.of(sheetContext).pop(const _FolderChoice(null)),
              ),
              ListTile(
                leading: const Icon(Icons.inbox_outlined),
                title: const Text('Chưa xếp thư mục'),
                selected: state.filter.folderId == myNoteRootFolderFilter,
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(const _FolderChoice(myNoteRootFolderFilter)),
              ),
              for (final node in nodes)
                ListTile(
                  contentPadding: EdgeInsets.only(
                    left: WebTuiSpacing.lg + (node.depth - 1) * 20,
                    right: WebTuiSpacing.lg,
                  ),
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(node.folder.name),
                  trailing: Text('${node.folder.noteCount}'),
                  selected: state.filter.folderId == node.folder.id,
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_FolderChoice(node.folder.id)),
                ),
              if (nodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(WebTuiSpacing.lg),
                  child: Text(
                    'Chưa có thư mục. Dùng nút thư mục trên thanh tiêu đề để '
                    'tạo.',
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) unawaited(controller.setFolder(picked.folderId));
  }
}

final class _FolderChoice {
  const _FolderChoice(this.folderId);

  final String? folderId;
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.onTap,
    this.onLongPress,
    this.folderName,
  });

  final MyNoteSummary note;
  final String? folderName;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WebTuiColors.surface,
      borderRadius: BorderRadius.circular(WebTuiRadii.lg),
      child: InkWell(
        key: Key('my_note_tile_${note.id}'),
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(WebTuiSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            border: Border.all(color: WebTuiColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (note.pinned) ...[
                    const Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: WebTuiColors.primary,
                      semanticLabel: 'Đã ghim',
                    ),
                    const SizedBox(width: WebTuiSpacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      note.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.bodyMedium.copyWith(
                        color: WebTuiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (note.excerpt.isNotEmpty) ...[
                const SizedBox(height: WebTuiSpacing.xxs),
                Text(
                  note.excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
              if (note.tags.isNotEmpty) ...[
                const SizedBox(height: WebTuiSpacing.xs),
                Wrap(
                  spacing: WebTuiSpacing.xs,
                  runSpacing: WebTuiSpacing.xs,
                  children: [
                    for (final tag in note.tags) MyNoteTagChip(tag: tag),
                  ],
                ),
              ],
              const SizedBox(height: WebTuiSpacing.xs),
              Text(
                [
                  formatMyNoteTime(note.updatedAt),
                  ?folderName,
                  if (note.isFromMessage) 'Từ tin nhắn',
                  if (note.attachmentCount > 0)
                    '${note.attachmentCount} tệp đính kèm',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WebTuiTypography.labelSmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
