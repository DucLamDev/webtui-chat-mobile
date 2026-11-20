import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_file_models.dart';
import '../../controllers/ide_files_controllers.dart';
import '../../widgets/files/ide_code_view.dart';
import '../../widgets/files/ide_files_ui.dart';
import '../../widgets/ide_wb.dart';
import 'ide_file_viewer_screen.dart';

/// Tìm trong dự án: theo tên (`files.find`) hoặc theo chữ (`files.grep`).
class IdeFilesSearchScreen extends ConsumerStatefulWidget {
  const IdeFilesSearchScreen({
    required this.root,
    this.debounce = const Duration(milliseconds: 400),
    super.key,
  });

  final String root;
  final Duration debounce;

  @override
  ConsumerState<IdeFilesSearchScreen> createState() =>
      _IdeFilesSearchScreenState();
}

class _IdeFilesSearchScreenState extends ConsumerState<IdeFilesSearchScreen> {
  final _query = TextEditingController();
  Timer? _timer;
  int _mode = 0; // 0 = theo tên, 1 = theo chữ
  bool _loading = false;
  bool _searched = false;
  Object? _error;
  bool _truncated = false;
  List<IdeFindHit> _finds = const [];
  List<IdeGrepHit> _greps = const [];
  int _seq = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(widget.debounce, _run);
  }

  Future<void> _run() async {
    final q = _query.text.trim();
    final seq = ++_seq;
    if (q.isEmpty) {
      setState(() {
        _searched = false;
        _loading = false;
        _error = null;
        _finds = const [];
        _greps = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = ref.read(ideFilesServiceProvider);
      if (_mode == 0) {
        final r = await files.find(widget.root, q);
        if (!mounted || seq != _seq) return;
        setState(() {
          _finds = r.items;
          _greps = const [];
          _truncated = r.truncated;
        });
      } else {
        final r = await files.grep(widget.root, q);
        if (!mounted || seq != _seq) return;
        setState(() {
          _greps = r.items;
          _finds = const [];
          _truncated = r.truncated;
        });
      }
      setState(() {
        _loading = false;
        _searched = true;
      });
    } on Object catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  String _rel(String path) => ideIsInside(widget.root, path)
      ? path.substring(widget.root.length).replaceFirst(RegExp('^/'), '')
      : path;

  void _open(String path, {int? line}) {
    unawaited(
      Navigator.of(context).push(
        IdePageRoute<void>(
          dark: true,
          builder: (_) =>
              IdeFileViewerScreen(root: widget.root, path: path, line: line),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: TextField(
          key: const Key('ide_search_field'),
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintText: _mode == 0
                ? tr('Tìm theo tên tệp', 'Search by file name')
                : tr('Tìm theo nội dung', 'Search by content'),
          ),
          onChanged: (_) => _schedule(),
          onSubmitted: (_) => unawaited(_run()),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.lg,
                WebTuiSpacing.sm,
                WebTuiSpacing.lg,
                WebTuiSpacing.sm,
              ),
              child: WebTuiSegmentedTabs(
                tabs: [tr('Theo tên', 'By name'), tr('Theo chữ', 'By text')],
                selectedIndex: _mode,
                onChanged: (i) {
                  setState(() => _mode = i);
                  unawaited(_run());
                },
              ),
            ),
            Expanded(child: _results()),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    if (_loading) {
      return WebTuiLoadingState(message: tr('Đang tìm...', 'Searching...'));
    }
    final e = _error;
    if (e != null) {
      return WebTuiErrorState(
        title: tr('Không tìm được', 'Search failed'),
        message: ideFilesErrorText(e),
        onRetry: _run,
      );
    }
    if (!_searched) {
      return WebTuiEmptyState(
        icon: Icons.search_rounded,
        title: tr('Tìm trong dự án', 'Search the project'),
        message: _mode == 0
            ? tr('Gõ một phần tên tệp.', 'Type part of a file name.')
            : tr('Gõ chữ cần tìm trong tệp.', 'Type text to find in files.'),
      );
    }
    final count = _mode == 0 ? _finds.length : _greps.length;
    if (count == 0) {
      return WebTuiEmptyState(
        icon: Icons.search_off_rounded,
        title: tr('Không có kết quả', 'No results'),
        message: tr('Thử từ khoá khác.', 'Try another keyword.'),
      );
    }
    return ListView.separated(
      key: const Key('ide_search_results'),
      itemCount: count + (_truncated ? 1 : 0),
      separatorBuilder: (_, _) => const WebTuiHairline(),
      itemBuilder: (_, i) {
        if (i == count) {
          return Padding(
            padding: const EdgeInsets.all(WebTuiSpacing.lg),
            child: Text(
              tr(
                'Còn nhiều kết quả nữa. Hãy gõ cụ thể hơn.',
                'There are more results. Be more specific.',
              ),
              style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
            ),
          );
        }
        if (_mode == 0) {
          final h = _finds[i];
          return ListTile(
            minVerticalPadding: 10,
            leading: Icon(
              h.isDir ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
              color: IdeWb.text,
            ),
            title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              _rel(h.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: h.isDir ? null : () => _open(h.path),
          );
        }
        final h = _greps[i];
        return ListTile(
          minVerticalPadding: 10,
          title: Text(
            h.text.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ideCodeStyle(context),
          ),
          subtitle: Text(
            '${_rel(h.path)}:${h.line}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _open(h.path, line: h.line),
        );
      },
    );
  }
}
