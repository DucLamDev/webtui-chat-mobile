import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/my_note.dart';
import '../controllers/my_note_editor_controller.dart';
import '../controllers/my_notes_access_provider.dart';
import '../controllers/my_notes_list_controller.dart';
import '../widgets/my_note_widgets.dart';
import 'my_notes_screen.dart';

/// Xem / soạn một ghi chú. [noteId] `new` (hoặc rỗng) = ghi chú mới.
class MyNoteEditorScreen extends ConsumerWidget {
  const MyNoteEditorScreen({
    required this.noteId,
    this.workspaceId,
    this.initialFolderId,
    super.key,
  });

  final String noteId;
  final String? workspaceId;
  final String? initialFolderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(myNotesEnabledProvider);
    final ws = resolveMyNotesWorkspaceId(ref, workspaceId);
    final id = noteId.trim();
    final isNew = id.isEmpty || id == 'new';
    if (!enabled || ws.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Note')),
        body: !enabled
            ? const WebTuiEmptyState(
                title: 'My Note chưa được bật',
                message: myNotesDisabledMessage,
                icon: Icons.sticky_note_2_outlined,
              )
            : const WebTuiEmptyState(
                title: 'Chưa chọn workspace',
                message: 'Chọn workspace trước khi mở My Note.',
                icon: Icons.sticky_note_2_outlined,
              ),
      );
    }
    return _MyNoteEditorView(
      editorKey: (workspaceId: ws, noteId: isNew ? null : id),
      initialFolderId: initialFolderId,
    );
  }
}

class _MyNoteEditorView extends ConsumerStatefulWidget {
  const _MyNoteEditorView({required this.editorKey, this.initialFolderId});

  final MyNoteEditorKey editorKey;
  final String? initialFolderId;

  @override
  ConsumerState<_MyNoteEditorView> createState() => _MyNoteEditorViewState();
}

