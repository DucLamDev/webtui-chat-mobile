import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/work_hub_providers.dart';
import '../widgets/shortcut_form_sheet.dart';
import '../widgets/work_common.dart';

/// Màn "Quản lý" lối tắt: kéo để sắp xếp, sửa, xoá.
class ShortcutsManageScreen extends ConsumerStatefulWidget {
  const ShortcutsManageScreen({required this.workspaceId, super.key});

  final String workspaceId;

  @override
  ConsumerState<ShortcutsManageScreen> createState() =>
      _ShortcutsManageScreenState();
}

class _ShortcutsManageScreenState extends ConsumerState<ShortcutsManageScreen> {
  List<AppShortcut>? _items;
  bool _busy = false;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _reload() async {
    _items = null;
    ref.invalidate(appShortcutsProvider(widget.workspaceId));
    if (mounted) setState(() {});
  }

  Future<void> _reorder(
    List<AppShortcut> current,
    int oldIndex,
    int newIndex,
  ) async {
    if (_busy) return;
    final next = [...current];
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() {
      _items = next;
      _busy = true;
    });
    final result = await ref
        .read(reorderAppShortcutsUseCaseProvider)
        .execute(
          workspaceId: widget.workspaceId,
          ids: [for (final item in next) item.id],
        );
    if (!mounted) return;
    final failure = result.failureOrNull;
    setState(() {
      _busy = false;
      if (failure != null) _items = current;
    });
    if (failure != null) {
      _snack(failure.message);
    } else {
      ref.invalidate(appShortcutsProvider(widget.workspaceId));
    }
  }

  Future<void> _edit(AppShortcut? shortcut) async {
    final saved = await showShortcutFormSheet(
      context,
      workspaceId: widget.workspaceId,
      shortcut: shortcut,
    );
    if (saved == true) await _reload();
  }

  Future<void> _delete(AppShortcut shortcut) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => WebTuiDialog(
        title: 'Xoá lối tắt?',
        message: 'Lối tắt "${shortcut.title}" sẽ biến mất với mọi người.',
        icon: WebTuiIcons.delete,
        tone: WebTuiDialogTone.danger,
        actions: [
          WebTuiDialogAction(
            label: 'Huỷ',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WebTuiDialogAction(
            key: const Key('shortcut_delete_confirm'),
            label: 'Xoá',
            primary: true,
            destructive: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(deleteAppShortcutUseCaseProvider)
        .execute(workspaceId: widget.workspaceId, shortcutId: shortcut.id);
    if (!mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      _snack(failure.message);
      return;
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appShortcutsProvider(widget.workspaceId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý lối tắt'),
        actions: [
          IconButton(
            key: const Key('shortcut_add'),
            tooltip: 'Thêm lối tắt',
            icon: const Icon(WebTuiIcons.add),
            onPressed: () => _edit(null),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                WorkSkeleton(height: 64, radius: 16),
                SizedBox(height: 10),
                WorkSkeleton(height: 64, radius: 16),
              ],
            ),
          ),
          error: (error, _) => Center(
            child: WorkErrorBox(
              message: workHubErrorText(error),
              onRetry: _reload,
            ),
          ),
          data: (data) {
            if (!data.canManage) {
              return const WorkEmptyBox(
                icon: WebTuiIcons.settings,
                message: 'Chỉ quản trị viên mới được quản lý lối tắt.',
              );
            }
            final items = _items ?? data.shortcuts;
            if (items.isEmpty) {
              return const WorkEmptyBox(
                icon: WebTuiIcons.externalLink,
                message: 'Chưa có lối tắt',
              );
            }
            return ReorderableListView.builder(
              key: const Key('shortcut_reorder_list'),
              padding: const EdgeInsets.all(16),
              buildDefaultDragHandles: false,
              itemCount: items.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _reorder(items, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final item = items[index];
                final colors = webTuiShortcutColors(item.color);
                return Padding(
                  key: ValueKey(item.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: WorkCard(
                    radius: 16,
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Row(
                      children: [
                        WorkIconBox(
                          icon: webTuiShortcutIcon(item.icon),
                          size: 44,
                          radius: 13,
                          background: colors.background,
                          foreground: colors.foreground,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WebTuiTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: WebTuiColors.textPrimary,
                                ),
                              ),
                              Text(
                                item.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WebTuiTypography.bodySmall.copyWith(
                                  color: WebTuiColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: Key('shortcut_edit_${item.id}'),
                          tooltip: 'Sửa',
                          icon: const Icon(WebTuiIcons.edit, size: 20),
                          onPressed: () => _edit(item),
                        ),
                        IconButton(
                          key: Key('shortcut_delete_${item.id}'),
                          tooltip: 'Xoá',
                          icon: const Icon(
                            WebTuiIcons.delete,
                            size: 20,
                            color: WebTuiColors.danger,
                          ),
                          onPressed: () => _delete(item),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(
                              WebTuiIcons.dragHandle,
                              color: WebTuiColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
