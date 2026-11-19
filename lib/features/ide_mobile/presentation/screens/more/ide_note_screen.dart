import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_note_models.dart';
import '../../controllers/ide_more_controllers.dart';
import '../../widgets/markdown/ide_blocks_model.dart';
import '../../widgets/markdown/ide_diagram_view.dart';
import '../../widgets/markdown/ide_markdown.dart';
import 'ide_more_common.dart';

const _titleMax = 120;
const _bodyMax = 512 * 1024;

/// Xem / sửa / tạo một ghi chú. [noteId] null = tạo mới. Trả `true` (pop) khi
/// đã tạo hoặc xoá, để danh sách tải lại.
class IdeNoteScreen extends ConsumerStatefulWidget {
  const IdeNoteScreen({required this.project, this.noteId, super.key});

  final String project;
  final String? noteId;

  @override
  ConsumerState<IdeNoteScreen> createState() => _IdeNoteScreenState();
}

class _IdeNoteScreenState extends ConsumerState<IdeNoteScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  IdeNote? _note;
  Object? _error;
  bool _loading = false;
  bool _editing = false;
  bool _busy = false;
  String? _conflict;
  String? _formError;

  bool get _creating => widget.noteId == null;

  @override
  void initState() {
    super.initState();
    if (_creating) {
      _editing = true;
    } else {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _dirty {
    if (!_editing) return false;
    final n = _note;
    if (n == null) return _title.text.isNotEmpty || _body.text.isNotEmpty;
    return _title.text != n.title || _body.text != n.body;
  }

  Future<void> _load({bool keepText = false}) async {
    setState(() {
      _loading = _note == null;
      _error = null;
    });
    try {
      final n = await ref
          .read(ideMoreServiceProvider)
          .note(widget.project, widget.noteId!);
      if (!mounted) return;
      setState(() {
        _note = n;
        _loading = false;
        if (!keepText) {
          _title.text = n.title;
          _body.text = n.body;
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text;
    if (title.isEmpty) {
      setState(() => _formError = tr('Hãy nhập tiêu đề.', 'Enter a title.'));
      return;
    }
    if (title.length > _titleMax) {
      setState(
        () => _formError = tr(
          'Tiêu đề tối đa $_titleMax ký tự.',
          'Title is at most $_titleMax characters.',
        ),
      );
      return;
    }
    if (utf8.encode(body).length > _bodyMax) {
      setState(
        () => _formError = tr(
          'Nội dung quá dài (tối đa 512 KB).',
          'The note is too long (512 KB max).',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    final service = ref.read(ideMoreServiceProvider);
    try {
      if (_creating) {
        await service.createNote(widget.project, title, body);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final n = _note!;
      final sha = await service.saveNote(
        widget.project,
        n.id,
        n.sha,
        title,
        body,
      );
      if (!mounted) return;
      setState(() {
        _note = IdeNote(
          id: n.id,
          title: title,
          body: body,
          sha: sha,
          kind: n.kind,
          diagram: n.diagram,
          updatedAt: DateTime.now(),
          updatedBy: n.updatedBy,
          createdBy: n.createdBy,
        );
        _editing = false;
        _conflict = null;
        _busy = false;
      });
      _toast(tr('Đã lưu ghi chú', 'Note saved'));
    } on IdeConflict catch (e) {
      if (!mounted) return;
      // Giữ nguyên chữ đang gõ, chỉ báo và cho chọn cách xử lý.
      setState(() {
        _busy = false;
        _conflict = e.message.isNotEmpty
            ? e.message
            : tr(
                'Ghi chú vừa được sửa ở chỗ khác.',
                'The note was just edited elsewhere.',
              );
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _formError = ideMoreErrorText(e);
      });
    }
  }

  Future<void> _copyMine() async {
    await Clipboard.setData(
      ClipboardData(text: '${_title.text}\n\n${_body.text}'),
    );
    if (mounted) _toast(tr('Đã chép chữ của bạn', 'Your text was copied'));
  }

  /// Lấy bản mới nhất. [keepMine]: giữ chữ đang gõ nhưng dùng `sha` mới nên
  /// lần lưu sau sẽ ghi đè; ngược lại bỏ chữ đang gõ.
  Future<void> _takeLatest({required bool keepMine}) async {
    setState(() => _busy = true);
    try {
      final n = await ref
          .read(ideMoreServiceProvider)
          .note(widget.project, widget.noteId!);
      if (!mounted) return;
      setState(() {
        _note = n;
        _conflict = null;
        _busy = false;
        if (!keepMine) {
          _title.text = n.title;
          _body.text = n.body;
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(ideMoreErrorText(e));
    }
  }

  Future<bool> _confirmDiscard() => showWebTuiConfirmDialog(
    context,
    title: tr('Bỏ thay đổi chưa lưu?', 'Discard unsaved changes?'),
    message: tr(
      'Chữ bạn đã gõ sẽ mất nếu thoát bây giờ.',
      'Your typed text is lost if you leave now.',
    ),
    confirmLabel: tr('Bỏ thay đổi', 'Discard'),
    cancelLabel: tr('Ở lại', 'Stay'),
    destructive: true,
  );

  Future<void> _cancelEdit() async {
    if (_dirty && !await _confirmDiscard()) return;
    if (!mounted) return;
    if (_creating) {
      Navigator.of(context).pop();
      return;
    }
    final n = _note!;
    setState(() {
      _editing = false;
      _conflict = null;
      _formError = null;
      _title.text = n.title;
      _body.text = n.body;
    });
  }

  Future<void> _delete() async {
    final n = _note!;
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Xoá ghi chú này?', 'Delete this note?'),
      message: tr(
        'Ghi chú vào mục "Đã xoá gần đây", có thể khôi phục. IDE sẽ hỏi xác nhận bằng khoá của bạn.',
        'The note moves to "Recently deleted" and can be restored. The IDE will ask you to confirm with your key.',
      ),
      confirmLabel: tr('Xoá ghi chú', 'Delete'),
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ideMoreServiceProvider)
          .deleteNote(widget.project, n.id, n.sha);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(ideMoreErrorText(e));
    }
  }

  Future<void> _versions() async {
    final restored = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VersionsSheet(
        project: widget.project,
        noteId: _note!.id,
        canRestore: !_dirty,
      ),
    );
    if (restored == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final n = _note;
    final diagram = n?.isDiagram ?? false;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDiscard()) nav.pop();
      },
      child: IdeMorePage(
        title: _creating
            ? tr('Ghi chú mới', 'New note')
            : (n?.title.isNotEmpty ?? false)
            ? n!.title
            : tr('Ghi chú', 'Note'),
        actions: [
          if (n != null && !_editing) ...[
            if (!diagram)
              IconButton(
                key: const Key('ide_note_edit'),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                tooltip: tr('Sửa', 'Edit'),
                onPressed: _busy ? null : () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined),
              ),
            IconButton(
              key: const Key('ide_note_versions'),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: tr('Phiên bản cũ', 'Versions'),
              onPressed: _busy ? null : _versions,
              icon: const Icon(Icons.history_rounded),
            ),
            IconButton(
              key: const Key('ide_note_delete'),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: tr('Xoá', 'Delete'),
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ],
        body: _body_(n, diagram),
      ),
    );
  }

  Widget _body_(IdeNote? n, bool diagram) {
    if (!_creating && n == null) {
      return _loading
          ? WebTuiLoadingState(message: tr('Đang tải...', 'Loading...'))
          : IdeMoreErrorView(error: _error ?? const IdeError(), onRetry: _load);
    }
    if (_editing) return _editor();
    final spec = diagram ? _diagramSpec(n!.diagram) : null;
    return ListView(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      children: [
        Text(
          [
            if (n!.updatedBy.isNotEmpty) n.updatedBy,
            if (n.updatedAt != null) ideFormatDateTime(n.updatedAt!),
          ].join(' · '),
          style: WebTuiTypography.bodySmall.copyWith(
            color: WebTuiColors.textMuted,
          ),
        ),
        const SizedBox(height: WebTuiSpacing.sm),
        if (diagram) ...[
          IdeCard(
            child: Row(
              children: [
                Icon(
                  Icons.desktop_windows_outlined,
                  color: WebTuiColors.textSecondary,
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                Expanded(
                  child: Text(
                    tr(
                      'Sơ đồ chỉ sửa trên máy tính',
                      'Diagrams can only be edited on the computer',
                    ),
                    key: const Key('ide_note_diagram_hint'),
                  ),
                ),
              ],
            ),
          ),
          if (spec != null) IdeDiagramView(spec: spec),
        ] else
          IdeMarkdown(text: n.body),
      ],
    );
  }

  IdeDiagramSpec? _diagramSpec(Object? raw) {
    if (raw is! Map) return null;
    try {
      return parseIdeDiagram(jsonEncode(raw));
    } on Object {
      return null;
    }
  }

  Widget _editor() {
    return Padding(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      child: Column(
        children: [
          if (_conflict != null) _conflictBanner(),
          TextField(
            key: const Key('ide_note_title'),
            controller: _title,
            enabled: !_busy,
            maxLength: _titleMax,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Tiêu đề', 'Title')),
          ),
          Expanded(
            child: TextField(
              key: const Key('ide_note_body'),
              controller: _body,
              enabled: !_busy,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Nội dung (Markdown)', 'Content (Markdown)'),
                alignLabelWithHint: true,
              ),
            ),
          ),
          if (_formError != null)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
              child: Text(
                _formError!,
                key: const Key('ide_note_error'),
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.danger,
                ),
              ),
            ),
          const SizedBox(height: WebTuiSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('ide_note_cancel'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: _busy ? null : _cancelEdit,
                  child: Text(tr('Huỷ', 'Cancel')),
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('ide_note_save'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(tr('Lưu', 'Save')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _conflictBanner() {
    return Container(
      key: const Key('ide_note_conflict'),
      margin: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      padding: const EdgeInsets.all(WebTuiSpacing.md),
      decoration: BoxDecoration(
        color: WebTuiColors.accentAmber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebTuiColors.accentAmber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _conflict!,
            style: WebTuiTypography.bodyMedium.copyWith(
              color: WebTuiColors.textPrimary,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          Text(
            tr(
              'Chữ bạn đang gõ vẫn còn nguyên. Chọn cách xử lý:',
              'Your typed text is still here. Choose what to do:',
            ),
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textSecondary,
            ),
          ),
          Wrap(
            spacing: WebTuiSpacing.sm,
            children: [
              TextButton(
                key: const Key('ide_note_conflict_copy'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: _copyMine,
                child: Text(tr('Chép chữ của tôi', 'Copy my text')),
              ),
              TextButton(
                key: const Key('ide_note_conflict_keep'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: _busy ? null : () => _takeLatest(keepMine: true),
                child: Text(tr('Giữ chữ của tôi', 'Keep my text')),
              ),
              TextButton(
                key: const Key('ide_note_conflict_reload'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: _busy ? null : () => _takeLatest(keepMine: false),
                child: Text(tr('Dùng bản mới', 'Use latest')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VersionsSheet extends ConsumerStatefulWidget {
  const _VersionsSheet({
    required this.project,
    required this.noteId,
    required this.canRestore,
  });

  final String project;
  final String noteId;
  final bool canRestore;

  @override
  ConsumerState<_VersionsSheet> createState() => _VersionsSheetState();
}

class _VersionsSheetState extends ConsumerState<_VersionsSheet> {
  Future<void> _open(IdeNoteVersion v) async {
    final restore = await showDialog<bool>(
      context: context,
      builder: (ctx) => WebTuiDialog(
        title: v.title.isEmpty ? '#${v.n}' : v.title,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(child: IdeMarkdown(text: v.body)),
        ),
        actions: [
          WebTuiDialogAction(
            key: const Key('webtui_dialog_cancel'),
            label: tr('Đóng', 'Close'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          if (widget.canRestore)
            WebTuiDialogAction(
              key: const Key('webtui_dialog_confirm'),
              label: tr('Khôi phục bản này', 'Restore this'),
              primary: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
        ],
      ),
    );
    if (restore != true || !mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(ideMoreServiceProvider)
          .restoreNote(widget.project, widget.noteId, v.n);
      nav.pop(true);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ideMoreErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.read(ideMoreServiceProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: IdeLoader<List<IdeNoteVersion>>(
          load: () => service.noteVersions(widget.project, widget.noteId),
          builder: (context, items, _) {
            if (items.isEmpty) {
              return SizedBox(
                height: 240,
                child: WebTuiEmptyState(
                  title: tr('Chưa có phiên bản cũ', 'No older versions'),
                  message: tr(
                    'Mỗi lần lưu sẽ tạo một phiên bản để quay lại.',
                    'Each save creates a version you can go back to.',
                  ),
                  icon: Icons.history_rounded,
                ),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final v in items)
                  ListTile(
                    key: Key('ide_note_version_${v.n}'),
                    minVerticalPadding: 12,
                    title: Text(v.title.isEmpty ? '#${v.n}' : v.title),
                    subtitle: Text(
                      [
                        if (v.by.isNotEmpty) v.by,
                        if (v.at != null) ideFormatDateTime(v.at!),
                        if (v.deleted) tr('đã xoá', 'deleted'),
                      ].join(' · '),
                    ),
                    onTap: () => _open(v),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
