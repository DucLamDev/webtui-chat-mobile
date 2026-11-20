import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_note_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../controllers/ide_more_controllers.dart';
import '../../widgets/ide_wb.dart';
import 'ide_more_common.dart';
import 'ide_note_screen.dart';

/// Ghi chú dự án: danh sách, tạo mới, khôi phục ghi chú đã xoá.
class IdeNotesScreen extends ConsumerWidget {
  const IdeNotesScreen({this.project, super.key});

  final String? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(ideMoreServiceProvider);
    return IdeMorePage(
      title: tr('Ghi chú dự án', 'Project notes'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) => IdeLoader<IdeNoteList>(
          load: () => service.notes(p.name),
          builder: (context, list, reload) =>
              _NotesBody(project: p.name, list: list, reload: reload),
        ),
      ),
    );
  }
}

class _NotesBody extends ConsumerStatefulWidget {
  const _NotesBody({
    required this.project,
    required this.list,
    required this.reload,
  });

  final String project;
  final IdeNoteList list;
  final Future<void> Function() reload;

  @override
  ConsumerState<_NotesBody> createState() => _NotesBodyState();
}

class _NotesBodyState extends ConsumerState<_NotesBody> {
  String get project => widget.project;
  IdeNoteList get list => widget.list;
  Future<void> Function() get reload => widget.reload;
  bool _restoring = false;

  Future<void> _create(BuildContext context) async {
    final created = await Navigator.of(
      context,
    ).push<bool>(IdePageRoute(builder: (_) => IdeNoteScreen(project: project)));
    if (created == true) await reload();
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    IdeDeletedNote d,
  ) async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      final ok = await showWebTuiConfirmDialog(
        context,
        title: tr('Khôi phục ghi chú?', 'Restore this note?'),
        message: ideVisibleText(d.title),
        confirmLabel: tr('Khôi phục', 'Restore'),
      );
      if (!ok || !context.mounted) return;
      await ref.read(ideMoreServiceProvider).restoreNote(project, d.id, d.n);
      await reload();
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ideMoreErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = IdeType.bodySmall.copyWith(color: IdeWb.text2);
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: reload,
          child: list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 320,
                      child: WebTuiEmptyState(
                        title: tr('Chưa có ghi chú', 'No notes'),
                        message: tr(
                          'Dự án này chưa có ghi chú. Bấm "Ghi chú mới" để tạo.',
                          'No notes yet. Tap "New note" to create one.',
                        ),
                        icon: Icons.sticky_note_2_outlined,
                      ),
                    ),
                  ],
                )
              : ListView(
                  key: const Key('ide_notes_list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    WebTuiSpacing.lg,
                    WebTuiSpacing.sm,
                    WebTuiSpacing.lg,
                    96,
                  ),
                  children: [
                    for (final n in list.notes)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: WebTuiSpacing.sm,
                        ),
                        child: IdeCard(
                          key: Key('ide_note_${n.id}'),
                          onTap: () async {
                            await context.push(
                              Uri(
                                path: '/ide/notes/${n.id}',
                                queryParameters: {'project': project},
                              ).toString(),
                            );
                            if (context.mounted) await reload();
                          },
                          child: Row(
                            children: [
                              Icon(
                                n.isDiagram
                                    ? Icons.account_tree_outlined
                                    : Icons.sticky_note_2_outlined,
                                color: IdeWb.text,
                              ),
                              const SizedBox(width: WebTuiSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      n.title.isEmpty
                                          ? tr('(chưa đặt tên)', '(untitled)')
                                          : ideVisibleText(n.title),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: IdeType.titleMedium.copyWith(
                                        color: IdeWb.textStrong,
                                      ),
                                    ),
                                    Text(
                                      [
                                        if (n.isDiagram) tr('Sơ đồ', 'Diagram'),
                                        if (n.updatedBy.isNotEmpty) n.updatedBy,
                                        if (n.updatedAt != null)
                                          ideFormatDateTime(n.updatedAt!),
                                      ].join(' · '),
                                      style: muted,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (list.deleted.isNotEmpty) ...[
                      const SizedBox(height: WebTuiSpacing.md),
                      Text(
                        tr('Đã xoá gần đây', 'Recently deleted'),
                        style: IdeType.titleMedium.copyWith(
                          color: IdeWb.textStrong,
                        ),
                      ),
                      for (final d in list.deleted)
                        ListTile(
                          key: Key('ide_note_deleted_${d.id}'),
                          contentPadding: EdgeInsets.zero,
                          minVerticalPadding: 12,
                          title: Text(ideVisibleText(d.title)),
                          subtitle: Text(
                            [
                              if (d.by.isNotEmpty) ideVisibleText(d.by),
                              if (d.at != null) ideFormatDateTime(d.at!),
                            ].join(' · '),
                          ),
                          trailing: TextButton(
                            onPressed: _restoring
                                ? null
                                : () => _restore(context, ref, d),
                            child: Text(tr('Khôi phục', 'Restore')),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
        if (!list.full)
          Positioned(
            right: WebTuiSpacing.lg,
            bottom: WebTuiSpacing.lg,
            child: FloatingActionButton.extended(
              key: const Key('ide_note_new'),
              onPressed: () => _create(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Ghi chú mới', 'New note')),
            ),
          ),
      ],
    );
  }
}
