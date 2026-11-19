import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_file_models.dart';
import '../../controllers/ide_files_controllers.dart';
import '../../widgets/files/ide_code_controller.dart';
import '../../widgets/files/ide_code_view.dart';
import '../../widgets/files/ide_files_ui.dart';
import 'ide_diff_screen.dart';

/// Trình sửa tệp chữ: số dòng, tô màu nhẹ, tìm / thay, hoàn tác / làm lại,
/// lưu có kiểm xung đột (`baseMtime`). Đóng trả `true` nếu đã lưu.
class IdeFileEditorScreen extends ConsumerStatefulWidget {
  const IdeFileEditorScreen({
    required this.root,
    required this.path,
    required this.initialText,
    required this.baseMtime,
    super.key,
  });

  final String root;
  final String path;
  final String initialText;
  final int baseMtime;

  @override
  ConsumerState<IdeFileEditorScreen> createState() =>
      _IdeFileEditorScreenState();
}

class _IdeFileEditorScreenState extends ConsumerState<IdeFileEditorScreen> {
  late final IdeCodeController _text = IdeCodeController(
    text: widget.initialText,
    language: ideLanguageFor(ideBaseName(widget.path)),
  );
  final _undo = UndoHistoryController();
  final _focus = FocusNode();
  final _vScroll = ScrollController();
  final _findText = TextEditingController();
  final _replaceText = TextEditingController();

  late String _savedText = widget.initialText;
  late int _baseMtime = widget.baseMtime;
  bool _savedOnce = false;
  bool _saving = false;
  bool _finding = false;
  List<int> _matches = const [];
  int _match = -1;

  String get _name => ideBaseName(widget.path);
  bool get _dirty => _text.text != _savedText;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  @override
  void dispose() {
    _text.removeListener(_onText);
    _text.dispose();
    _undo.dispose();
    _focus.dispose();
    _vScroll.dispose();
    _findText.dispose();
    _replaceText.dispose();
    super.dispose();
  }

  void _onText() {
    if (!mounted) return;
    setState(() {
      if (_finding) _recompute();
    });
  }

  // ---- tìm / thay ----

  void _recompute({bool keepIndex = false}) {
    final q = _findText.text;
    if (q.isEmpty) {
      _matches = const [];
      _match = -1;
      return;
    }
    final hay = _text.text.toLowerCase();
    final needle = q.toLowerCase();
    final out = <int>[];
    var i = hay.indexOf(needle);
    while (i >= 0 && out.length < 5000) {
      out.add(i);
      i = hay.indexOf(needle, i + needle.length);
    }
    _matches = out;
    if (out.isEmpty) {
      _match = -1;
    } else if (!keepIndex || _match < 0 || _match >= out.length) {
      _match = 0;
    }
  }

