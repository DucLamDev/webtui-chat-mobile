import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import 'ide_ai_commands.dart';
import 'ide_ai_json.dart';
import 'ide_voice_button.dart';

const ideMaxMessageLength = 100000;

/// Tệp đính kèm đã chọn: [path] có khi tải xong.
final class IdeDraftAttachment {
  IdeDraftAttachment({required this.file, this.path, this.failed = false});

  final IdePickedFile file;
  String? path;
  bool failed;

  Map<String, Object?> toJson() => {
    'path': path,
    'name': file.name,
    'image': file.isImage,
  };
}

/// Ô gõ: menu `/` và `@`, đính kèm, giọng nói, Dừng.
class IdeAiComposer extends StatefulWidget {
  const IdeAiComposer({
    required this.canControl,
    required this.busy,
    required this.onSend,
    required this.onStop,
    required this.upload,
    this.commands = const [],
    this.changedPaths = const [],
    this.findFiles,
    this.picker,
    this.voice = true,
    this.initialText = '',
    super.key,
  });

  /// Chữ điền sẵn vào ô soạn (vd `@đường-dẫn ` từ màn Tệp).
  final String initialText;
  final bool canControl;
  final bool busy;
  final List<Map<String, Object?>> commands;
  final List<String> changedPaths;

  /// `files.find` qua RPC (null nếu IDE không có op này).
  final Future<List<String>> Function(String query)? findFiles;

  /// Tải tệp lên IDE, trả đường dẫn tuyệt đối trên máy IDE.
  final Future<String> Function(IdePickedFile file) upload;
  final void Function(String text, List<Map<String, Object?>> attachments)
  onSend;
  final VoidCallback onStop;
  final IdeAttachmentPicker? picker;
  final bool voice;

  @override
  State<IdeAiComposer> createState() => _IdeAiComposerState();
}

