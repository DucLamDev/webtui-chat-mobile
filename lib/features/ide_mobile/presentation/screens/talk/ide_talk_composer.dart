import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_talk_controller.dart';
import '../../../application/ide_talk_service.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/ai/ide_ai_commands.dart';
import '../../widgets/files/ide_file_card.dart' show ideFormatSize;
import '../../widgets/ide_wb.dart';
import 'ide_talk_providers.dart';

IdeTalkAttachment ideTalkAttachmentOf(IdePickedFile f) => IdeTalkAttachment(
  name: f.name,
  mime: f.mime,
  size: f.size,
  image: f.isImage,
  read: f.read,
);

/// Thanh dưới thay ô nhập trong cuộc của AI Agent (cổng IDE không nhận
/// `talk.send` ở đây): lời ngắn + nút "Chạy ngay" khi có `talk.agent_run`.
class IdeTalkAgentBar extends StatelessWidget {
  const IdeTalkAgentBar({required this.onRun, this.busy = false, super.key});

  /// `null` = IDE không có `talk.agent_run`: chỉ hiện lời.
  final VoidCallback? onRun;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IdeWb.bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WebTuiSpacing.lg,
            vertical: WebTuiSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  onRun == null
                      ? tr(
                          'Cuộc của AI Agent: không hỏi tiếp được.',
                          'AI Agent chat: you cannot ask follow-ups here.',
                        )
                      : tr(
                          'Cuộc của AI Agent: bấm Chạy ngay để chạy lại việc',
                          'AI Agent chat: tap Run now to run the job again',
                        ),
                  key: const Key('talk_agent_bar_text'),
                  style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
                ),
              ),
              if (onRun != null) ...[
                const SizedBox(width: WebTuiSpacing.sm),
                FilledButton(
                  key: const Key('talk_agent_run'),
                  onPressed: busy ? null : onRun,
                  child: Text(tr('Chạy ngay', 'Run now')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ô soạn tin: gõ, đính kèm ảnh / tệp, gửi (đang bận thì "Xếp hàng"), dừng.
/// [onSend] trả `true` khi đã gửi (ô được xoá); lỗi thì giữ nguyên chữ.
class IdeTalkComposer extends ConsumerStatefulWidget {
  const IdeTalkComposer({
    required this.controller,
    required this.working,
    required this.sending,
    required this.onSend,
    required this.onStop,
    this.canAttach = true,
    this.canStop = true,
    super.key,
  });

  final TextEditingController controller;

  /// AI đang trả lời (nút gửi thành "Xếp hàng", có nút Dừng).
  final bool working;
  final bool sending;
  final bool canAttach;
  final bool canStop;
  final Future<bool> Function(String text, List<IdeTalkAttachment> files)
  onSend;
  final VoidCallback onStop;

  @override
  ConsumerState<IdeTalkComposer> createState() => _IdeTalkComposerState();
}

class _IdeTalkComposerState extends ConsumerState<IdeTalkComposer> {
  final _picked = <IdePickedFile>[];
  bool _picking = false;
  bool _submitting = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pick(String kind) async {
    if (_picking) return;
    final images = _picked.where((f) => f.isImage).length;
    final files = _picked.length - images;
    if (kind != 'file' && images >= ideTalkMaxImages) {
      _snack(tr('Tối đa 8 ảnh.', 'At most 8 images.'));
      return;
    }
    if (kind == 'file' && files >= ideTalkMaxFiles) {
      _snack(tr('Tối đa 10 tệp.', 'At most 10 files.'));
      return;
    }
    setState(() => _picking = true);
    try {
      final picker = ref.read(ideTalkPickerProvider);
      final f = switch (kind) {
        'camera' => await picker.pickImage(camera: true),
        'gallery' => await picker.pickImage(camera: false),
        _ => await picker.pickFile(),
      };
      if (f != null && mounted) setState(() => _picked.add(f));
    } on Object {
      // MissingPluginException (Linux), từ chối quyền camera...
      _snack(
        tr(
          'Không mở được trình chọn trên máy này.',
          'Could not open the picker on this device.',
        ),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (widget.sending || _submitting) return;
    final text = widget.controller.text;
    if (text.trim().isEmpty) {
      _snack(tr('Hãy nhập nội dung.', 'Enter a message.'));
      return;
    }
    _submitting = true;
    final bool ok;
    try {
      ok = await widget.onSend(text, [
        for (final f in _picked) ideTalkAttachmentOf(f),
      ]);
    } finally {
      _submitting = false;
    }
    if (ok && mounted) {
      // Chỉ xoá đúng phần đã gửi: ô còn nguyên chữ đó thì xoá, đã gõ thêm thì giữ.
      if (widget.controller.text == text) widget.controller.clear();
      setState(_picked.clear);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IdeWb.bg,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.sm,
            WebTuiSpacing.sm,
            WebTuiSpacing.sm,
            WebTuiSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_picked.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _picked.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(
                            right: WebTuiSpacing.xs,
                          ),
                          child: InputChip(
                            key: Key('talk_picked_$i'),
                            avatar: Icon(
                              _picked[i].isImage
                                  ? Icons.image_outlined
                                  : Icons.attach_file_rounded,
                              size: 16,
                            ),
                            label: Text(
                              '${ideVisibleText(_picked[i].name)} · ${ideFormatSize(_picked[i].size)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                            onDeleted: widget.sending
                                ? null
                                : () => setState(() => _picked.removeAt(i)),
                          ),
                        ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.canAttach)
                    PopupMenuButton<String>(
                      key: const Key('talk_attach'),
                      tooltip: tr('Đính kèm', 'Attach'),
                      enabled: !widget.sending && !_picking,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      constraints: const BoxConstraints(minWidth: 44),
                      onSelected: _pick,
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'gallery',
                          height: 48,
                          child: Text(tr('Ảnh trong máy', 'Photo library')),
                        ),
                        PopupMenuItem(
                          value: 'camera',
                          height: 48,
                          child: Text(tr('Chụp ảnh', 'Take a photo')),
                        ),
                        PopupMenuItem(
                          value: 'file',
                          height: 48,
                          child: Text(tr('Tệp', 'File')),
                        ),
                      ],
                    ),
                  Expanded(
                    child: TextField(
                      key: const Key('talk_input'),
                      controller: widget.controller,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: widget.working
                            ? tr(
                                'AI đang trả lời, tin mới sẽ xếp hàng chờ',
                                'The AI is replying; new messages are queued',
                              )
                            : tr('Nhắn cho AI', 'Message the AI'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  if (widget.working && widget.canStop)
                    IconButton(
                      key: const Key('talk_stop'),
                      tooltip: tr('Dừng', 'Stop'),
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      icon: Icon(
                        Icons.stop_circle_outlined,
                        color: IdeWb.danger,
                      ),
                      onPressed: widget.onStop,
                    ),
                  IconButton.filled(
                    key: const Key('talk_send'),
                    tooltip: widget.working
                        ? tr('Xếp hàng', 'Queue')
                        : tr('Gửi', 'Send'),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: widget.sending
                        ? null
                        : () => unawaited(_submit()),
                    icon: widget.sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            widget.working
                                ? Icons.schedule_send_rounded
                                : Icons.send_rounded,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
