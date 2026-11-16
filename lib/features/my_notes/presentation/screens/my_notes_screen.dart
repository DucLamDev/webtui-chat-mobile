import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../workspace/presentation/controllers/workspace_controller.dart';
import '../../domain/entities/my_note.dart';
import '../../domain/markdown/my_note_markdown.dart';
import '../controllers/my_notes_access_provider.dart';
import '../controllers/my_notes_list_controller.dart';
import '../widgets/my_note_filter_sheet.dart';
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
      ),
      floatingActionButton: ready
          ? _NewNoteButton(workspaceId: resolvedWorkspaceId)
          : null,
      body: SafeArea(
        top: false,
        child: !enabled
            ? const _MyNotesDisabled()
            : resolvedWorkspaceId.isEmpty
            ? WebTuiEmptyState(
                title: tr('Chưa chọn workspace', 'No workspace selected'),
                message: tr(
                  'Chọn workspace trước khi mở My Note.',
                  'Select a workspace before opening My Note.',
                ),
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
    return WebTuiEmptyState(
      key: Key('my_notes_disabled'),
      title: tr('My Note chưa được bật', 'My Note isn\'t enabled'),
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
            tr(
              'Bạn đang ngoại tuyến. Kết nối lại để tạo ghi chú mới.',
              'You\'re offline. Reconnect to create new notes.',
            ),
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
      label: Text(tr('Ghi chú mới', 'New note')),
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
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: WebTuiSearchBar(
                        hintText: tr('Tìm ghi chú', 'Search notes'),
                        debounceDuration: const Duration(milliseconds: 350),
                        onChanged: (value) =>
                            unawaited(controller.setQuery(value)),
                      ),
                    ),
                    const SizedBox(width: WebTuiSpacing.xs),
                    _FilterButton(
                      count: myNoteActiveFilterCount(state.filter),
                      onPressed: () => unawaited(
                        showMyNoteFilterSheet(
                          context,
                          workspaceId: workspaceId,
                        ),
                      ),
                    ),
                  ],
                ),
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
      return [
        SliverToBoxAdapter(
          child: WebTuiLoadingState(
            message: tr('Đang tải ghi chú...', 'Loading note...'),
          ),
        ),
      ];
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: WebTuiErrorState(
            title: tr('Chưa tải được My Note', 'Couldn\'t load My Note'),
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
            title: filtered
                ? tr('Không có ghi chú phù hợp', 'No matching notes')
                : tr('Chưa có ghi chú', 'No notes yet'),
            message: filtered
                ? tr(
                    'Thử bỏ bớt bộ lọc hoặc đổi từ khoá tìm kiếm.',
                    'Try removing some filters or changing your search.',
                  )
                : tr(
                    'Ghi lại ý tưởng, việc cần nhớ, hoặc nhấn giữ một tin nhắn để lưu vào My Note.',
                    'Jot down ideas and things to remember, or long-press a message to save it to My Note.',
                  ),
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
        SliverToBoxAdapter(
          child: WebTuiLoadingState(
            message: tr('Đang tải thêm...', 'Loading more...'),
          ),
        ),
      if (state.loadMoreErrorMessage != null)
        SliverToBoxAdapter(
          child: Center(
            child: TextButton.icon(
              onPressed: () => unawaited(controller.loadMore()),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                tr('Tải thêm lỗi, thử lại', 'Couldn\'t load more, retry'),
              ),
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
    final action = await showWebTuiSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WebTuiSheetHeader(
              title: note.displayTitle,
              subtitle: tr('Ghi chú của tôi', 'My notes'),
            ),
            WebTuiSheetActionTile(
              icon: WebTuiIcons.pin,
              title: note.pinned
                  ? tr('Bỏ ghim', 'Unpin')
                  : tr('Ghim lên đầu', 'Pin to top'),
              onTap: () => Navigator.of(sheetContext).pop('pin'),
            ),
            WebTuiSheetActionTile(
              icon: WebTuiIcons.delete,
              title: tr('Xoá ghi chú', 'Delete note'),
              tone: WebTuiDialogTone.danger,
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
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
        title: tr('Xoá ghi chú?', 'Delete note?'),
        message: tr(
          'Ghi chú "${note.displayTitle}" sẽ bị xoá khỏi My Note.',
          'The note "${note.displayTitle}" will be removed from My Note.',
        ),
        confirmLabel: tr('Xoá', 'Delete'),
      );
      if (!confirmed) return;
      error = await controller.deleteNote(note);
      if (error == null && context.mounted) {
        showMyNoteSnack(context, tr('Đã xoá ghi chú.', 'Note deleted.'));
      }
    }
    if (error != null && context.mounted) showMyNoteSnack(context, error);
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      key: const Key('my_notes_filter_button'),
      tooltip: tr('Lọc', 'Filter'),
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.tune_rounded),
      ),
    );
  }
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
    final preview = myNoteMarkdownToPlainText(note.excerpt).trim();
    return Material(
      color: WebTuiColors.surface,
      borderRadius: BorderRadius.circular(WebTuiRadii.lg),
      child: InkWell(
        key: Key('my_note_tile_${note.id}'),
        borderRadius: BorderRadius.circular(WebTuiRadii.lg),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WebTuiSpacing.md,
            vertical: WebTuiSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WebTuiRadii.lg),
            border: Border.all(color: WebTuiColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
                  if (note.pinned) ...[
                    const SizedBox(width: WebTuiSpacing.xs),
                    Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: WebTuiColors.primary,
                      semanticLabel: tr('Đã ghim', 'Pinned'),
                    ),
                  ],
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: WebTuiSpacing.xs),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      [
                        formatMyNoteRelativeTime(note.updatedAt),
                        ?folderName,
                        if (note.isFromMessage)
                          tr('Từ tin nhắn', 'From a message'),
                        if (note.attachmentCount > 0)
                          tr(
                            '${note.attachmentCount} tệp',
                            '${note.attachmentCount} files',
                          ),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WebTuiTypography.labelSmall.copyWith(
                        color: WebTuiColors.textMuted,
                      ),
                    ),
                  ),
                  for (final tag in note.tags.take(2)) ...[
                    const SizedBox(width: WebTuiSpacing.xs),
                    MyNoteTagChip(tag: tag),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
