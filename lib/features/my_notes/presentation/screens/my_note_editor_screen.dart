import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../domain/entities/my_note.dart';
import '../../domain/markdown/my_note_markdown_format.dart';
import '../controllers/my_note_editor_controller.dart';
import '../controllers/my_notes_access_provider.dart';
import '../controllers/my_notes_list_controller.dart';
import '../widgets/my_note_markdown_view.dart';
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
            ? WebTuiEmptyState(
                title: tr('My Note chưa được bật', 'My Note isn\'t enabled'),
                message: myNotesDisabledMessage,
                icon: Icons.sticky_note_2_outlined,
              )
            : WebTuiEmptyState(
                title: tr('Chưa chọn workspace', 'No workspace selected'),
                message: tr(
                  'Chọn workspace trước khi mở My Note.',
                  'Select a workspace before opening My Note.',
                ),
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

    final title = state.isNew
        ? tr('Ghi chú mới', 'New note')
        : tr('Ghi chú', 'Note');
    return PopScope(
      canPop: !_isDirty() || state.isBusy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmMyNoteAction(
          context,
          title: tr('Bỏ thay đổi?', 'Discard changes?'),
          message: tr(
            'Nội dung bạn vừa soạn chưa được lưu.',
            'What you just wrote hasn\'t been saved.',
          ),
          confirmLabel: tr('Bỏ thay đổi', 'Discard changes'),
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
              : Text(tr('Lưu', 'Save')),
        ),
      ];
    }
    final readOnly = state.isOffline || state.isBusy;
    return [
      IconButton(
        key: const Key('my_note_edit'),
        tooltip: tr('Sửa ghi chú', 'Edit note'),
        icon: const Icon(Icons.edit_outlined),
        onPressed: readOnly
            ? () => showMyNoteSnack(
                context,
                tr(
                  'Bạn đang ngoại tuyến. Kết nối lại để sửa ghi chú.',
                  'You\'re offline. Reconnect to edit notes.',
                ),
              )
            : () => setState(() => _editing = true),
      ),
      IconButton(
        tooltip: tr('Xoá ghi chú', 'Delete note'),
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
      return WebTuiEmptyState(
        title: tr('My Note chưa được bật', 'My Note isn\'t enabled'),
        message: myNotesDisabledMessage,
        icon: Icons.sticky_note_2_outlined,
      );
    }
    if (!state.isNew || widget.editorKey.noteId != null) {
      if (state.note == null && state.errorMessage != null) {
        return WebTuiErrorState(
          title: state.notFound
              ? tr('Không tìm thấy ghi chú', 'Note not found')
              : tr('Chưa tải được ghi chú', 'Couldn\'t load the note'),
          message: state.errorMessage!,
          onRetry: state.notFound ? null : () => unawaited(controller.load()),
        );
      }
      if (state.note == null) {
        return WebTuiLoadingState(
          message: tr('Đang tải ghi chú...', 'Loading note...'),
        );
      }
    }
    final note = state.note;
    final banners = <Widget>[
      if (state.isOffline) const MyNotesOfflineBanner(),
      if (state.conflict)
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
                child: Text(tr('Sao chép nội dung', 'Copy content')),
              ),
              FilledButton(
                key: const Key('my_note_reload_latest'),
                onPressed: () {
                  _forceFill = true;
                  unawaited(controller.reloadLatest());
                },
                child: Text(tr('Tải bản mới nhất', 'Load latest version')),
              ),
            ],
          ),
        )
      else if (state.saveErrorMessage != null)
        MyNotesNotice(
          icon: Icons.error_outline_rounded,
          color: WebTuiColors.danger,
          message: state.saveErrorMessage!,
        ),
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
              WebTuiSpacing.lg,
              WebTuiSpacing.xl,
            ),
            children: [
              for (final banner in banners) ...[
                banner,
                const SizedBox(height: WebTuiSpacing.md),
              ],
              if (_editing)
                ..._editFields(state)
              else if (note != null)
                ..._viewFields(context, state, note, controller),
            ],
          ),
        ),
        if (_editing) _FormatToolbar(onFormat: _format),
      ],
    );
  }

  void _format(MyNoteFormat format) {
    final selection = _body.selection;
    final result = applyMyNoteFormat(
      format,
      _body.text,
      selection.start,
      selection.end,
    );
    _body.value = TextEditingValue(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.start,
        extentOffset: result.end,
      ),
    );
    setState(() {});
  }

  List<MyNoteFolderNode> _folderNodes(MyNoteEditorState state) =>
      flattenMyNoteFolderTree(buildMyNoteFolderTree(state.folders));

  String? _folderName(MyNoteEditorState state, String? id) {
    if (id == null) return null;
    for (final folder in state.folders) {
      if (folder.id == id) return folder.name;
    }
    return null;
  }

  Future<void> _pickFolder(MyNoteEditorState state) async {
    final nodes = _folderNodes(state);
    final picked = await showWebTuiSheet<_FolderPick>(
      context: context,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
        ),
        child: ListView(
          key: const Key('my_note_folder_picker'),
          shrinkWrap: true,
          children: [
            WebTuiSheetHeader(title: tr('Chọn thư mục', 'Choose folder')),
            WebTuiSheetActionTile(
              icon: WebTuiIcons.file,
              title: tr('Chưa xếp thư mục', 'No folder'),
              selected: _folderId == null,
              onTap: () =>
                  Navigator.of(sheetContext).pop(const _FolderPick(null)),
            ),
            for (final node in nodes)
              Padding(
                padding: EdgeInsets.only(left: (node.depth - 1) * 16.0),
                child: WebTuiSheetActionTile(
                  icon: WebTuiIcons.folderOpen,
                  title: node.folder.name,
                  selected: _folderId == node.folder.id,
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_FolderPick(node.folder.id)),
                ),
              ),
            const SizedBox(height: WebTuiSpacing.sm),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _folderId = picked.id);
  }

  Future<void> _editTags() async {
    final value = await showMyNoteTextDialog(
      context,
      title: 'Tag',
      label: tr('Tag, cách nhau bằng dấu phẩy', 'Tags, separated by commas'),
      confirmLabel: 'Xong',
      initialValue: _tags.text,
      maxLength: 300,
    );
    if (value != null && mounted) setState(() => _tags.text = value.trim());
  }

  List<Widget> _editFields(MyNoteEditorState state) {
    final folderIds = {for (final node in _folderNodes(state)) node.folder.id};
    final folderName = folderIds.contains(_folderId)
        ? _folderName(state, _folderId)
        : null;
    final tagText = _tags.text.trim();
    return [
      TextField(
        key: const Key('my_note_title_field'),
        controller: _title,
        maxLength: MyNoteLimits.titleMaxLength,
        maxLines: null,
        textInputAction: TextInputAction.next,
        style: WebTuiTypography.titleLarge.copyWith(
          color: WebTuiColors.textPrimary,
          fontSize: 24,
        ),
        decoration: InputDecoration(
          hintText: tr('Tiêu đề', 'Title'),
          border: InputBorder.none,
          counterText: '',
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: WebTuiSpacing.xs),
      SingleChildScrollView(
        key: const Key('my_note_meta_row'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ActionChip(
              key: const Key('my_note_folder_chip'),
              avatar: const Icon(Icons.folder_outlined, size: 18),
              label: Text(folderName ?? tr('Chưa xếp thư mục', 'No folder')),
              onPressed: () => unawaited(_pickFolder(state)),
            ),
            const SizedBox(width: WebTuiSpacing.xs),
            ActionChip(
              key: const Key('my_note_tags_chip'),
              avatar: const Icon(Icons.sell_outlined, size: 18),
              label: Text(
                tagText.isEmpty ? tr('Thêm tag', 'Add tag') : tagText,
              ),
              onPressed: () => unawaited(_editTags()),
            ),
            const SizedBox(width: WebTuiSpacing.xs),
            FilterChip(
              key: const Key('my_note_pin_chip'),
              avatar: Icon(
                _pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                size: 18,
              ),
              label: Text(tr('Ghim', 'Pin')),
              selected: _pinned,
              showCheckmark: false,
              onSelected: (value) => setState(() => _pinned = value),
            ),
          ],
        ),
      ),
      const Divider(height: WebTuiSpacing.lg),
      TextField(
        key: const Key('my_note_body_field'),
        controller: _body,
        minLines: 12,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        style: WebTuiTypography.bodyMedium.copyWith(
          color: WebTuiColors.textPrimary,
          height: 1.5,
        ),
        decoration: InputDecoration(
          hintText: tr(
            'Viết ghi chú (hỗ trợ markdown)',
            'Write a note (markdown supported)',
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
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
    final folderName = _folderName(state, note.folderId);
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              note.displayTitle,
              style: WebTuiTypography.titleLarge.copyWith(
                color: WebTuiColors.textPrimary,
                fontSize: 24,
              ),
            ),
          ),
          if (note.pinned)
            Padding(
              padding: EdgeInsets.only(top: 6, left: WebTuiSpacing.xs),
              child: Icon(
                Icons.push_pin_rounded,
                size: 18,
                color: WebTuiColors.primary,
                semanticLabel: tr('Đã ghim', 'Pinned'),
              ),
            ),
        ],
      ),
      const SizedBox(height: WebTuiSpacing.xs),
      Text(
        [
          tr(
            'Sửa lúc ${formatMyNoteTime(note.updatedAt)}',
            'Edited ${formatMyNoteTime(note.updatedAt)}',
          ),
          folderName ?? tr('Chưa xếp thư mục', 'No folder'),
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
                    'title': tr('Tin nhắn gốc', 'Original message'),
                  },
                ).toString(),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: Text(tr('Mở tin nhắn gốc', 'Open original message')),
          ),
        ),
      ],
      const Divider(height: WebTuiSpacing.xl),
      if (note.body.trim().isEmpty)
        Text(
          tr('Ghi chú chưa có nội dung.', 'This note has no content yet.'),
          style: WebTuiTypography.bodyMedium.copyWith(
            color: WebTuiColors.textMuted,
          ),
        )
      else
        MyNoteMarkdownView(source: note.body),
      if (note.attachments.isNotEmpty) ...[
        const SizedBox(height: WebTuiSpacing.md),
        Text(
          tr('Tệp đính kèm', 'Attachment'),
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
                    tooltip: tr('Gỡ khỏi ghi chú', 'Remove from note'),
                    icon: const Icon(Icons.link_off_rounded),
                    onPressed: () async {
                      final removed = await controller.removeAttachment(
                        attachment.fileId,
                      );
                      if (removed && context.mounted) {
                        showMyNoteSnack(
                          context,
                          tr(
                            'Đã gỡ tệp khỏi ghi chú.',
                            'File removed from the note.',
                          ),
                        );
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
    if (context.mounted) {
      showMyNoteSnack(context, tr('Đã lưu ghi chú.', 'Note saved.'));
    }
  }

  Future<void> _delete(
    BuildContext context,
    MyNoteEditorController controller,
  ) async {
    final confirmed = await confirmMyNoteAction(
      context,
      title: tr('Xoá ghi chú?', 'Delete note?'),
      message: tr(
        'Ghi chú sẽ bị xoá khỏi My Note.',
        'The note will be removed from My Note.',
      ),
      confirmLabel: tr('Xoá', 'Delete'),
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
      showMyNoteSnack(context, tr('Đã xoá ghi chú.', 'Note deleted.'));
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
  if (bytes <= 0) return tr('Không rõ dung lượng', 'Size unknown');
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

final class _FolderPick {
  const _FolderPick(this.id);

  final String? id;
}

class _FormatToolbar extends StatelessWidget {
  const _FormatToolbar({required this.onFormat});

  final void Function(MyNoteFormat format) onFormat;

  @override
  Widget build(BuildContext context) {
    final items = <(MyNoteFormat, IconData, String)>[
      (MyNoteFormat.bold, Icons.format_bold_rounded, tr('In đậm', 'Bold')),
      (
        MyNoteFormat.italic,
        Icons.format_italic_rounded,
        tr('In nghiêng', 'Italic'),
      ),
      (MyNoteFormat.heading, Icons.title_rounded, tr('Tiêu đề', 'Title')),
      (
        MyNoteFormat.bullet,
        Icons.format_list_bulleted_rounded,
        tr('Danh sách', 'List'),
      ),
      (
        MyNoteFormat.checklist,
        Icons.checklist_rounded,
        tr('Việc cần làm', 'To-do'),
      ),
      (MyNoteFormat.code, Icons.code_rounded, tr('Mã', 'Code')),
    ];
    return Material(
      color: WebTuiColors.surface,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          child: Row(
            key: const Key('my_note_format_toolbar'),
            children: [
              for (final (format, icon, label) in items)
                Expanded(
                  child: IconButton(
                    key: Key('my_note_format_${format.name}'),
                    tooltip: label,
                    icon: Icon(icon),
                    onPressed: () => onFormat(format),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
