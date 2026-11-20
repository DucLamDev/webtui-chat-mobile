import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_download_service.dart';
import 'ide_image_viewer.dart';

final _pathRe = RegExp(
  r'(?<![\w/:.~%@+-])(/(?:[\w.\-+@%]+/)*[\w.\-+@%]*[\w\-+@%]\.[A-Za-z0-9]{1,8})(?![\w/])',
);

/// Đường dẫn tệp tuyệt đối có đuôi trong [text] (không trùng, tối đa 8, bỏ
/// đường có `..`). Địa chỉ web (`https://a/b.png`) không tính.
List<String> ideFilePathsIn(String text) {
  final out = <String>[];
  for (final m in _pathRe.allMatches(text)) {
    final p = m[1]!;
    if (p.split('/').contains('..') || out.contains(p)) continue;
    out.add(p);
    if (out.length >= 8) break;
  }
  return out;
}

String ideFormatSize(int? bytes) {
  if (bytes == null || bytes < 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
}

/// Thẻ tệp trong tin nhắn: chạm để tải về máy; ảnh thì mở xem toàn màn.
class IdeFileCard extends ConsumerStatefulWidget {
  const IdeFileCard({required this.path, this.name, this.size, super.key});

  final String path;
  final String? name;
  final int? size;

  @override
  ConsumerState<IdeFileCard> createState() => _IdeFileCardState();
}

class _IdeFileCardState extends ConsumerState<IdeFileCard> {
  IdeDownload? _dl;
  IdeDownloadedFile? _file;
  String? _error;
  String? _note;

  String get _name => ideSafeFileName(widget.name ?? widget.path);

  @override
  void dispose() {
    _dl?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final service = ref.read(ideDownloadServiceProvider);
    final dl = service.start(widget.path, name: widget.name);
    setState(() {
      _dl = dl;
      _error = null;
      _note = null;
    });
    try {
      final f = await dl.done;
      if (!mounted) return;
      setState(() {
        _file = f;
        _dl = null;
      });
      if (ideIsImageName(f.name)) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => IdeImageViewer(file: f),
          ),
        );
        await _discard();
      } else {
        await _save();
      }
    } on IdeDownloadCancelled {
      if (mounted) setState(() => _dl = null);
    } on Object {
      if (mounted) {
        setState(() {
          _dl = null;
          _error = tr('Không tải được tệp', 'Could not download the file');
        });
      }
    }
  }

  Future<void> _save() async {
    final f = _file;
    if (f == null) return;
    try {
      final note = await ref
          .read(ideDownloadServiceProvider)
          .save(f, confirmOpen: _confirmOpen);
      if (mounted && note != null) setState(() => _note = note);
      await _discard();
    } on Object {
      if (mounted) {
        setState(
          () => _error = tr('Không lưu được tệp', 'Could not save the file'),
        );
      }
    }
  }

  Future<bool> _confirmOpen() {
    if (!mounted) return Future.value(false);
    return showWebTuiConfirmDialog(
      context,
      title: tr('Mở tệp bằng ứng dụng khác?', 'Open with another app?'),
      message: tr(
        'Máy Android này chưa lưu thẳng vào Tải về được. Chỉ mở tệp bạn tin tưởng.',
        'This Android cannot save to Downloads directly. Only open files you trust.',
      ),
      confirmLabel: tr('Mở', 'Open'),
    );
  }

  /// Xoá tệp tạm sau khi lưu / xem xong; muốn lưu lại thì tải lại.
  Future<void> _discard() async {
    final f = _file;
    if (f == null) return;
    _file = null;
    await ref.read(ideDownloadServiceProvider).discard(f);
  }

  @override
  Widget build(BuildContext context) {
    final dl = _dl;
    final image = ideIsImageName(_name);
    final size = ideFormatSize(_file?.size ?? widget.size);
    final sub = _error ?? _note ?? size;
    return Container(
      padding: const EdgeInsets.all(WebTuiSpacing.sm),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: WebTuiColors.border),
      ),
      child: Row(
        children: [
          Icon(
            image ? Icons.image_outlined : Icons.insert_drive_file_outlined,
            color: WebTuiColors.primary,
          ),
          const SizedBox(width: WebTuiSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: WebTuiColors.textPrimary,
                  ),
                ),
                if (dl != null)
                  StreamBuilder<double?>(
                    stream: dl.progress.stream,
                    initialData: dl.progress.value,
                    builder: (_, s) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(value: s.data),
                    ),
                  )
                else if (sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: _error != null
                          ? WebTuiColors.danger
                          : WebTuiColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (dl != null)
            IconButton(
              tooltip: tr('Huỷ tải', 'Cancel download'),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(Icons.close_rounded),
              onPressed: dl.cancel,
            )
          else
            IconButton(
              tooltip: _file != null
                  ? tr('Lưu lại', 'Save again')
                  : image
                  ? tr('Xem ảnh', 'View image')
                  : tr('Tải về', 'Download'),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(
                _file != null
                    ? Icons.save_alt_rounded
                    : image
                    ? Icons.open_in_full_rounded
                    : Icons.download_rounded,
              ),
              onPressed: _file != null ? _save : () => unawaited(_start()),
            ),
        ],
      ),
    );
  }
}