class _MyNoteEditorViewState extends ConsumerState<_MyNoteEditorView> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tags = TextEditingController();
  bool _pinned = false;
  String? _folderId;
  late bool _editing = widget.editorKey.noteId == null;

  /// Bản đã nạp vào ô soạn; so với bản này để biết có thay đổi chưa lưu.
  MyNote? _loadedNote;

  /// Bấm "Tải bản mới nhất": nạp đè cả khi đang có chữ chưa lưu.
  bool _forceFill = false;

  @override
  void initState() {
    super.initState();
    final folder = widget.initialFolderId?.trim() ?? '';
    _folderId = folder.isEmpty ? null : folder;
    ref.listenManual<MyNoteEditorState>(
      myNoteEditorControllerProvider(widget.editorKey),
      (_, next) => _onState(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _onState(MyNoteEditorState state) {
    final note = state.note;
    if (note == null) return;
    final loaded = _loadedNote;
    if (loaded != null &&
        loaded.id == note.id &&
        loaded.version == note.version) {
      return;
    }
    // Không đè chữ đang gõ dở, trừ khi người dùng chủ động tải bản mới nhất.
    if (_editing && !_forceFill && loaded != null && _isDirty()) return;
    _forceFill = false;
    _fill(note);
    if (mounted) setState(() {});
  }

  void _fill(MyNote note) {
    _title.text = note.title;
    _body.text = note.body;
    _tags.text = note.tags.join(', ');
    _pinned = note.pinned;
    _folderId = note.folderId;
    _loadedNote = note;
  }

  bool _isDirty() {
    if (!_editing) return false;
    final note = _loadedNote;
    if (note == null) {
      return _title.text.trim().isNotEmpty ||
          _body.text.trim().isNotEmpty ||
          _tags.text.trim().isNotEmpty;
    }
    return _title.text.trim() != note.title ||
        _body.text != note.body ||
        _tags.text.trim() != note.tags.join(', ') ||
        _pinned != note.pinned ||
        _folderId != note.folderId;
  }

  @override
  Widget build(BuildContext context) {
    final provider = myNoteEditorControllerProvider(widget.editorKey);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final note = state.note;

    final title = state.isNew ? 'Ghi chú mới' : 'Ghi chú';
    return PopScope(
      canPop: !_isDirty() || state.isBusy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmMyNoteAction(
          context,
          title: 'Bỏ thay đổi?',
          message: 'Nội dung bạn vừa soạn chưa được lưu.',
          confirmLabel: 'Bỏ thay đổi',
        );
        if (leave && context.mounted) {
          setState(() => _editing = false);
          if (note != null) _fill(note);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: WebTuiColors.background,
        appBar: AppBar(
          title: Text(title),
          surfaceTintColor: Colors.transparent,
          actions: _actions(context, state, controller),
        ),
        body: SafeArea(top: false, child: _content(context, state, controller)),
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    MyNoteEditorState state,
    MyNoteEditorController controller,
  ) {
    if (state.featureDisabled || state.errorMessage != null) return const [];
    if (state.isLoading && state.note == null && !state.isNew) {
      return const [];
    }
    if (_editing) {
      return [
        TextButton(
          key: const Key('my_note_save'),
          onPressed: state.isBusy || state.conflict
              ? null
              : () => _save(context, controller),
          child: state.isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Lưu'),
        ),
      ];
    }
    final readOnly = state.isOffline || state.isBusy;
    return [
      IconButton(
        key: const Key('my_note_edit'),
        tooltip: 'Sửa ghi chú',
        icon: const Icon(Icons.edit_outlined),
        onPressed: readOnly
            ? () => showMyNoteSnack(
                context,
                'Bạn đang ngoại tuyến. Kết nối lại để sửa ghi chú.',
              )
            : () => setState(() => _editing = true),
      ),
      IconButton(
        tooltip: 'Xoá ghi chú',
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: readOnly ? null : () => _delete(context, controller),
      ),
    ];
  }

  Widget _content(
    BuildContext context,
    MyNoteEditorState state,
    MyNoteEditorController controller,
  ) {
    if (state.featureDisabled) {
      return const WebTuiEmptyState(
        title: 'My Note chưa được bật',
        message: myNotesDisabledMessage,
        icon: Icons.sticky_note_2_outlined,
      );
    }
    if (!state.isNew || widget.editorKey.noteId != null) {
      if (state.note == null && state.errorMessage != null) {
        return WebTuiErrorState(
          title: state.notFound
              ? 'Không tìm thấy ghi chú'
              : 'Chưa tải được ghi chú',
          message: state.errorMessage!,
          onRetry: state.notFound ? null : () => unawaited(controller.load()),
        );
      }
      if (state.note == null) {
        return const WebTuiLoadingState(message: 'Đang tải ghi chú...');
      }
    }
    final note = state.note;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.lg,
        WebTuiSpacing.md,
        WebTuiSpacing.lg,
        WebTuiSpacing.xl,
      ),
      children: [
        if (state.isOffline) ...[
          const MyNotesOfflineBanner(),
          const SizedBox(height: WebTuiSpacing.md),
        ],
        if (state.conflict) ...[
          MyNotesNotice(
            key: const Key('my_note_conflict'),
            icon: Icons.sync_problem_rounded,
            color: WebTuiColors.danger,
            message: myNoteConflictMessage,
            action: Wrap(
              spacing: WebTuiSpacing.xs,
              children: [
                TextButton(
                  onPressed: () => unawaited(
                    Clipboard.setData(ClipboardData(text: _body.text)),
                  ),
                  child: const Text('Sao chép nội dung'),
                ),
                FilledButton(
                  key: const Key('my_note_reload_latest'),
                  onPressed: () {
                    _forceFill = true;
                    unawaited(controller.reloadLatest());
                  },
                  child: const Text('Tải bản mới nhất'),
                ),
              ],
            ),
          ),
          const SizedBox(height: WebTuiSpacing.md),
        ] else if (state.saveErrorMessage != null) ...[
          MyNotesNotice(
            icon: Icons.error_outline_rounded,
            color: WebTuiColors.danger,
            message: state.saveErrorMessage!,
          ),
          const SizedBox(height: WebTuiSpacing.md),
        ],
        if (_editing)
          ..._editFields(state)
        else if (note != null)
          ..._viewFields(context, state, note, controller),
      ],
    );
  }

  List<Widget> _editFields(MyNoteEditorState state) {
    final folders = flattenMyNoteFolderTree(
      buildMyNoteFolderTree(state.folders),
    );
    final folderIds = {for (final node in folders) node.folder.id};
    final selectedFolder = folderIds.contains(_folderId) ? _folderId : null;
    return [
      TextField(
        key: const Key('my_note_title_field'),
        controller: _title,
        maxLength: MyNoteLimits.titleMaxLength,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Tiêu đề'),
        onChanged: (_) => setState(() {}),
      ),
      TextField(
        key: const Key('my_note_tags_field'),
        controller: _tags,
        decoration: const InputDecoration(
          labelText: 'Tag',
          hintText: 'việc nhà, ý tưởng (cách nhau bằng dấu phẩy)',
          prefixIcon: Icon(Icons.sell_outlined),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: WebTuiSpacing.sm),
      DropdownButtonFormField<String?>(
        key: ValueKey('folder_$selectedFolder'),
        initialValue: selectedFolder,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Thư mục',
          prefixIcon: Icon(Icons.folder_outlined),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Chưa xếp thư mục'),
          ),
          for (final node in folders)
            DropdownMenuItem<String?>(
              value: node.folder.id,
              child: Text(
                '${'  ' * (node.depth - 1)}${node.folder.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) => setState(() => _folderId = value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _pinned,
        title: const Text('Ghim lên đầu danh sách'),
        onChanged: (value) => setState(() => _pinned = value),
      ),
      TextField(
        key: const Key('my_note_body_field'),
        controller: _body,
        minLines: 10,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          labelText: 'Nội dung',
          hintText: 'Viết ghi chú (hỗ trợ cú pháp markdown)',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  List<Widget> _viewFields(
    BuildContext context,
    MyNoteEditorState state,
    MyNote note,
    MyNoteEditorController controller,
  ) {
    String? folderName;
    for (final folder in state.folders) {
      if (folder.id == note.folderId) folderName = folder.name;
    }
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.pinned) ...[
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(
                Icons.push_pin_rounded,
                size: 18,
                color: WebTuiColors.primary,
                semanticLabel: 'Đã ghim',
              ),
            ),
            const SizedBox(width: WebTuiSpacing.xs),
          ],
          Expanded(
            child: SelectableText(
              note.displayTitle,
              style: WebTuiTypography.titleLarge.copyWith(
                color: WebTuiColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: WebTuiSpacing.xs),
      Text(
        [
          'Sửa lúc ${formatMyNoteTime(note.updatedAt)}',
          folderName ?? 'Chưa xếp thư mục',
        ].join(' · '),
        style: WebTuiTypography.labelSmall.copyWith(
          color: WebTuiColors.textMuted,
        ),
      ),
      if (note.tags.isNotEmpty) ...[
        const SizedBox(height: WebTuiSpacing.sm),
        Wrap(
          spacing: WebTuiSpacing.xs,
          runSpacing: WebTuiSpacing.xs,
          children: [for (final tag in note.tags) MyNoteTagChip(tag: tag)],
        ),
      ],
      if (note.isFromMessage) ...[
        const SizedBox(height: WebTuiSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('my_note_open_source'),
            onPressed: () => unawaited(
              context.push(
                Uri(
                  path: '/conversations/${note.sourceChannelId}',
                  queryParameters: {
                    'workspaceId': widget.editorKey.workspaceId,
                    'messageId': note.sourceMessageId!,
                    'title': 'Tin nhắn gốc',
                  },
                ).toString(),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Mở tin nhắn gốc'),
          ),
        ),
      ],
      const SizedBox(height: WebTuiSpacing.md),
      Container(
        padding: const EdgeInsets.all(WebTuiSpacing.md),
        decoration: BoxDecoration(
          color: WebTuiColors.surface,
          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
          border: Border.all(color: WebTuiColors.border),
        ),
        child: SelectableText(
          note.body.isEmpty ? 'Ghi chú chưa có nội dung.' : note.body,
          style: WebTuiTypography.bodyMedium.copyWith(
            color: note.body.isEmpty
                ? WebTuiColors.textMuted
                : WebTuiColors.textPrimary,
            height: 1.45,
          ),
        ),
      ),
      if (note.attachments.isNotEmpty) ...[
        const SizedBox(height: WebTuiSpacing.md),
        Text(
          'Tệp đính kèm',
          style: WebTuiTypography.bodyMedium.copyWith(
            color: WebTuiColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        for (final attachment in note.attachments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.attach_file_rounded),
            title: Text(attachment.originalName),
            subtitle: Text(_formatBytes(attachment.byteSize)),
            trailing: state.isOffline
                ? null
                : IconButton(
                    tooltip: 'Gỡ khỏi ghi chú',
                    icon: const Icon(Icons.link_off_rounded),
                    onPressed: () async {
                      final removed = await controller.removeAttachment(
                        attachment.fileId,
                      );
                      if (removed && context.mounted) {
                        showMyNoteSnack(context, 'Đã gỡ tệp khỏi ghi chú.');
                      }
                    },
                  ),
          ),
      ],
    ];
  }

  Future<void> _save(
    BuildContext context,
    MyNoteEditorController controller,
  ) async {
    FocusScope.of(context).unfocus();
    final saved = await controller.save(
      MyNoteDraft(
        title: _title.text,
        body: _body.text,
        tagsInput: _tags.text,
        pinned: _pinned,
        folderId: _folderId,
      ),
    );
    if (saved == null || !mounted) return;
    _fill(saved);
    setState(() => _editing = false);
    final listProvider = myNotesListControllerProvider(
      widget.editorKey.workspaceId,
    );
    if (ref.exists(listProvider)) {
      ref.read(listProvider.notifier).upsertNote(saved);
    }
    if (context.mounted) showMyNoteSnack(context, 'Đã lưu ghi chú.');
  }

  Future<void> _delete(
    BuildContext context,
    MyNoteEditorController controller,
  ) async {
    final confirmed = await confirmMyNoteAction(
      context,
      title: 'Xoá ghi chú?',
      message: 'Ghi chú sẽ bị xoá khỏi My Note.',
      confirmLabel: 'Xoá',
    );
    if (!confirmed) return;
    final noteId = ref
        .read(myNoteEditorControllerProvider(widget.editorKey))
        .note
        ?.id;
    final deleted = await controller.delete();
    if (!deleted || !mounted) return;
    final listProvider = myNotesListControllerProvider(
      widget.editorKey.workspaceId,
    );
    if (noteId != null && ref.exists(listProvider)) {
      ref.read(listProvider.notifier).removeNote(noteId);
    }
    if (context.mounted) {
      showMyNoteSnack(context, 'Đã xoá ghi chú.');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(
          Uri(
            path: '/my-notes',
            queryParameters: {'workspaceId': widget.editorKey.workspaceId},
          ).toString(),
        );
      }
    }
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return 'Không rõ dung lượng';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