class _IdeAiComposerState extends State<IdeAiComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final List<IdeDraftAttachment> _files = [];
  late final IdeAttachmentPicker _picker =
      widget.picker ?? PlatformIdeAttachmentPicker();
  List<IdeSlashCommand> _slash = const [];
  List<String> _mentions = const [];
  String _error = '';
  Timer? _debounce;
  int _findSeq = 0;
  ({int start, int end})? _mentionRange;

  @override
  void initState() {
    super.initState();
    if (widget.initialText.isNotEmpty) {
      _text.value = TextEditingValue(
        text: widget.initialText,
        selection: TextSelection.collapsed(offset: widget.initialText.length),
      );
    }
    _text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _uploading => _files.any((f) => f.path == null && !f.failed);

  bool get _canSend =>
      widget.canControl &&
      !_uploading &&
      (_text.text.trim().isNotEmpty || _files.any((f) => f.path != null));

  void _onChanged() {
    final value = _text.value;
    final text = value.text;
    // Menu `/`: cả ô chỉ có một từ bắt đầu bằng "/".
    List<IdeSlashCommand> slash = const [];
    if (text.startsWith('/') && !text.contains(RegExp(r'\s'))) {
      final q = text.toLowerCase();
      slash = [
        for (final c in ideSlashCommands(widget.commands))
          if (c.name.toLowerCase().startsWith(q)) c,
      ];
    }
    // Menu `@`: từ đang gõ (trước con trỏ) bắt đầu bằng "@".
    final cursor = value.selection.isValid ? value.selection.baseOffset : -1;
    ({int start, int end})? range;
    if (cursor > 0 && cursor <= text.length) {
      var s = cursor;
      while (s > 0 && !RegExp(r'\s').hasMatch(text[s - 1])) {
        s--;
      }
      if (s < cursor && text[s] == '@') range = (start: s, end: cursor);
    }
    var mentions = const <String>[];
    if (range != null) {
      final q = text.substring(range.start + 1, range.end).toLowerCase();
      mentions = [
        for (final p in widget.changedPaths)
          if (q.isEmpty || p.toLowerCase().contains(q)) p,
      ].take(8).toList();
      _debounce?.cancel();
      final find = widget.findFiles;
      if (find != null && q.isNotEmpty) {
        final seq = ++_findSeq;
        _debounce = Timer(const Duration(milliseconds: 250), () async {
          try {
            final found = await find(q);
            if (!mounted || seq != _findSeq) return;
            setState(() {
              _mentions = {..._mentions, ...found}.take(12).toList();
            });
          } on Object {
            // Không có kết quả tìm tệp: vẫn dùng danh sách đã sửa.
          }
        });
      }
    }
    setState(() {
      _slash = slash;
      _mentions = mentions;
      _mentionRange = range;
    });
  }

  void _pickSlash(IdeSlashCommand c) {
    final next = '${c.name} ';
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _focus.requestFocus();
  }

  void _pickMention(String path) {
    final r = _mentionRange;
    if (r == null) return;
    final text = _text.text;
    final insert = '@$path ';
    _text.value = TextEditingValue(
      text: text.replaceRange(r.start, r.end, insert),
      selection: TextSelection.collapsed(offset: r.start + insert.length),
    );
    _focus.requestFocus();
  }

  Future<void> _attach(Future<IdePickedFile?> Function() pick) async {
    try {
      final file = await pick();
      if (file == null || !mounted) return;
      final draft = IdeDraftAttachment(file: file);
      setState(() {
        _files.add(draft);
        _error = '';
      });
      try {
        final path = await widget.upload(file);
        draft.path = path;
      } on Object {
        draft.failed = true;
        _error = tr(
          'Không tải được tệp lên IDE.',
          'Could not upload the file.',
        );
      }
      if (mounted) setState(() {});
    } on Object {
      if (mounted) {
        setState(
          () => _error = tr('Không chọn được tệp.', 'Could not pick the file.'),
        );
      }
    }
  }

  void _send() {
    if (!_canSend) return;
    final attachments = [
      for (final f in _files)
        if (f.path != null) f.toJson(),
    ];
    widget.onSend(_text.text.trim(), attachments);
    _text.clear();
    setState(_files.clear);
  }

  void _showAttachMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WebTuiColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('ide_attach_gallery'),
              minTileHeight: 52,
              leading: const Icon(Icons.photo_outlined),
              title: Text(tr('Ảnh trong máy', 'Photo library')),
              onTap: () {
                Navigator.of(sheet).pop();
                _attach(() => _picker.pickImage(camera: false));
              },
            ),
            ListTile(
              key: const Key('ide_attach_camera'),
              minTileHeight: 52,
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('Chụp ảnh', 'Take a photo')),
              onTap: () {
                Navigator.of(sheet).pop();
                _attach(() => _picker.pickImage(camera: true));
              },
            ),
            ListTile(
              key: const Key('ide_attach_file'),
              minTileHeight: 52,
              leading: const Icon(Icons.attach_file_rounded),
              title: Text(tr('Tệp', 'File')),
              onTap: () {
                Navigator.of(sheet).pop();
                _attach(_picker.pickFile);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final length = _text.text.length;
    final menu = _slash.isNotEmpty
        ? _menu(const Key('ide_slash_menu'), [
            for (final c in _slash)
              _menuRow(
                Key('ide_slash_${c.name}'),
                c.name,
                c.description,
                () => _pickSlash(c),
              ),
          ])
        : _mentions.isNotEmpty
        ? _menu(const Key('ide_mention_menu'), [
            for (final p in _mentions)
              _menuRow(
                Key('ide_mention_$p'),
                aiBaseName(p),
                p,
                () => _pickMention(p),
              ),
          ])
        : null;
    return Material(
      color: WebTuiColors.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?menu,
            if (_files.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: WebTuiSpacing.md,
                  ),
                  children: [
                    for (final f in _files)
                      Padding(
                        padding: const EdgeInsets.only(right: WebTuiSpacing.xs),
                        child: InputChip(
                          key: Key('ide_draft_${f.file.name}'),
                          avatar: f.path == null && !f.failed
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  f.failed
                                      ? Icons.error_outline_rounded
                                      : (f.file.isImage
                                            ? Icons.image_outlined
                                            : Icons.insert_drive_file_outlined),
                                  size: 18,
                                ),
                          label: Text(
                            f.file.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () => setState(() => _files.remove(f)),
                        ),
                      ),
                  ],
                ),
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.md,
                ),
                child: Text(
                  _error,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.danger,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.sm,
                WebTuiSpacing.xs,
                WebTuiSpacing.sm,
                WebTuiSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    key: const Key('ide_attach_button'),
                    tooltip: tr('Đính kèm', 'Attach'),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: widget.canControl ? _showAttachMenu : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      key: const Key('ide_ai_input'),
                      controller: _text,
                      focusNode: _focus,
                      enabled: widget.canControl,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(ideMaxMessageLength),
                      ],
                      decoration: InputDecoration(
                        hintText: widget.canControl
                            ? tr(
                                'Nhắn cho AI…  (/ lệnh, @ tệp)',
                                'Message the AI…  (/ command, @ file)',
                              )
                            : tr('Chỉ xem', 'View only'),
                        counterText: length > ideMaxMessageLength - 2000
                            ? '$length/$ideMaxMessageLength'
                            : '',
                        filled: true,
                        fillColor: WebTuiColors.backgroundMuted,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(WebTuiRadii.lg),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (widget.voice && widget.canControl)
                    IdeVoiceButton(
                      onText: (t) {
                        final cur = _text.text;
                        final next = cur.isEmpty ? t : '$cur $t';
                        _text.text = next.length > ideMaxMessageLength
                            ? next.substring(0, ideMaxMessageLength)
                            : next;
                      },
                    ),
                  if (widget.busy)
                    IconButton.filledTonal(
                      key: const Key('ide_ai_stop'),
                      tooltip: tr('Dừng', 'Stop'),
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      onPressed: widget.canControl ? widget.onStop : null,
                      icon: const Icon(Icons.stop_rounded),
                    ),
                  IconButton.filled(
                    key: const Key('ide_ai_send'),
                    tooltip: tr('Gửi', 'Send'),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: _canSend ? _send : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu(Key key, List<Widget> rows) => Container(
    key: key,
    constraints: const BoxConstraints(maxHeight: 260),
    margin: const EdgeInsets.fromLTRB(
      WebTuiSpacing.sm,
      0,
      WebTuiSpacing.sm,
      WebTuiSpacing.xs,
    ),
    child: Material(
      color: WebTuiColors.surfaceElevated,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: WebTuiColors.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: ListView(shrinkWrap: true, children: rows),
    ),
  );

  Widget _menuRow(Key key, String title, String sub, VoidCallback onTap) =>
      ListTile(
        key: key,
        dense: true,
        minTileHeight: 48,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: sub.isEmpty
            ? null
            : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      );
}
