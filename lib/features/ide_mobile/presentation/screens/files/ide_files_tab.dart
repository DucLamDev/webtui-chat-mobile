import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_download_service.dart';
import '../../../data/ide_connection.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_file_models.dart';
import '../../controllers/ide_controllers.dart';
import '../../controllers/ide_files_controllers.dart';
import '../../widgets/ai/ide_ai_commands.dart';
import '../../widgets/ai/ide_new_session_sheet.dart' show IdeProjectItem;
import '../../widgets/files/ide_file_actions.dart';
import '../../widgets/files/ide_file_card.dart' show ideFormatSize;
import '../../widgets/files/ide_file_job_dialog.dart';
import '../../widgets/files/ide_file_transfer.dart';
import '../../widgets/files/ide_files_ui.dart';
import '../../widgets/ide_wb.dart';
import 'ide_diff_screen.dart';
import 'ide_file_viewer_screen.dart';
import 'ide_files_search_screen.dart';
import 'ide_trash_screen.dart';

/// Tab Tệp của IDE: cây thư mục dự án, thao tác nhấn giữ, nút "+", tìm,
/// thay đổi git, thùng rác.
class IdeFilesTab extends ConsumerStatefulWidget {
  const IdeFilesTab({this.picker, super.key});

  /// Chỗ thay bộ chọn tệp / ảnh khi test.
  final IdeAttachmentPicker? picker;

  @override
  ConsumerState<IdeFilesTab> createState() => _IdeFilesTabState();
}

class _IdeFilesTabState extends ConsumerState<IdeFilesTab> {
  late final IdeAttachmentPicker _picker =
      widget.picker ?? PlatformIdeAttachmentPicker();

  List<IdeProjectItem>? _projects;
  Object? _projectsError;
  bool _loading = true;
  Object? _error;
  List<IdeFileEntry> _entries = const [];
  bool _busy = false;
  int _seq = 0;