  void _gotoMatch(int index) {
    if (_matches.isEmpty) return;
    final n = _matches.length;
    final i = (index % n + n) % n;
    final start = _matches[i];
    setState(() => _match = i);
    final len = _findText.text.length;
    _text.selection = TextSelection(
      baseOffset: start,
      extentOffset: math.min(start + len, _text.text.length),
    );
    final line = '\n'.allMatches(_text.text.substring(0, start)).length;
    final extent = ideCodeLineExtent(context);
    if (_vScroll.hasClients) {
      _vScroll.animateTo(
        (line * extent - 100).clamp(0.0, _vScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  void _replaceOne() {
    if (_match < 0 || _match >= _matches.length) return;
    final start = _matches[_match];
    final len = _findText.text.length;
    final r = _replaceText.text;
    final t = _text.text;
    _text.value = TextEditingValue(
      text: t.replaceRange(start, start + len, r),
      selection: TextSelection.collapsed(offset: start + r.length),
    );
    setState(() {
      _recompute(keepIndex: true);
      if (_matches.isNotEmpty) _gotoMatch(_match);
    });
  }

  void _replaceAll() {
    final q = _findText.text;
    if (q.isEmpty || _matches.isEmpty) return;
    final r = _replaceText.text;
    final count = _matches.length;
    _text.value = TextEditingValue(
      text: _text.text.replaceAllMapped(
        RegExp(RegExp.escape(q), caseSensitive: false),
        (_) => r,
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    setState(_recompute);
    ideSnack(context, tr('Đã thay $count chỗ', 'Replaced $count occurrences'));
  }

  // ---- lưu ----

  Future<bool> _save({bool force = false}) async {
    if (_saving) return false;
    setState(() => _saving = true);
    final text = _text.text;
    try {
      final mtime = await ref
          .read(ideFilesServiceProvider)
          .write(widget.path, text, baseMtime: _baseMtime, force: force);
      if (!mounted) return true;
      setState(() {
        _savedText = text;
        _baseMtime = mtime;
        _savedOnce = true;
      });
      ideSnack(context, tr('Đã lưu', 'Saved'));
      return true;
    } on IdeConflict {
      if (!mounted) return false;
      return await _resolveConflict();
    } on Object catch (e) {
      if (mounted) ideSnack(context, ideFilesErrorText(e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Tệp đã đổi trên máy tính: Tải lại / Ghi đè / Xem khác biệt.
  Future<bool> _resolveConflict() async {
    while (mounted) {
      final choice = await showWebTuiSheet<String>(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WebTuiSheetHeader(
                title: tr(
                  'Tệp đã đổi trên máy tính',
                  'File changed on your computer',
                ),
                subtitle: tr(
                  'Có người vừa sửa tệp này. Chọn cách xử lý.',
                  'Someone just edited this file. Choose what to do.',
                ),
              ),
              WebTuiSheetActionTile(
                key: const Key('ide_conflict_reload'),
                icon: Icons.refresh_rounded,
                title: tr('Tải lại', 'Reload'),
                subtitle: tr(
                  'Bỏ phần bạn sửa, lấy bản mới',
                  'Discard your edits, take the new version',
                ),
                onTap: () => Navigator.of(ctx).pop('reload'),
              ),
              WebTuiSheetActionTile(
                key: const Key('ide_conflict_force'),
                icon: Icons.save_as_outlined,
                title: tr('Ghi đè', 'Overwrite'),
                subtitle: tr(
                  'Lưu bản của bạn, mất thay đổi trên máy tính',
                  'Save yours, losing the computer changes',
                ),
                tone: WebTuiDialogTone.danger,
                onTap: () => Navigator.of(ctx).pop('force'),
              ),
              WebTuiSheetActionTile(
                key: const Key('ide_conflict_diff'),
                icon: Icons.difference_outlined,
                title: tr('Xem khác biệt', 'View differences'),
                subtitle: tr(
                  'Xem thay đổi của tệp so với bản đã lưu (git)',
                  'See the file changes against the last commit (git)',
                ),
                onTap: () => Navigator.of(ctx).pop('diff'),
              ),
              const SizedBox(height: WebTuiSpacing.sm),
            ],
          ),
        ),
      );
      if (!mounted || choice == null) return false;
      switch (choice) {
        case 'reload':
          return _reload();
        case 'force':
          // _saving đang bật cho lượt trước; tắt để lượt ghi đè chạy.
          setState(() => _saving = false);
          return _save(force: true);
        case 'diff':
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  IdeDiffScreen(root: widget.root, path: widget.path),
            ),
          );
      }
    }
    return false;
  }

  Future<bool> _reload() async {
    try {
      final t = await ref.read(ideFilesServiceProvider).read(widget.path);
      if (!mounted) return false;
      _text.value = TextEditingValue(
        text: t.text,
        selection: const TextSelection.collapsed(offset: 0),
      );
      setState(() {
        _savedText = t.text;
        _baseMtime = t.mtime;
      });
      ideSnack(context, tr('Đã tải lại bản mới', 'Reloaded the new version'));
      return false;
    } on Object catch (e) {
      if (mounted) ideSnack(context, ideFilesErrorText(e));
      return false;
    }
  }

  // ---- thoát ----

  Future<void> _onPop(bool didPop) async {
    if (didPop) return;
    if (_dirty) {
      final leave = await showWebTuiConfirmDialog(
        context,
        title: tr('Thoát mà chưa lưu?', 'Leave without saving?'),
        message: tr(
          'Các thay đổi chưa lưu sẽ mất.',
          'Unsaved changes will be lost.',
        ),
        confirmLabel: tr('Bỏ thay đổi', 'Discard'),
        cancelLabel: tr('Tiếp tục sửa', 'Keep editing'),
        destructive: true,
        icon: Icons.warning_amber_rounded,
      );
      if (!leave || !mounted) return;
    }
    Navigator.of(context).pop(_savedOnce);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => unawaited(_onPop(didPop)),
      child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: Colors.transparent,
          title: Text(
            _dirty ? '$_name •' : _name,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            ValueListenableBuilder<UndoHistoryValue>(
              valueListenable: _undo,
              builder: (_, v, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('ide_editor_undo'),
                    tooltip: tr('Hoàn tác', 'Undo'),
                    icon: const Icon(Icons.undo_rounded),
                    onPressed: v.canUndo ? _undo.undo : null,
                  ),
                  IconButton(
                    key: const Key('ide_editor_redo'),
                    tooltip: tr('Làm lại', 'Redo'),
                    icon: const Icon(Icons.redo_rounded),
                    onPressed: v.canRedo ? _undo.redo : null,
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('ide_editor_find'),
              tooltip: tr('Tìm và thay', 'Find and replace'),
              icon: Icon(
                _finding ? Icons.search_off_rounded : Icons.search_rounded,
              ),
              onPressed: () => setState(() {
                _finding = !_finding;
                if (_finding) {
                  _recompute();
                }
              }),
            ),
            IconButton(
              key: const Key('ide_editor_save'),
              tooltip: tr('Lưu', 'Save'),
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              onPressed: _dirty && !_saving ? () => unawaited(_save()) : null,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_finding) _findBar(),
              Expanded(child: _editor()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _findBar() {
    final count = _matches.isEmpty
        ? (_findText.text.isEmpty ? '' : tr('0 kết quả', '0 results'))
        : '${_match + 1}/${_matches.length}';
    return Container(
      color: WebTuiColors.backgroundMuted,
      padding: const EdgeInsets.fromLTRB(
        WebTuiSpacing.md,
        WebTuiSpacing.sm,
        WebTuiSpacing.sm,
        WebTuiSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('ide_find_field'),
                  controller: _findText,
                  autofocus: true,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('Tìm', 'Find'),
                    suffixText: count,
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {
                    _recompute();
                    if (_matches.isNotEmpty) _gotoMatch(0);
                  }),
                  onSubmitted: (_) => _gotoMatch(_match + 1),
                ),
              ),
              IconButton(
                key: const Key('ide_find_prev'),
                tooltip: tr('Kết quả trước', 'Previous'),
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                onPressed: _matches.isEmpty
                    ? null
                    : () => _gotoMatch(_match - 1),
              ),
              IconButton(
                key: const Key('ide_find_next'),
                tooltip: tr('Kết quả sau', 'Next'),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                onPressed: _matches.isEmpty
                    ? null
                    : () => _gotoMatch(_match + 1),
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('ide_replace_field'),
                  controller: _replaceText,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('Thay bằng', 'Replace with'),
                  ),
                ),
              ),
              TextButton(
                key: const Key('ide_replace_one'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _matches.isEmpty ? null : _replaceOne,
                child: Text(tr('Thay', 'Replace')),
              ),
              TextButton(
                key: const Key('ide_replace_all'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _matches.isEmpty ? null : _replaceAll,
                child: Text(tr('Thay hết', 'All')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _measuredText;
  TextScaler? _measuredScale;
  double _measuredWidth = 0;

  /// Bề rộng thật của dòng dài nhất. Không lấy số ký tự × bề rộng một ký tự:
  /// chữ có dấu / chữ lấy từ phông dự phòng rộng hơn, ô sửa sẽ tự ngắt dòng và
  /// số dòng lệch với mã. Chỉ đo các dòng gần dài nhất để tệp lớn vẫn nhẹ.
  double _widestLine(String t) {
    final scaler = MediaQuery.textScalerOf(context);
    if (identical(t, _measuredText) && scaler == _measuredScale) {
      return _measuredWidth;
    }
    final lines = t.split('\n');
    var longest = 0;
    for (final l in lines) {
      if (l.length > longest) longest = l.length;
    }
    final candidates = [
      for (final l in lines)
        if (l.length * 10 >= longest * 6) l,
    ]..sort((a, b) => b.length.compareTo(a.length));
    var width = 0.0;
    for (final l in candidates.take(64)) {
      final p = TextPainter(
        text: TextSpan(text: l, style: ideCodeStyle()),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      width = math.max(width, p.width);
      p.dispose();
    }
    _measuredText = t;
    _measuredScale = scaler;
    _measuredWidth = width.ceilToDouble();
    return _measuredWidth;
  }

  Widget _editor() {
    final t = _text.text;
    final lines = '\n'.allMatches(t).length + 1;
    final charW = ideCodeCharWidth(context);
    final textW = _widestLine(t);
    final extent = ideCodeLineExtent(context);
    final line = _finding && _match >= 0 && _match < _matches.length
        ? '\n'.allMatches(t.substring(0, _matches[_match])).length
        : null;
    return LayoutBuilder(
      builder: (context, box) {
        const pad = WebTuiSpacing.md;
        final gutterW = ideLineNumbersWidth(context, lines);
        final fieldW = math.max(
          box.maxWidth - gutterW,
          textW + charW * 3 + pad * 2,
        );
        return Scrollbar(
          controller: _vScroll,
          child: SingleChildScrollView(
            controller: _vScroll,
            child: Stack(
              children: [
                if (line != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: line * extent + WebTuiSpacing.sm,
                    height: extent,
                    child: ColoredBox(color: WebTuiColors.primarySoft),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
                      child: IdeLineNumbers(lines: lines),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: fieldW,
                          child: TextField(
                            key: const Key('ide_editor_field'),
                            controller: _text,
                            focusNode: _focus,
                            undoController: _undo,
                            readOnly: _saving,
                            maxLines: null,
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
                            autocorrect: false,
                            enableSuggestions: false,
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            style: ideCodeStyle(),
                            strutStyle: ideCodeStrut,
                            cursorColor: WebTuiColors.primary,
                            decoration: const InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.fromLTRB(
                                pad,
                                WebTuiSpacing.sm,
                                pad,
                                WebTuiSpacing.sm,
                              ),
                            ),
                            inputFormatters: [
                              // Tệp nhận chữ thuần: bỏ ký tự điều khiển dán vào.
                              FilteringTextInputFormatter.deny(
                                RegExp(
                                  r'[\u0000-\u0008\u000b\u000c\u000e-\u001f]',
                                ),
                              ),
                            ],
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
      },
    );
  }
}
