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
import '../../domain/markdown/my_note_line_ops.dart';
import '../../domain/my_note_editor_text.dart';
import '../controllers/my_note_editor_controller.dart';
import '../controllers/my_notes_access_provider.dart';
import '../controllers/my_notes_list_controller.dart';
import '../widgets/my_note_attachment_picker.dart';
import '../widgets/my_note_attachments_view.dart';
import '../widgets/my_note_rich_text_controller.dart';
import '../widgets/my_note_widgets.dart';
import 'my_notes_screen.dart';

/// Soạn một ghi chú kiểu app Ghi chú iPhone: một ô soạn duy nhất (dòng đầu là
/// tiêu đề), bấm vào là gõ, tự lưu; thanh định dạng nằm trên bàn phím.
/// [noteId] `new` (hoặc rỗng) = ghi chú mới.
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
        appBar: AppBar(title: Text(tr('Ghi chú', 'Notes'))),
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
  final _text = MyNoteRichTextController();
  final _focus = FocusNode(debugLabel: 'my_note_editor');
  late final AppLifecycleListener _lifecycle;

  bool _pinned = false;
  String? _folderId;

  /// Tag đặt từ trước, không nằm trong chữ dạng `#tag` (giữ khi lưu).
  List<String> _otherTags = const [];

  /// Đã nạp ghi chú vào ô soạn (chỉ nạp một lần, trừ khi tải bản mới nhất).
  bool _filled = false;

  /// Văn bản lần gần nhất đã hẹn lưu, để bỏ qua thay đổi chỉ là vùng chọn.
  String _lastText = '';

  /// Có thay đổi chưa chắc đã lưu: chặn vuốt / nút quay lại để lưu trước.
  bool _unsaved = false;
  bool _leaving = false;
  bool _formatPanel = false;

  MyNoteEditorController get _controller =>
      ref.read(myNoteEditorControllerProvider(widget.editorKey).notifier);

  @override
  void initState() {
    super.initState();
    final folder = widget.initialFolderId?.trim() ?? '';
    _folderId = folder.isEmpty ? null : folder;
    _text.addListener(_onTextChanged);
    _text.onChecklistToggled = () => _scheduleSave(immediately: true);
    _focus.addListener(_onFocusChanged);
    _lifecycle = AppLifecycleListener(
      onInactive: () => unawaited(_controller.flushAutosave()),
      onHide: () => unawaited(_controller.flushAutosave()),
    );
    ref.listenManual<MyNoteEditorState>(
      myNoteEditorControllerProvider(widget.editorKey),
      _onState,
      fireImmediately: true,
    );
    if (widget.editorKey.noteId == null) {
      _filled = true;
      // Ghi chú mới: mở bàn phím ngay như iPhone.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _text.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onState(MyNoteEditorState? previous, MyNoteEditorState next) {
    final note = next.note;
    _text.readOnly = next.isOffline || next.conflict;
    if (note != null && !_filled) _fill(note);
    final previousNote = previous?.note;
    if (note != null &&
        (previousNote == null ||
            previousNote.version != note.version ||
            previousNote.attachments.length != note.attachments.length)) {
      final listProvider = myNotesListControllerProvider(
        widget.editorKey.workspaceId,
      );
      if (ref.exists(listProvider)) {
        ref.read(listProvider.notifier).upsertNote(note);
      }
    }
  }

  void _fill(MyNote note) {
    final text = joinMyNoteEditorText(note.title, note.body);
    _otherTags = myNoteTagsOutsideText(note.tags, text);
    _pinned = note.pinned;
    _folderId = note.folderId;
    _lastText = text;
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _filled = true;
    _unsaved = false;
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    if (!_filled || _text.text == _lastText) return;
    _lastText = _text.text;
    _scheduleSave();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      _formatPanel = false;
      unawaited(_controller.flushAutosave());
    }
    if (mounted) setState(() {});
  }

  MyNoteDraft _draft({String? text}) => MyNoteDraft.fromEditorText(
    text ?? _text.text,
    otherTags: _otherTags,
    pinned: _pinned,
    folderId: _folderId,
  );

  void _scheduleSave({bool immediately = false}) {
    final state = ref.read(myNoteEditorControllerProvider(widget.editorKey));
    if (state.isOffline || state.conflict) return;
    _controller.scheduleAutosave(
      _draft(),
      delay: immediately ? Duration.zero : myNoteAutosaveDelay,
    );
    if (!_unsaved && mounted) setState(() => _unsaved = true);
  }

  Future<void> _flush() async {
    final ok = await _controller.flushAutosave();
    if (ok && mounted && _unsaved) setState(() => _unsaved = false);
  }

  /// Rời màn: lưu nốt; ghi chú cũ bị xoá hết chữ thì hỏi xoá hay giữ bản cũ.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final state = ref.read(myNoteEditorControllerProvider(widget.editorKey));
      final draft = _draft();
      if (draft.isEmpty && state.note != null && !state.isOffline) {
        final delete = await showWebTuiConfirmDialog(
          context,
          title: tr('Ghi chú trống', 'Empty note'),
          message: tr(
            'Bạn đã xoá hết chữ. Xoá luôn ghi chú này, hoặc giữ bản đã lưu trước đó?',
            'You removed all the text. Delete this note, or keep the last saved version?',
          ),
          confirmLabel: tr('Xoá ghi chú', 'Delete note'),
          cancelLabel: tr('Giữ bản đã lưu', 'Keep saved version'),
          destructive: true,
          icon: WebTuiIcons.delete,
        );
        if (!mounted) return;
        if (delete) {
          await _deleteAndClose(confirm: false);
          return;
        }
        _close();
        return;
      }
      final ok = await _controller.flushAutosave();
      if (!mounted) return;
      if (ok) {
        _close();
        return;
      }
      final latest = ref.read(myNoteEditorControllerProvider(widget.editorKey));
      final discard = await showWebTuiConfirmDialog(
        context,
        title: tr('Chưa lưu được ghi chú', 'Note not saved yet'),
        message:
            latest.saveErrorMessage ??
            tr(
              'Phần vừa soạn chưa gửi được lên máy chủ.',
              'Your latest changes haven\'t reached the server.',
            ),
        confirmLabel: tr('Thoát, bỏ phần chưa lưu', 'Leave without saving'),
        cancelLabel: tr('Ở lại', 'Stay'),
        destructive: true,
      );
      if (discard && mounted) _close();
    } finally {
      _leaving = false;
    }
  }

  void _close() {
    _unsaved = false;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      // pop() thẳng (không qua PopScope): đã lưu / người dùng đã chọn bỏ.
      navigator.pop();
    } else {
      context.go(
        Uri(
          path: '/my-notes',
          queryParameters: {'workspaceId': widget.editorKey.workspaceId},
        ).toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = myNoteEditorControllerProvider(widget.editorKey);
    final state = ref.watch(provider);
    final ready = _contentReady(state);
    return PopScope(
      canPop: !ready || !_unsaved || state.isOffline,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: WebTuiColors.page,
        appBar: AppBar(
          backgroundColor: WebTuiColors.page,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          leadingWidth: 132,
          leading: _BackToNotesButton(onPressed: () => unawaited(_leave())),
          actions: ready ? _actions(context, state) : const [],
        ),
        // Đáy: thanh công cụ / bảng Aa tự chừa vùng an toàn để nền kéo sát mép.
        body: SafeArea(
          top: false,
          bottom: false,
          child: _content(context, state),
        ),
      ),
    );
  }

  bool _contentReady(MyNoteEditorState state) {
    if (state.featureDisabled) return false;
    if (widget.editorKey.noteId == null) return true;
    return state.note != null;
  }

  List<Widget> _actions(BuildContext context, MyNoteEditorState state) {
    return [
      if (_focus.hasFocus)
        WebTuiHeaderTextButton(
          key: const Key('my_note_done'),
          label: tr('Xong', 'Done'),
          onPressed: () {
            _focus.unfocus();
            unawaited(_flush());
          },
        ),
      WebTuiHeaderIconButton(
        key: const Key('my_note_more'),
        icon: WebTuiIcons.more,
        tooltip: tr('Tuỳ chọn ghi chú', 'Note options'),
        onPressed: () => unawaited(_showMenu(context, state)),
      ),
      const SizedBox(width: WebTuiSpacing.xs),
    ];
  }

  Widget _content(BuildContext context, MyNoteEditorState state) {
    if (state.featureDisabled) {
      return WebTuiEmptyState(
        title: tr('My Note chưa được bật', 'My Note isn\'t enabled'),
        message: myNotesDisabledMessage,
        icon: Icons.sticky_note_2_outlined,
      );
    }
    if (widget.editorKey.noteId != null && state.note == null) {
      if (state.errorMessage != null) {
        return WebTuiErrorState(
          title: state.notFound
              ? tr('Không tìm thấy ghi chú', 'Note not found')
              : tr('Chưa tải được ghi chú', 'Couldn\'t load the note'),
          message: state.errorMessage!,
          onRetry: state.notFound ? null : () => unawaited(_controller.load()),
        );
      }
      return WebTuiLoadingState(
        message: tr('Đang tải ghi chú...', 'Loading note...'),
      );
    }
    final note = state.note;
    final readOnly = state.isOffline || state.conflict;
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
            runSpacing: WebTuiSpacing.xs,
            children: [
              TextButton(
                key: const Key('my_note_keep_mine'),
                onPressed: state.isBusy ? null : () => unawaited(_keepMine()),
                child: Text(tr('Giữ bản của tôi', 'Keep my version')),
              ),
              FilledButton(
                key: const Key('my_note_reload_latest'),
                onPressed: state.isBusy
                    ? null
                    : () {
                        _filled = false;
                        unawaited(_controller.reloadLatest());
                      },
                child: Text(tr('Tải bản mới nhất', 'Load latest version')),
              ),
            ],
          ),
        )
      else if (state.saveErrorMessage != null)
        MyNotesNotice(
          key: const Key('my_note_save_error'),
          icon: Icons.error_outline_rounded,
          color: WebTuiColors.danger,
          message: state.saveErrorMessage!,
        ),
    ];
    final updatedAt = note?.updatedAt.toLocal() ?? DateTime.now();
    return Column(
      children: [
        for (final banner in banners)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.xs,
              WebTuiSpacing.lg,
              WebTuiSpacing.xs,
            ),
            child: banner,
          ),
        Expanded(
          child: ListView(
            key: const Key('my_note_scroll'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, WebTuiSpacing.lg),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
                child: Text(
                  formatMyNoteEditorDate(updatedAt),
                  key: const Key('my_note_date'),
                  textAlign: TextAlign.center,
                  style: WebTuiTypography.labelSmall.copyWith(
                    color: WebTuiColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
              TextField(
                key: const Key('my_note_editor_field'),
                controller: _text,
                focusNode: _focus,
                readOnly: readOnly,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  MyNoteListInputFormatter(),
                  LengthLimitingTextInputFormatter(
                    MyNoteLimits.titleMaxLength +
                        1 +
                        MyNoteLimits.bodyMaxLength,
                  ),
                ],
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.textPrimary,
                  fontSize: 17,
                  height: 1.35,
                ),
                cursorColor: WebTuiColors.primary,
                decoration: InputDecoration(
                  hintText: tr('Tiêu đề', 'Title'),
                  hintStyle: WebTuiTypography.titleLarge.copyWith(
                    color: WebTuiColors.textMuted,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                  // Chữ nằm thẳng trên nền trang như app Ghi chú: bỏ khung / nền
                  // ô nhập mặc định của theme ở mọi trạng thái.
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  filled: false,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (note != null &&
                  (note.attachments.isNotEmpty || state.uploadingCount > 0))
                Padding(
                  padding: const EdgeInsets.only(top: WebTuiSpacing.lg),
                  child: MyNoteAttachmentsView(
                    key: const Key('my_note_attachments'),
                    workspaceId: widget.editorKey.workspaceId,
                    attachments: note.attachments,
                    uploadingCount: state.uploadingCount,
                    readOnly: state.isOffline,
                    onRemove: _removeAttachment,
                  ),
                ),
              if (note != null && note.isFromMessage)
                Padding(
                  padding: const EdgeInsets.only(top: WebTuiSpacing.md),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('my_note_open_source'),
                      onPressed: () => unawaited(_openSource(note)),
                      icon: Icon(WebTuiIcons.messages, size: 18),
                      label: Text(
                        tr('Mở tin nhắn gốc', 'Open original message'),
                      ),
                    ),
                  ),
                ),
              // Chạm vùng trống dưới chữ: con trỏ về cuối ghi chú như iPhone.
              GestureDetector(
                key: const Key('my_note_tail'),
                behavior: HitTestBehavior.opaque,
                onTap: readOnly ? null : _focusAtEnd,
                child: const SizedBox(height: 240),
              ),
            ],
          ),
        ),
        if (state.isOffline)
          SizedBox(height: MediaQuery.paddingOf(context).bottom)
        else
          TextFieldTapRegion(
            child: _formatPanel && _focus.hasFocus
                ? _FormatPanel(
                    controller: _text,
                    onClose: () => setState(() => _formatPanel = false),
                    onChanged: () => setState(() {}),
                  )
                : _EditorToolbar(
                    keyboardOpen: _focus.hasFocus,
                    enabled: !readOnly,
                    onFormat: _openFormatPanel,
                    onChecklist: _toggleChecklist,
                    onAttach: () => unawaited(_attach()),
                    onCompose: () => unawaited(_composeNew()),
                  ),
          ),
      ],
    );
  }

  void _focusAtEnd() {
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
    _focus.requestFocus();
  }

  void _openFormatPanel() {
    if (!_focus.hasFocus) _focusAtEnd();
    setState(() => _formatPanel = true);
  }

  void _toggleChecklist() {
    if (!_focus.hasFocus) _focusAtEnd();
    _text.applyEdit(toggleMyNoteChecklist(_text.edit));
  }

  Future<void> _keepMine() async {
    final saved = await _controller.saveOverwriting(_draft());
    if (saved != null && mounted) {
      setState(() => _unsaved = false);
      showMyNoteSnack(
        context,
        tr('Đã lưu bản của bạn.', 'Your version has been saved.'),
      );
    }
  }

  Future<void> _attach() async {
    final source = await showMyNoteAttachSourceSheet(context);
    if (source == null || !mounted) return;
    final files = await pickMyNoteAttachments(context, source);
    if (files.isEmpty || !mounted) return;
    final state = ref.read(myNoteEditorControllerProvider(widget.editorKey));
    if (state.note == null && _draft().isEmpty) {
      // Máy chủ cần có chữ: ghi chú mới chỉ có ảnh thì đặt sẵn tiêu đề.
      final title = tr('Ghi chú mới', 'New note');
      _lastText = title;
      _text.value = TextEditingValue(
        text: title,
        selection: TextSelection.collapsed(offset: title.length),
      );
    }
    final added = await _controller.addAttachments(files, draftIfNew: _draft());
    if (!mounted) return;
    if (added > 0) setState(() => _unsaved = _controller.hasPendingChanges);
  }

  Future<void> _removeAttachment(MyNoteAttachment attachment) async {
    final removed = await _controller.removeAttachment(attachment.fileId);
    if (removed && mounted) {
      showMyNoteSnack(
        context,
        tr('Đã gỡ tệp khỏi ghi chú.', 'File removed from the note.'),
      );
    }
  }

  Future<void> _openSource(MyNote note) async {
    await _flush();
    if (!mounted) return;
    await context.push(
      Uri(
        path: '/conversations/${note.sourceChannelId}',
        queryParameters: {
          'workspaceId': widget.editorKey.workspaceId,
          'messageId': note.sourceMessageId!,
          'title': tr('Tin nhắn gốc', 'Original message'),
        },
      ).toString(),
    );
  }

  Future<void> _composeNew() async {
    await _flush();
    if (!mounted) return;
    await context.push(
      myNoteLocation(
        workspaceId: widget.editorKey.workspaceId,
        noteId: 'new',
        folderId: _folderId,
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, MyNoteEditorState state) async {
    _focus.unfocus();
    final note = state.note;
    final editable = !state.isOffline && !state.conflict;
    final folderName = _folderName(state, _folderId);
    final action = await showWebTuiSheet<_MenuAction>(
      context: context,
      builder: (sheetContext) {
        void pick(_MenuAction value) => Navigator.of(sheetContext).pop(value);
        return SafeArea(
          top: false,
          child: Column(
            key: const Key('my_note_menu'),
            mainAxisSize: MainAxisSize.min,
            children: [
              WebTuiSheetHeader(title: tr('Ghi chú', 'Note')),
              if (editable)
                WebTuiSheetActionTile(
                  key: const Key('my_note_menu_pin'),
                  icon: _pinned ? WebTuiIcons.pinFilled : WebTuiIcons.pin,
                  title: _pinned
                      ? tr('Bỏ ghim', 'Unpin')
                      : tr('Ghim ghi chú', 'Pin note'),
                  onTap: () => pick(_MenuAction.pin),
                ),
              if (editable)
                WebTuiSheetActionTile(
                  key: const Key('my_note_menu_folder'),
                  icon: WebTuiIcons.folderOpen,
                  title: tr('Chuyển vào thư mục', 'Move to folder'),
                  subtitle: folderName ?? tr('Chưa xếp thư mục', 'No folder'),
                  onTap: () => pick(_MenuAction.folder),
                ),
              if (editable)
                WebTuiSheetActionTile(
                  key: const Key('my_note_menu_tags'),
                  icon: WebTuiIcons.tag,
                  title: tr('Tag', 'Tags'),
                  subtitle: _tagSummary(),
                  onTap: () => pick(_MenuAction.tags),
                ),
              WebTuiSheetActionTile(
                key: const Key('my_note_menu_copy'),
                icon: WebTuiIcons.copy,
                title: tr('Sao chép nội dung', 'Copy content'),
                onTap: () => pick(_MenuAction.copy),
              ),
              if (note != null && editable)
                WebTuiSheetActionTile(
                  key: const Key('my_note_menu_delete'),
                  icon: WebTuiIcons.delete,
                  title: tr('Xoá ghi chú', 'Delete note'),
                  tone: WebTuiDialogTone.danger,
                  onTap: () => pick(_MenuAction.delete),
                ),
              const SizedBox(height: WebTuiSpacing.sm),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _MenuAction.pin:
        setState(() => _pinned = !_pinned);
        _scheduleSave(immediately: true);
      case _MenuAction.folder:
        await _pickFolder(state);
      case _MenuAction.tags:
        await _editTags();
      case _MenuAction.copy:
        await Clipboard.setData(ClipboardData(text: _text.text));
        if (context.mounted) {
          showMyNoteSnack(context, tr('Đã sao chép.', 'Copied.'));
        }
      case _MenuAction.delete:
        await _deleteAndClose(confirm: true);
    }
  }

  String _tagSummary() {
    final tags = myNoteEditorTags(_text.text, _otherTags);
    if (tags.isEmpty) {
      return tr('Gõ #tag trong ghi chú để gắn tag', 'Type #tag in the note');
    }
    return tags.map((tag) => '#$tag').join(' ');
  }

  String? _folderName(MyNoteEditorState state, String? id) {
    if (id == null) return null;
    for (final folder in state.folders) {
      if (folder.id == id) return folder.name;
    }
    return null;
  }

  Future<void> _pickFolder(MyNoteEditorState state) async {
    final nodes = flattenMyNoteFolderTree(buildMyNoteFolderTree(state.folders));
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
    if (picked == null || !mounted || picked.id == _folderId) return;
    setState(() => _folderId = picked.id);
    _scheduleSave(immediately: true);
  }

  Future<void> _editTags() async {
    final value = await showMyNoteTextDialog(
      context,
      title: tr('Tag khác', 'Other tags'),
      label: tr(
        'Tag cách nhau bằng dấu phẩy. Gõ #tag ngay trong ghi chú cũng được.',
        'Tags separated by commas. You can also type #tag in the note.',
      ),
      confirmLabel: tr('Xong', 'Done'),
      initialValue: _otherTags.join(', '),
      maxLength: 300,
      icon: WebTuiIcons.tag,
    );
    if (value == null || !mounted) return;
    setState(
      () => _otherTags = mergeMyNoteTags(parseMyNoteTagInput(value), const []),
    );
    _scheduleSave(immediately: true);
  }

  Future<void> _deleteAndClose({required bool confirm}) async {
    if (confirm) {
      final confirmed = await confirmMyNoteAction(
        context,
        title: tr('Xoá ghi chú?', 'Delete note?'),
        message: tr(
          'Ghi chú sẽ bị xoá khỏi My Note.',
          'The note will be removed from My Note.',
        ),
        confirmLabel: tr('Xoá', 'Delete'),
      );
      if (!confirmed || !mounted) return;
    }
    final noteId = ref
        .read(myNoteEditorControllerProvider(widget.editorKey))
        .note
        ?.id;
    final deleted = await _controller.delete();
    if (!deleted || !mounted) return;
    final listProvider = myNotesListControllerProvider(
      widget.editorKey.workspaceId,
    );
    if (noteId != null && ref.exists(listProvider)) {
      ref.read(listProvider.notifier).removeNote(noteId);
    }
    showMyNoteSnack(context, tr('Đã xoá ghi chú.', 'Note deleted.'));
    _close();
  }
}

/// Ngày giờ ở đầu ghi chú (kiểu iPhone): "16 tháng 11, 2026 lúc 19:30".
String formatMyNoteEditorDate(DateTime value) {
  final local = value.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ];
  return tr(
    '${local.day} tháng ${local.month}, ${local.year} lúc $hh:$mm',
    '${months[local.month - 1]} ${local.day}, ${local.year} at $hh:$mm',
  );
}

enum _MenuAction { pin, folder, tags, copy, delete }

final class _FolderPick {
  const _FolderPick(this.id);

  final String? id;
}

/// Nút quay lại kiểu iPhone: mũi tên + chữ "Ghi chú".
class _BackToNotesButton extends StatelessWidget {
  const _BackToNotesButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr('Quay lại danh sách ghi chú', 'Back to notes'),
      excludeSemantics: true,
      child: InkWell(
        key: const Key('my_note_back'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 6),
              Icon(WebTuiIcons.back, size: 26, color: WebTuiColors.primary),
              Flexible(
                child: Text(
                  tr('Ghi chú', 'Notes'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    color: WebTuiColors.primary,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thanh công cụ dưới cùng (nằm ngay trên bàn phím khi đang gõ): Aa định
/// dạng, ô tick, máy ảnh / đính kèm; bên phải là soạn ghi chú mới.
class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.keyboardOpen,
    required this.enabled,
    required this.onFormat,
    required this.onChecklist,
    required this.onAttach,
    required this.onCompose,
  });

  final bool keyboardOpen;
  final bool enabled;
  final VoidCallback onFormat;
  final VoidCallback onChecklist;
  final VoidCallback onAttach;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.page,
        border: Border(
          top: BorderSide(color: WebTuiColors.hairline, width: 0.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: SizedBox(
          height: 48,
          child: Row(
            key: const Key('my_note_toolbar'),
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ToolbarButton(
                key: const Key('my_note_format_button'),
                icon: WebTuiIcons.textSize,
                tooltip: tr('Định dạng chữ', 'Text format'),
                onPressed: enabled ? onFormat : null,
              ),
              _ToolbarButton(
                key: const Key('my_note_checklist_button'),
                icon: WebTuiIcons.tasks,
                tooltip: tr('Danh sách việc (ô tick)', 'Checklist'),
                onPressed: enabled ? onChecklist : null,
              ),
              _ToolbarButton(
                key: const Key('my_note_attach_button'),
                icon: WebTuiIcons.camera,
                tooltip: tr('Thêm ảnh hoặc tệp', 'Add photo or file'),
                onPressed: enabled ? onAttach : null,
              ),
              if (!keyboardOpen)
                _ToolbarButton(
                  key: const Key('my_note_compose_button'),
                  icon: WebTuiIcons.compose,
                  tooltip: tr('Ghi chú mới', 'New note'),
                  onPressed: onCompose,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
      icon: Icon(icon, size: 24),
      color: WebTuiColors.primary,
      disabledColor: WebTuiColors.textMuted,
    );
  }
}

/// Bảng định dạng "Aa" (thay thanh công cụ khi mở, như iPhone): kiểu dòng,
/// đậm / nghiêng / gạch / mã, danh sách.
class _FormatPanel extends StatelessWidget {
  const _FormatPanel({
    required this.controller,
    required this.onClose,
    required this.onChanged,
  });

  final MyNoteRichTextController controller;
  final VoidCallback onClose;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final offset = controller.selection.isValid
        ? controller.selection.start
        : controller.text.length;
    final block = myNoteBlockStyleAt(controller.text, offset);
    final inline = myNoteInlineStylesAt(controller.text, offset);

    void applyBlock(MyNoteBlockStyle style) {
      controller.applyEdit(setMyNoteBlockStyle(controller.edit, style));
      onChanged();
    }

    void applyInline(MyNoteInlineStyle style) {
      controller.applyEdit(toggleMyNoteInlineStyle(controller.edit, style));
      onChanged();
    }

    final styles = <(MyNoteBlockStyle, String, TextStyle)>[
      (
        MyNoteBlockStyle.title,
        tr('Tiêu đề', 'Title'),
        const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      (
        MyNoteBlockStyle.heading,
        tr('Đề mục', 'Heading'),
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      (
        MyNoteBlockStyle.subheading,
        tr('Đề mục phụ', 'Subheading'),
        const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      (
        MyNoteBlockStyle.body,
        tr('Nội dung', 'Body'),
        const TextStyle(fontSize: 15),
      ),
      (
        MyNoteBlockStyle.monospace,
        tr('Đơn cách', 'Monostyled'),
        const TextStyle(
          fontSize: 14,
          fontFamilyFallback: ['Menlo', 'Courier', 'monospace'],
        ),
      ),
    ];
    return DecoratedBox(
      key: const Key('my_note_format_panel'),
      decoration: BoxDecoration(
        color: WebTuiColors.groupBackground,
        border: Border(
          top: BorderSide(color: WebTuiColors.hairline, width: 0.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          6,
          12,
          10 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Định dạng', 'Format'),
                    style: WebTuiTypography.titleMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('my_note_format_close'),
                  tooltip: tr('Đóng', 'Close'),
                  onPressed: onClose,
                  icon: Icon(WebTuiIcons.close, size: 20),
                  color: WebTuiColors.textSecondary,
                ),
              ],
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (style, label, textStyle) in styles)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _PanelChip(
                        key: Key('my_note_style_${style.name}'),
                        selected: block == style,
                        onTap: () => applyBlock(style),
                        child: Text(
                          label,
                          style: textStyle.copyWith(
                            color: block == style
                                ? WebTuiColors.textOnPrimary
                                : WebTuiColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (style, icon, label)
                    in <(MyNoteInlineStyle, IconData, String)>[
                      (
                        MyNoteInlineStyle.bold,
                        Icons.format_bold_rounded,
                        tr('Đậm', 'Bold'),
                      ),
                      (
                        MyNoteInlineStyle.italic,
                        Icons.format_italic_rounded,
                        tr('Nghiêng', 'Italic'),
                      ),
                      (
                        MyNoteInlineStyle.strikethrough,
                        Icons.format_strikethrough_rounded,
                        tr('Gạch ngang', 'Strikethrough'),
                      ),
                      (
                        MyNoteInlineStyle.code,
                        Icons.code_rounded,
                        tr('Mã', 'Code'),
                      ),
                    ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _PanelChip(
                        key: Key('my_note_inline_${style.name}'),
                        selected: inline.contains(style),
                        semanticLabel: label,
                        onTap: () => applyInline(style),
                        child: Icon(
                          icon,
                          color: inline.contains(style)
                              ? WebTuiColors.textOnPrimary
                              : WebTuiColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (style, icon, label)
                    in <(MyNoteBlockStyle, IconData, String)>[
                      (
                        MyNoteBlockStyle.bullet,
                        Icons.format_list_bulleted_rounded,
                        tr('Danh sách chấm', 'Bulleted list'),
                      ),
                      (
                        MyNoteBlockStyle.numbered,
                        Icons.format_list_numbered_rounded,
                        tr('Danh sách số', 'Numbered list'),
                      ),
                      (
                        MyNoteBlockStyle.checklist,
                        WebTuiIcons.tasks,
                        tr('Danh sách việc', 'Checklist'),
                      ),
                      (
                        MyNoteBlockStyle.quote,
                        Icons.format_quote_rounded,
                        tr('Trích dẫn', 'Block quote'),
                      ),
                    ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _PanelChip(
                        key: Key('my_note_style_${style.name}'),
                        selected: block == style,
                        semanticLabel: label,
                        onTap: () => applyBlock(style),
                        child: Icon(
                          icon,
                          color: block == style
                              ? WebTuiColors.textOnPrimary
                              : WebTuiColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelChip extends StatelessWidget {
  const _PanelChip({
    required this.selected,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    super.key,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: selected ? WebTuiColors.primaryFill : WebTuiColors.page,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(widthFactor: 1, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