  IdeFilesLocation? get _loc => ref.read(ideFilesLocationProvider);
  String get _root => _loc?.root ?? '';
  String get _dir => _loc?.dir ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _projectsError = null;
      _error = null;
    });
    try {
      if (refresh) ref.invalidate(ideFileProjectsProvider);
      final list = await ref.read(ideFileProjectsProvider.future);
      if (!mounted) return;
      _projects = list;
      if (list.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final cur = _loc;
      final keep = cur != null && list.any((p) => p.root == cur.root);
      if (!keep) {
        ref.read(ideFilesLocationProvider.notifier).state = IdeFilesLocation(
          root: list.first.root,
          dir: list.first.root,
        );
      }
      await _load();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _projectsError = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(ideFilesServiceProvider)
          .list(_dir, hidden: ref.read(ideFilesShowHiddenProvider));
      if (!mounted || seq != _seq) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } on Object catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _goTo(String dir) {
    final loc = _loc;
    if (loc == null) return;
    ref.read(ideFilesLocationProvider.notifier).state = IdeFilesLocation(
      root: loc.root,
      dir: dir,
    );
    unawaited(_load());
  }

  void _pickProject(IdeProjectItem p) {
    ref.read(ideFilesLocationProvider.notifier).state = IdeFilesLocation(
      root: p.root,
      dir: p.root,
    );
    unawaited(_load());
  }

  List<IdeFileEntry> get _sorted {
    final sort = ref.read(ideFilesSortProvider);
    final out = [..._entries];
    int byName(IdeFileEntry a, IdeFileEntry b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return switch (sort) {
        IdeFileSort.name => byName(a, b),
        IdeFileSort.date =>
          b.mtime != a.mtime ? b.mtime.compareTo(a.mtime) : byName(a, b),
        IdeFileSort.size =>
          b.size != a.size ? b.size.compareTo(a.size) : byName(a, b),
      };
    });
    return out;
  }

  // ---- thao tác ----

  /// Chạy một thao tác, báo kết quả / lỗi, rồi tải lại danh sách.
  Future<bool> _run(Future<void> Function() action, String done) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ideSnack(context, done);
      await _load();
      return true;
    } on Object catch (e) {
      if (mounted) ideSnack(context, ideFilesErrorText(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(IdeFileEntry e) {
    if (e.isDir) return _goTo(e.path);
    if (e.secret) {
      ideSnack(
        context,
        tr(
          'Tệp bí mật chỉ mở trên máy tính.',
          'Secret files only open on your computer.',
        ),
      );
      return;
    }
    unawaited(
      Navigator.of(context).push(
        IdePageRoute<void>(
          dark: true,
          builder: (_) =>
              IdeFileViewerScreen(root: _root, path: e.path, size: e.size),
        ),
      ),
    );
  }

  Future<void> _rename(IdeFileEntry e) async {
    final name = await showWebTuiTextInputDialog(
      context,
      title: tr('Đổi tên', 'Rename'),
      initialValue: e.name,
      label: tr('Tên mới', 'New name'),
      maxLength: 255,
      validator: ideNameErrorText,
    );
    if (name == null || name == e.name || !mounted) return;
    await _run(
      () async => ref.read(ideFilesServiceProvider).rename(e.path, name),
      tr('Đã đổi tên', 'Renamed'),
    );
  }

  void _clip(IdeFileEntry e, {required bool cut}) {
    ref.read(ideFilesClipboardProvider.notifier).state = IdeFileClip(
      path: e.path,
      name: e.name,
      cut: cut,
      isDir: e.isDir,
    );
    ideSnack(
      context,
      cut
          ? tr(
              'Đã cắt "${e.name}". Vào thư mục đích rồi bấm Dán.',
              'Cut "${e.name}". Open the target folder and tap Paste.',
            )
          : tr(
              'Đã chép "${e.name}". Vào thư mục đích rồi bấm Dán.',
              'Copied "${e.name}". Open the target folder and tap Paste.',
            ),
    );
  }

  Future<void> _paste() async {
    final clip = ref.read(ideFilesClipboardProvider);
    if (clip == null) return;
    // Không dán thư mục vào chính nó hay thư mục con của nó.
    if (clip.isDir && ideIsInside(clip.path, _dir)) {
      ideSnack(
        context,
        tr(
          'Không dán thư mục vào chính nó.',
          'Cannot paste a folder into itself.',
        ),
      );
      return;
    }
    final ok = await _run(() async {
      final files = ref.read(ideFilesServiceProvider);
      if (clip.cut) {
        await files.move(clip.path, _dir);
      } else {
        await files.copy(clip.path, _dir);
      }
    }, tr('Đã dán "${clip.name}"', 'Pasted "${clip.name}"'));
    if (ok && clip.cut) {
      ref.read(ideFilesClipboardProvider.notifier).state = null;
    }
  }

  Future<void> _delete(IdeFileEntry e) async {
    final ok = await showWebTuiConfirmDialog(
      context,
      title: tr('Xoá "${e.name}"?', 'Delete "${e.name}"?'),
      message: tr(
        'Mục này được chuyển vào thùng rác, bạn có thể khôi phục.',
        'It moves to the trash and can be restored.',
      ),
      confirmLabel: tr('Xoá', 'Delete'),
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    await _run(
      () async => ref.read(ideFilesServiceProvider).delete(e.path),
      tr('Đã chuyển vào thùng rác', 'Moved to the trash'),
    );
  }

  Future<void> _zip(IdeFileEntry e) async {
    if (_busy) return;
    try {
      final job = await ref.read(ideFilesServiceProvider).zip(e.path);
      if (!mounted) return;
      final out = await showIdeFileJobDialog(
        context,
        job: job,
        title: tr('Đang nén zip', 'Creating zip'),
      );
      if (!mounted) return;
      await _load();
      if (out == null) return;
      if (!out.ok) {
        if (mounted) {
          ideSnack(
            context,
            out.cancelled
                ? tr('Đã huỷ nén', 'Zip cancelled')
                : tr('Nén không thành công', 'Zip failed'),
          );
        }
        return;
      }
      if (mounted) {
        ideSnack(
          context,
          tr(
            'Đã nén xong (có trong thư mục).',
            'Zip created (in this folder).',
          ),
        );
      }
    } on Object catch (err) {
      if (mounted) ideSnack(context, ideFilesErrorText(err));
    }
  }

  Future<void> _newFile() async {
    final r = await showDialog<({String name, bool agents})>(
      context: context,
      builder: (_) => const _NewFileDialog(),
    );
    if (r == null || !mounted) return;
    await _run(
      () async => ref
          .read(ideFilesServiceProvider)
          .create(_dir, r.name, agents: r.agents),
      tr('Đã tạo tệp', 'File created'),
    );
  }

  Future<void> _newFolder() async {
    final name = await showWebTuiTextInputDialog(
      context,
      title: tr('Thư mục mới', 'New folder'),
      label: tr('Tên thư mục', 'Folder name'),
      confirmLabel: tr('Tạo', 'Create'),
      maxLength: 255,
      validator: ideNameErrorText,
    );
    if (name == null || !mounted) return;
    await _run(
      () async => ref.read(ideFilesServiceProvider).mkdir(_dir, name),
      tr('Đã tạo thư mục', 'Folder created'),
    );
  }

  Future<void> _upload({required bool image}) async {
    try {
      final f = image
          ? await _picker.pickImage(camera: false)
          : await _picker.pickFile();
      if (f == null || !mounted) return;
      final name = ideSafeFileName(f.name);
      await _run(
        () async => ref
            .read(ideFilesServiceProvider)
            .put(_dir, name, f.read(), size: f.size, mime: f.mime),
        tr('Đã tải lên "$name"', 'Uploaded "$name"'),
      );
    } on Object catch (e) {
      if (mounted) ideSnack(context, ideFilesErrorText(e));
    }
  }

  Future<void> _fetchUrl() async {
    final url = await showWebTuiTextInputDialog(
      context,
      title: tr('Lấy từ liên kết', 'Get from link'),
      message: tr(
        'IDE sẽ tải tệp từ liên kết https về thư mục này.',
        'The IDE downloads the https link into this folder.',
      ),
      label: tr('Liên kết https://', 'https:// link'),
      confirmLabel: tr('Lấy', 'Get'),
      validator: (v) {
        final u = Uri.tryParse(v.trim());
        return u != null && u.scheme == 'https' && u.host.isNotEmpty
            ? null
            : tr(
                'Chỉ nhận liên kết bắt đầu bằng https://',
                'Only https:// links are accepted',
              );
      },
    );
    if (url == null || !mounted) return;
    try {
      final job = await ref
          .read(ideFilesServiceProvider)
          .fetch(_dir, url.trim());
      if (!mounted) return;
      final out = await showIdeFileJobDialog(
        context,
        job: job,
        title: tr('Đang lấy tệp', 'Fetching file'),
      );
      if (!mounted) return;
      await _load();
      if (out != null && mounted) {
        ideSnack(
          context,
          out.ok
              ? tr('Đã lấy xong tệp', 'File fetched')
              : out.cancelled
              ? tr('Đã huỷ', 'Cancelled')
              : tr('Không lấy được tệp', 'Could not fetch the file'),
        );
      }
    } on Object catch (e) {
      if (mounted) ideSnack(context, ideFilesErrorText(e));
    }
  }

  // ---- bảng chọn ----

  Future<void> _plus() async {
    final c = await showWebTuiSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            WebTuiSheetHeader(
              title: tr('Thêm vào thư mục này', 'Add to this folder'),
            ),
            _tile(
              ctx,
              'new_file',
              Icons.note_add_outlined,
              tr('Tệp mới', 'New file'),
            ),
            _tile(
              ctx,
              'new_folder',
              Icons.create_new_folder_outlined,
              tr('Thư mục mới', 'New folder'),
            ),
            _tile(
              ctx,
              'upload',
              Icons.upload_file_rounded,
              tr('Tải tệp lên', 'Upload a file'),
            ),
            _tile(
              ctx,
              'upload_image',
              Icons.image_outlined,
              tr('Tải ảnh lên', 'Upload a photo'),
            ),
            _tile(
              ctx,
              'fetch',
              Icons.link_rounded,
              tr('Lấy từ liên kết', 'Get from link'),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
          ],
        ),
      ),
    );
    if (c == null || !mounted) return;
    switch (c) {
      case 'new_file':
        await _newFile();
      case 'new_folder':
        await _newFolder();
      case 'upload':
        await _upload(image: false);
      case 'upload_image':
        await _upload(image: true);
      case 'fetch':
        await _fetchUrl();
    }
  }

  Widget _tile(
    BuildContext ctx,
    String id,
    IconData icon,
    String title, {
    bool danger = false,
  }) => WebTuiSheetActionTile(
    key: Key('ide_act_$id'),
    icon: icon,
    title: title,
    tone: danger ? WebTuiDialogTone.danger : WebTuiDialogTone.normal,
    onTap: () => Navigator.of(ctx).pop(id),
  );

  Future<void> _actions(IdeFileEntry e) async {
    final textual = !e.isDir && ideFileKindOf(e.name) == IdeFileKind.code;
    final c = await showWebTuiSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            WebTuiSheetHeader(
              title: e.name,
              subtitle: e.secret
                  ? tr(
                      'Tệp bí mật: chỉ mở trên máy tính',
                      'Secret file: only opens on your computer',
                    )
                  : null,
            ),
            if (!e.secret) ...[
              _tile(ctx, 'open', Icons.open_in_new_rounded, tr('Mở', 'Open')),
              if (textual)
                _tile(ctx, 'edit', Icons.edit_outlined, tr('Sửa', 'Edit')),
              _tile(
                ctx,
                'ai',
                Icons.auto_awesome_rounded,
                tr('Hỏi AI về tệp này', 'Ask AI about this'),
              ),
            ],
            // Tệp bí mật: không đổi tên / chuyển chỗ (đổi `.env` thành tên
            // thường là thoát khỏi danh sách chặn), chỉ còn xoá.
            if (!e.secret) ...[
              _tile(
                ctx,
                'rename',
                Icons.drive_file_rename_outline_rounded,
                tr('Đổi tên', 'Rename'),
              ),
              _tile(ctx, 'copy', Icons.copy_rounded, tr('Sao chép', 'Copy')),
              _tile(ctx, 'cut', Icons.content_cut_rounded, tr('Cắt', 'Cut')),
            ],
            if (!e.secret && !e.isDir)
              _tile(
                ctx,
                'download',
                Icons.download_rounded,
                tr('Tải về máy', 'Download'),
              ),
            if (!e.secret)
              _tile(
                ctx,
                'zip',
                Icons.folder_zip_outlined,
                tr('Nén zip', 'Zip'),
              ),
            _tile(
              ctx,
              'path',
              Icons.link_rounded,
              tr('Chép đường dẫn', 'Copy path'),
            ),
            _tile(
              ctx,
              'delete',
              Icons.delete_outline_rounded,
              tr('Xoá', 'Delete'),
              danger: true,
            ),
            const SizedBox(height: WebTuiSpacing.sm),
          ],
        ),
      ),
    );
    if (c == null || !mounted) return;
    switch (c) {
      case 'open':
        _open(e);
      case 'edit':
        await _openEdit(e);
      case 'ai':
        await ideAskAiAboutPath(context, root: _root, path: e.path);
      case 'rename':
        await _rename(e);
      case 'copy':
        _clip(e, cut: false);
      case 'cut':
        _clip(e, cut: true);
      case 'download':
        await ideDownloadAndSave(context, ref, e.path, name: e.name);
      case 'zip':
        await _zip(e);
      case 'path':
        await ideCopyText(
          context,
          e.path,
          tr('Đã chép đường dẫn', 'Path copied'),
        );
      case 'delete':
        await _delete(e);
    }
  }

  Future<void> _openEdit(IdeFileEntry e) async {
    if (e.size > ideFileTextMaxBytes) {
      ideSnack(
        context,
        tr(
          'Tệp lớn hơn 3 MB, chỉ tải về được.',
          'File is larger than 3 MB, download only.',
        ),
      );
      return;
    }
    // Mở trình xem (đọc tệp) rồi người dùng bấm Sửa: một đường duy nhất.
    _open(e);
  }

  Future<void> _sortMenu() async {
    final cur = ref.read(ideFilesSortProvider);
    final hidden = ref.read(ideFilesShowHiddenProvider);
    final c = await showWebTuiSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            WebTuiSheetHeader(
              title: tr('Sắp xếp và hiển thị', 'Sort and show'),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_sort_name'),
              icon: Icons.sort_by_alpha_rounded,
              title: tr('Theo tên', 'By name'),
              selected: cur == IdeFileSort.name,
              onTap: () => Navigator.of(ctx).pop('name'),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_sort_date'),
              icon: Icons.schedule_rounded,
              title: tr('Theo ngày sửa', 'By date'),
              selected: cur == IdeFileSort.date,
              onTap: () => Navigator.of(ctx).pop('date'),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_sort_size'),
              icon: Icons.data_usage_rounded,
              title: tr('Theo dung lượng', 'By size'),
              selected: cur == IdeFileSort.size,
              onTap: () => Navigator.of(ctx).pop('size'),
            ),
            WebTuiSheetActionTile(
              key: const Key('ide_toggle_hidden'),
              icon: hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              title: hidden
                  ? tr('Ẩn tệp ẩn', 'Hide hidden files')
                  : tr('Hiện tệp ẩn', 'Show hidden files'),
              onTap: () => Navigator.of(ctx).pop('hidden'),
            ),
            const SizedBox(height: WebTuiSpacing.sm),
          ],
        ),
      ),
    );
    if (c == null || !mounted) return;
    switch (c) {
      case 'hidden':
        ref.read(ideFilesShowHiddenProvider.notifier).state = !hidden;
        await _load();
      default:
        ref.read(ideFilesSortProvider.notifier).state = switch (c) {
          'date' => IdeFileSort.date,
          'size' => IdeFileSort.size,
          _ => IdeFileSort.name,
        };
        setState(() {});
    }
  }

  Future<void> _projectMenu() async {
    final list = _projects ?? const [];
    final cur = _root;
    final p = await showWebTuiSheet<IdeProjectItem>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            WebTuiSheetHeader(title: tr('Chọn dự án', 'Choose project')),
            for (final p in list)
              WebTuiSheetActionTile(
                key: Key('ide_project_${p.name}'),
                icon: Icons.folder_special_outlined,
                title: p.name,
                selected: p.root == cur,
                onTap: () => Navigator.of(ctx).pop(p),
              ),
            const SizedBox(height: WebTuiSpacing.sm),
          ],
        ),
      ),
    );
    if (p != null && mounted) _pickProject(p);
  }

  void _push(Widget screen, {bool dark = false}) {
    unawaited(
      Navigator.of(
        context,
      ).push(IdePageRoute<void>(dark: dark, builder: (_) => screen)).then((_) {
        if (mounted) unawaited(_load());
      }),
    );
  }

  // ---- giao diện ----

  @override
  Widget build(BuildContext context) {
    final offline =
        ref.watch(ideLinkStatusProvider).valueOrNull?.phase ==
        IdeLinkPhase.offline;
    ref.watch(ideFilesSortProvider);
    final clip = ref.watch(ideFilesClipboardProvider);
    final loc = ref.watch(ideFilesLocationProvider);
    final projects = _projects;

    Widget body;
    if (_projectsError != null) {
      body = _errorView(_projectsError!, () => _init(refresh: true));
    } else if (projects != null && projects.isEmpty && !_loading) {
      body = WebTuiEmptyState(
        icon: Icons.folder_off_outlined,
        title: tr('Chưa có dự án', 'No projects yet'),
        message: tr(
          'Tài khoản này chưa có dự án nào trên IDE.',
          'This account has no projects on the IDE yet.',
        ),
      );
    } else if (projects == null || loc == null) {
      body = WebTuiLoadingState(
        message: tr('Đang mở tệp...', 'Opening files...'),
      );
    } else {
      body = Column(
        children: [
          _header(loc, projects),
          if (clip != null) _clipBar(clip),
          Expanded(child: _list(offline)),
        ],
      );
    }
    final atRoot = loc == null || loc.dir == loc.root;
    return PopScope(
      canPop: atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && loc != null) _goTo(ideParentPath(loc.dir));
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: body,
        floatingActionButton: loc == null
            ? null
            : FloatingActionButton(
                key: const Key('ide_files_plus'),
                tooltip: tr('Thêm', 'Add'),
                onPressed: _busy ? null : _plus,
                child: const Icon(Icons.add_rounded),
              ),
      ),
    );
  }

  Widget _header(IdeFilesLocation loc, List<IdeProjectItem> projects) {
    IdeProjectItem? cur;
    for (final p in projects) {
      if (p.root == loc.root) cur = p;
    }
    final crumbs = ideBreadcrumbs(loc.root, loc.dir, rootLabel: cur?.name);
    const btn = BoxConstraints(minWidth: 48, minHeight: 48);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: IdeWb.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.sm,
              WebTuiSpacing.xs,
              WebTuiSpacing.xs,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _projectButton(
                    cur?.name ?? ideBaseName(loc.root),
                    many: projects.length > 1,
                  ),
                ),
                IconButton(
                  key: const Key('ide_files_search'),
                  tooltip: tr('Tìm', 'Search'),
                  constraints: btn,
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => _push(IdeFilesSearchScreen(root: loc.root)),
                ),
                if (cur?.git ?? true)
                  IconButton(
                    key: const Key('ide_files_changes'),
                    tooltip: tr('Thay đổi git', 'Git changes'),
                    constraints: btn,
                    icon: const Icon(Icons.difference_outlined),
                    onPressed: () =>
                        _push(IdeDiffScreen(root: loc.root), dark: true),
                  ),
                PopupMenuButton<String>(
                  key: const Key('ide_files_menu'),
                  tooltip: tr('Thêm', 'More'),
                  constraints: const BoxConstraints(minWidth: 200),
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (v) => v == 'trash'
                      ? _push(IdeTrashScreen(root: loc.root))
                      : unawaited(_sortMenu()),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      key: const Key('ide_files_sort'),
                      value: 'sort',
                      child: _menuRow(
                        Icons.tune_rounded,
                        tr('Sắp xếp và hiển thị', 'Sort and show'),
                      ),
                    ),
                    PopupMenuItem(
                      key: const Key('ide_files_trash'),
                      value: 'trash',
                      child: _menuRow(
                        Icons.delete_outline_rounded,
                        tr('Thùng rác', 'Trash'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Ở gốc dự án thì không cần thanh đường dẫn (tên dự án đã ở trên).
          if (crumbs.length > 1)
            SizedBox(
              height: 44,
              child: ListView.separated(
                key: const Key('ide_breadcrumbs'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: WebTuiSpacing.md,
                ),
                itemCount: crumbs.length,
                separatorBuilder: (_, _) => Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: IdeWb.text2,
                ),
                itemBuilder: (_, i) {
                  final (label, path) = crumbs[i];
                  return _crumb(
                    label,
                    root: i == 0,
                    last: i == crumbs.length - 1,
                    onTap: () => _goTo(path),
                  );
                },
              ),
            )
          else
            const SizedBox(height: WebTuiSpacing.xs),
        ],
      ),
    );
  }

  /// Nút chọn dự án: ô biểu tượng màu + tên đậm + mũi tên khi có nhiều dự án.
  Widget _projectButton(String name, {required bool many}) {
    return InkWell(
      key: const Key('ide_project_picker'),
      onTap: many ? _projectMenu : null,
      borderRadius: BorderRadius.circular(WebTuiRadii.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: IdeWb.accentSoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.folder_rounded,
                  size: 18,
                  color: IdeWb.accentInk,
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm + 2),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IdeType.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (many)
                Padding(
                  padding: const EdgeInsets.only(left: WebTuiSpacing.xxs),
                  child: Icon(
                    Icons.unfold_more_rounded,
                    size: 18,
                    color: IdeWb.text2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 20, color: IdeWb.text),
      const SizedBox(width: WebTuiSpacing.md),
      Text(text, style: IdeType.bodyMedium),
    ],
  );

  /// Một chặng đường dẫn: viên thuốc chữ mono; chặng cuối tô nền nhạt.
  /// Gốc chỉ hiện biểu tượng nhà (tên dự án đã ở nút chọn dự án phía trên).
  Widget _crumb(
    String label, {
    required bool root,
    required bool last,
    required VoidCallback onTap,
  }) {
    final color = last ? IdeWb.accentInk : IdeWb.text;
    return Semantics(
      button: !last,
      label: root ? tr('Gốc dự án $label', 'Project root $label') : label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        onTap: last ? null : onTap,
        child: Center(
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: last ? IdeWb.accentSoft : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: root
                ? Icon(Icons.home_rounded, size: 17, color: color)
                : Text(
                    label,
                    style: WebTuiTypography.mono(
                      size: 13,
                      weight: last ? FontWeight.w600 : FontWeight.w500,
                      color: color,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _clipBar(IdeFileClip clip) {
    final into = clip.isDir && ideIsInside(clip.path, _dir);
    return Container(
      color: IdeWb.accentSoft,
      padding: const EdgeInsets.symmetric(
        horizontal: WebTuiSpacing.lg,
        vertical: WebTuiSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              clip.cut
                  ? tr('Đã cắt: ${clip.name}', 'Cut: ${clip.name}')
                  : tr('Đã chép: ${clip.name}', 'Copied: ${clip.name}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IdeType.bodyMedium,
            ),
          ),
          TextButton(
            key: const Key('ide_paste'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy || into ? null : _paste,
            child: Text(tr('Dán vào đây', 'Paste here')),
          ),
          IconButton(
            key: const Key('ide_paste_cancel'),
            tooltip: tr('Bỏ', 'Clear'),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.close_rounded),
            onPressed: () =>
                ref.read(ideFilesClipboardProvider.notifier).state = null,
          ),
        ],
      ),
    );
  }

  Widget _errorView(Object e, VoidCallback retry) {
    if (e is IdeOffline) {
      return WebTuiErrorState(
        title: tr('IDE đang ngoại tuyến', 'IDE is offline'),
        message: tr(
          'Hãy mở IDE trên máy tính và kiểm tra mạng.',
          'Open the IDE on your computer and check the network.',
        ),
        onRetry: retry,
      );
    }
    if (e is IdeForbidden) {
      return WebTuiEmptyState(
        icon: Icons.lock_outline_rounded,
        title: tr('Không có quyền xem', 'No access'),
        message: ideFilesErrorText(e),
      );
    }
    return WebTuiErrorState(
      title: tr('Không mở được thư mục', 'Could not open the folder'),
      message: ideFilesErrorText(e),
      onRetry: retry,
    );
  }

  Widget _list(bool offline) {
    if (_loading) {
      return WebTuiLoadingState(
        message: tr('Đang mở thư mục...', 'Opening the folder...'),
      );
    }
    final e = _error;
    if (e != null) return _errorView(offline ? const IdeOffline() : e, _load);
    final items = _sorted;
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 48),
            WebTuiEmptyState(
              icon: Icons.folder_open_rounded,
              title: tr('Thư mục trống', 'Empty folder'),
              message: tr(
                'Bấm + để tạo tệp, thư mục hoặc tải lên.',
                'Tap + to create a file, folder or upload.',
              ),
            ),
          ],
        ),
      );
    }
    // Danh sách trong một thẻ bo góc (kiểu Files / Working Copy). Đệm dưới
    // 96 để nút + nổi không che nút ⋮ của hàng cuối.
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        key: const Key('ide_files_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.md,
              WebTuiSpacing.md,
              WebTuiSpacing.md,
              96,
            ),
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: IdeWb.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: IdeWb.border),
              ),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  thickness: 1,
                  indent: 54,
                  color: IdeWb.border,
                ),
                itemBuilder: (_, i) => _row(
                  items[i],
                  radius: BorderRadius.vertical(
                    top: Radius.circular(i == 0 ? 14 : 0),
                    bottom: Radius.circular(i == items.length - 1 ? 14 : 0),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IdeFileEntry e, {BorderRadius? radius}) {
    final sub = <String>[
      if (e.secret)
        tr('Chỉ mở trên máy tính', 'Only opens on your computer')
      else ...[
        if (!e.isDir) ideFormatSize(e.size),
        ideShortDate(e.mtime),
      ],
    ].where((s) => s.isNotEmpty).join(' · ');
    final gitLabel = ideGitLabel(e.git);
    final tint = ideEntryTint(e);
    return Semantics(
      label: [
        e.isDir ? tr('Thư mục', 'Folder') : tr('Tệp', 'File'),
        e.name,
        if (gitLabel.isNotEmpty) gitLabel,
        sub,
      ].join(', '),
      excludeSemantics: true,
      onTap: () => _open(e),
      onLongPress: () => _actions(e),
      // Material trong suốt để hiệu ứng chạm vẽ trên nền thẻ.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('ide_entry_${e.name}'),
          borderRadius: radius,
          onTap: () => _open(e),
          onLongPress: () => unawaited(_actions(e)),
          child: ConstrainedBox(
            // Một dòng gọn như cây tệp IDE web: xem được nhiều tệp một lúc.
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.only(left: WebTuiSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(ideEntryIcon(e), size: 16, color: tint),
                  ),
                  const SizedBox(width: WebTuiSpacing.sm + 2),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IdeType.bodyMedium.copyWith(
                          color: e.isHidden ? IdeWb.text : IdeWb.textStrong,
                        ),
                      ),
                    ),
                  ),
                  if (sub.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Padding(
                        padding: const EdgeInsets.only(left: WebTuiSpacing.sm),
                        child: Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: IdeType.bodySmall.copyWith(
                            fontSize: 11.5,
                            color: IdeWb.text2,
                          ),
                        ),
                      ),
                    ),
                  if (e.git.isNotEmpty)
                    Container(
                      key: Key('ide_git_${e.name}'),
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(left: WebTuiSpacing.xs),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ideGitColor(e.git).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        e.git,
                        style: WebTuiTypography.mono(
                          size: 12,
                          weight: FontWeight.w700,
                          color: IdeWb.textStrong,
                        ),
                      ),
                    ),
                  if (e.secret)
                    Padding(
                      padding: const EdgeInsets.only(left: WebTuiSpacing.xs),
                      child: Icon(
                        Icons.lock_rounded,
                        size: 18,
                        color: IdeWb.text2,
                      ),
                    ),
                  IconButton(
                    key: Key('ide_more_${e.name}'),
                    tooltip: tr('Thao tác', 'Actions'),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: IdeWb.text2,
                    ),
                    onPressed: () => unawaited(_actions(e)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewFileDialog extends StatefulWidget {
  const _NewFileDialog();

  @override
  State<_NewFileDialog> createState() => _NewFileDialogState();
}

class _NewFileDialogState extends State<_NewFileDialog> {
  final _name = TextEditingController();
  bool _agents = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final err = ideNameErrorText(name);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop((name: name, agents: _agents));
  }

  @override
  Widget build(BuildContext context) {
    return WebTuiDialog(
      title: tr('Tệp mới', 'New file'),
      icon: Icons.note_add_outlined,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebTuiDialogTextField(
            controller: _name,
            label: tr('Tên tệp', 'File name'),
            maxLength: 255,
            autofocus: true,
            errorText: _error,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          CheckboxListTile(
            key: const Key('ide_new_agents'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _agents,
            title: Text(tr('Dùng mẫu AGENTS.md', 'Use the AGENTS.md template')),
            onChanged: (v) => setState(() {
              _agents = v ?? false;
              if (_agents && _name.text.trim().isEmpty) {
                _name.text = 'AGENTS.md';
              }
            }),
          ),
        ],
      ),
      actions: [
        WebTuiDialogAction(
          label: tr('Huỷ', 'Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        WebTuiDialogAction(
          key: const Key('ide_new_file_ok'),
          label: tr('Tạo', 'Create'),
          primary: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}
