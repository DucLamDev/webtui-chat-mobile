import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_files_service.dart';
import '../../../domain/ide_file_models.dart';
import '../../controllers/ide_files_controllers.dart';
import '../../widgets/files/ide_code_view.dart';
import '../../widgets/files/ide_files_ui.dart';
import '../../widgets/ide_wb.dart';

/// Màn xem thay đổi git (`files.diff`): cả dự án hoặc một tệp; dòng thêm
/// xanh, dòng xoá đỏ.
class IdeDiffScreen extends ConsumerStatefulWidget {
  const IdeDiffScreen({required this.root, this.path, super.key});

  final String root;
  final String? path;

  @override
  ConsumerState<IdeDiffScreen> createState() => _IdeDiffScreenState();
}

class _IdeDiffScreenState extends ConsumerState<IdeDiffScreen> {
  bool _loading = true;
  Object? _error;
  List<String> _lines = const [];
  bool _clipped = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final diff = await ref
          .read(ideFilesServiceProvider)
          .diff(widget.root, path: widget.path);
      if (!mounted) return;
      setState(() {
        final (lines, clipped) = ideClipDiff(diff);
        _lines = lines;
        _clipped = clipped;
        _loading = false;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.path == null
        ? tr('Thay đổi trong dự án', 'Project changes')
        : ideBaseName(widget.path!);
    final Widget body;
    if (_loading) {
      body = WebTuiLoadingState(
        message: tr('Đang lấy thay đổi...', 'Loading changes...'),
      );
    } else if (_error != null) {
      body = WebTuiErrorState(
        title: tr('Không lấy được thay đổi', 'Could not load changes'),
        message: ideFilesErrorText(_error!),
        onRetry: _load,
      );
    } else if (_lines.isEmpty) {
      body = WebTuiEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: tr('Không có thay đổi', 'No changes'),
        message: tr(
          'Mã đang giống bản đã lưu gần nhất.',
          'The code matches the latest commit.',
        ),
      );
    } else {
      body = ListView.builder(
        key: const Key('ide_diff_list'),
        itemCount: _lines.length + (_clipped ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _lines.length) {
            return Padding(
              key: const Key('ide_diff_clipped'),
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              child: Text(
                tr(
                  'Khác biệt quá dài, chỉ hiện phần đầu.',
                  'The diff is too long, showing only the beginning.',
                ),
                style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
              ),
            );
          }
          return IdeDiffLine(line: _lines[i]);
        },
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: tr('Tải lại', 'Reload'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Một dòng diff tô theo loại.
class IdeDiffLine extends StatelessWidget {
  const IdeDiffLine({required this.line, super.key});

  final String line;

  @override
  Widget build(BuildContext context) {
    final kind = ideDiffLineKind(line);
    final (bg, fg) = switch (kind) {
      IdeDiffLineKind.add => (
        IdeWbPalette.of(context).ok.withValues(alpha: 0.16),
        IdeWbPalette.of(context).textStrong,
      ),
      IdeDiffLineKind.remove => (
        IdeWbPalette.of(context).danger.withValues(alpha: 0.14),
        IdeWbPalette.of(context).textStrong,
      ),
      IdeDiffLineKind.hunk => (
        IdeWbPalette.of(context).accentSoft,
        IdeWbPalette.of(context).accentInk,
      ),
      IdeDiffLineKind.header => (
        IdeWbPalette.of(context).chip,
        IdeWbPalette.of(context).text,
      ),
      IdeDiffLineKind.context => (
        Colors.transparent,
        IdeWbPalette.of(context).textStrong,
      ),
    };
    return Semantics(
      label: switch (kind) {
        IdeDiffLineKind.add => tr('Thêm: $line', 'Added: $line'),
        IdeDiffLineKind.remove => tr('Xoá: $line', 'Removed: $line'),
        _ => line,
      },
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        color: bg,
        padding: const EdgeInsets.symmetric(
          horizontal: WebTuiSpacing.md,
          vertical: 1,
        ),
        child: Text(
          line.isEmpty ? ' ' : line,
          style: ideCodeStyle(context).copyWith(
            color: fg,
            fontWeight: kind == IdeDiffLineKind.header
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
