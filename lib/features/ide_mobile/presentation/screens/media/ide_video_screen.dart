import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_download_service.dart';
import '../../../application/ide_media_service.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_media_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../controllers/ide_project_controllers.dart';
import '../../widgets/files/ide_image_viewer.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';
import 'ide_media_common.dart';
import 'ide_video_list_screen.dart' show ideVideoStateTag;

class _Loaded {
  const _Loaded(this.detail, this.root);
  final IdeVideoDetail detail;
  final String root;
}

/// Một video: các cảnh (chữ, phụ đề, ảnh bấm mới tải), xem / lưu video.
class IdeVideoScreen extends ConsumerWidget {
  const IdeVideoScreen({required this.project, required this.slug, super.key});

  final String project;
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(ideMediaServiceProvider);
    final gate = ideMediaGate(ref, const ['video.get']);
    return IdeMorePage(
      title: tr('Studio video', 'Video studio'),
      body:
          gate ??
          IdeLoader<_Loaded>(
            load: () async {
              final projects = await ref.read(ideProjectsProvider.future);
              final p = projects.where((e) => e.name == project).firstOrNull;
              if (p == null) {
                throw const IdeNotFound('Không tìm thấy dự án này.');
              }
              return _Loaded(await svc.videoGet(project, slug), p.root);
            },
            builder: (context, d, reload) =>
                _VideoBody(data: d, reload: reload),
          ),
    );
  }
}

class _VideoBody extends ConsumerStatefulWidget {
  const _VideoBody({required this.data, required this.reload});

  final _Loaded data;
  final Future<void> Function() reload;

  @override
  ConsumerState<_VideoBody> createState() => _VideoBodyState();
}

class _VideoBodyState extends ConsumerState<_VideoBody> {
  final _busy = <String>{};
  final _thumbs = <int, IdeDownloadedFile>{};
  final _live = <IdeDownload>{};
  // Tệp đã tải theo khoá: bấm lại dùng luôn, dọn khi rời màn.
  final _files = <String, IdeDownloadedFile>{};
  final _tooBig = <String>{};
  late final IdeDownloadService _dl;

  @override
  void initState() {
    super.initState();
    _dl = ref.read(ideDownloadServiceProvider);
  }

  @override
  void dispose() {
    for (final d in _live) {
      d.cancel();
    }
    for (final f in {..._thumbs.values, ..._files.values}) {
      unawaited(_dl.discard(f));
    }
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Tải `<root>/<tương đối>`; `null` nếu bị chặn / quá lớn / lỗi (đã báo).
  Future<IdeDownloadedFile?> _fetch(
    String key,
    String? rel,
    int maxBytes,
  ) async {
    final have = _files[key];
    if (have != null) return have;
    if (_busy.contains(key)) return null;
    final path = ideMediaJoin(widget.data.root, rel);
    if (path == null) {
      _snack(tr('Đường dẫn tệp không hợp lệ.', 'Invalid file path.'));
      return null;
    }
    setState(() => _busy.add(key));
    final d = _dl.start(path, maxBytes: maxBytes);
    _live.add(d);
    try {
      final f = await d.done;
      if (!mounted) {
        await _dl.discard(f);
        return null;
      }
      _files[key] = f;
      return f;
    } on IdeDownloadCancelled {
      return null;
    } on IdeDownloadTooLarge {
      _markTooBig(key);
      return null;
    } on IdeTooLarge {
      _markTooBig(key);
      return null;
    } on Object catch (e) {
      _snack(ideMoreErrorText(e));
      return null;
    } finally {
      _live.remove(d);
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  void _markTooBig(String key) {
    if (!mounted) return;
    setState(() => _tooBig.add(key));
    _snack(
      tr(
        'Tệp quá lớn cho điện thoại: Mở trên máy tính.',
        'File too large for the phone: open it on the computer.',
      ),
    );
  }

  Future<void> _openImage(String key, String? rel) async {
    final f = await _fetch(key, rel, ideVideoImageMaxBytes);
    if (f == null || !mounted) return;
    await Navigator.of(
      context,
    ).push<void>(IdePageRoute(builder: (_) => IdeImageViewer(file: f)));
  }

  /// [idx] là vị trí trong danh sách (khoá riêng): `n` từ IDE chỉ để hiển thị.
  Future<void> _thumb(int idx, IdeVideoScene s) async {
    final have = _thumbs[idx];
    if (have != null) {
      await Navigator.of(
        context,
      ).push<void>(IdePageRoute(builder: (_) => IdeImageViewer(file: have)));
      return;
    }
    final f = await _fetch('scene$idx', s.image, ideVideoImageMaxBytes);
    if (f == null || !mounted) return;
    setState(() => _thumbs[idx] = f);
  }

  Future<void> _play(String key, String? rel) async {
    final f = await _fetch(key, rel, ideVideoFileMaxBytes);
    if (f == null || !mounted) return;
    await Navigator.of(
      context,
    ).push<void>(IdePageRoute(builder: (_) => _VideoPlayerScreen(file: f)));
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data.detail;
    final v = d.video;
    final (label, color) = ideVideoStateTag(v.state);
    final muted = IdeType.bodySmall.copyWith(color: IdeWb.text2);
    Widget action(
      String key,
      String text,
      IconData icon,
      String? rel,
      int cap, {
      bool image = false,
    }) {
      if (rel == null) return const SizedBox.shrink();
      final big = _tooBig.contains(key);
      return OutlinedButton.icon(
        key: Key('ide_video_$key'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
        onPressed: _busy.contains(key) || big
            ? null
            : () => image ? _openImage(key, rel) : _play(key, rel),
        icon: _busy.contains(key)
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        label: Text(
          big ? tr('Mở trên máy tính', 'Open on the computer') : text,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.reload,
      child: ListView(
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  ideVisibleText(v.title),
                  key: const Key('ide_video_title'),
                  style: IdeType.titleLarge,
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              IdeTag(label, color: color),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          Text(
            [
              if (v.ratio.isNotEmpty) ideVisibleText(v.ratio),
              v.scenes == null ? '—' : '${v.scenes} ${tr('cảnh', 'scenes')}',
              ideMediaDuration(v.seconds),
            ].join(' · '),
            style: muted,
          ),
          if (d.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
              child: Text(
                ideVisibleText(d.error),
                key: const Key('ide_video_error'),
                style: IdeType.bodySmall.copyWith(color: IdeWb.danger),
              ),
            ),
          const SizedBox(height: WebTuiSpacing.md),
          Wrap(
            spacing: WebTuiSpacing.sm,
            runSpacing: WebTuiSpacing.sm,
            children: [
              action(
                'play',
                tr('Xem video', 'Play video'),
                Icons.play_circle_outline_rounded,
                v.video,
                ideVideoFileMaxBytes,
              ),
              action(
                'draft',
                tr('Xem bản nháp', 'Play draft'),
                Icons.play_arrow_rounded,
                v.draft,
                ideVideoFileMaxBytes,
              ),
              action(
                'cover',
                tr('Ảnh bìa', 'Cover'),
                Icons.image_outlined,
                v.cover,
                ideVideoImageMaxBytes,
                image: true,
              ),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.lg),
          Text(tr('Các cảnh', 'Scenes'), style: IdeType.titleMedium),
          const SizedBox(height: WebTuiSpacing.sm),
          if (d.scenes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.lg),
              child: Text(
                d.error.isNotEmpty
                    ? tr('Không đọc được các cảnh.', 'Could not read scenes.')
                    : tr(
                        'Video này chưa có cảnh.',
                        'This video has no scenes.',
                      ),
                key: const Key('ide_video_no_scenes'),
                style: muted,
              ),
            )
          else
            for (final (idx, s) in d.scenes.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                child: _SceneCard(
                  scene: s,
                  thumb: _thumbs[idx],
                  busy: _busy.contains('scene$idx'),
                  tooBig: _tooBig.contains('scene$idx'),
                  onThumb: () => _thumb(idx, s),
                ),
              ),
        ],
      ),
    );
  }
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({
    required this.scene,
    required this.thumb,
    required this.busy,
    required this.tooBig,
    required this.onThumb,
  });

  final IdeVideoScene scene;
  final IdeDownloadedFile? thumb;
  final bool busy;
  final bool tooBig;
  final VoidCallback onThumb;

  @override
  Widget build(BuildContext context) {
    final muted = IdeType.bodySmall.copyWith(color: IdeWb.text2);
    return IdeCard(
      key: Key('ide_scene_${scene.n}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${tr('Cảnh', 'Scene')} ${scene.n}', style: IdeType.titleMedium),
          if (scene.text.isNotEmpty) ...[
            const SizedBox(height: WebTuiSpacing.xs),
            Text(ideVisibleText(scene.text), style: IdeType.bodyMedium),
          ],
          if (scene.caption.isNotEmpty) ...[
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              '${tr('Phụ đề', 'Caption')}: ${ideVisibleText(scene.caption)}',
              style: muted,
            ),
          ],
          if (scene.image != null) ...[
            const SizedBox(height: WebTuiSpacing.sm),
            if (thumb != null)
              InkWell(
                key: Key('ide_scene_img_${scene.n}'),
                borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                onTap: onThumb,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(WebTuiRadii.sm),
                  child: Image(
                    image: ideBoundedImage(thumb!.file),
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(height: 44),
                  ),
                ),
              )
            else
              TextButton.icon(
                key: Key('ide_scene_load_${scene.n}'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: busy || tooBig ? null : onThumb,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined),
                label: Text(
                  tooBig
                      ? tr('Mở trên máy tính', 'Open on the computer')
                      : tr('Xem ảnh', 'Show image'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Phát video đã tải (như màn xem tệp), có nút Lưu về máy.
class _VideoPlayerScreen extends ConsumerStatefulWidget {
  const _VideoPlayerScreen({required this.file});

  final IdeDownloadedFile file;

  @override
  ConsumerState<_VideoPlayerScreen> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends ConsumerState<_VideoPlayerScreen> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(
      File(widget.file.file.path),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await c.initialize();
    } on Object {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    c.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _c = c);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          ideVisibleText(widget.file.name),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: tr('Lưu về máy', 'Save to device'),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.save_alt_rounded),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final note = await ref
                  .read(ideDownloadServiceProvider)
                  .save(widget.file);
              if (note != null) {
                messenger.showSnackBar(SnackBar(content: Text(note)));
              }
            },
          ),
        ],
      ),
      body: _failed
          ? Center(
              child: Text(
                tr('Không phát được video này.', 'Cannot play this video.'),
                style: const TextStyle(color: Colors.white),
              ),
            )
          : c == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: c.value.aspectRatio <= 0
                          ? 16 / 9
                          : c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
                  ),
                ),
                VideoProgressIndicator(c, allowScrubbing: true),
                IconButton(
                  key: const Key('ide_video_toggle'),
                  iconSize: 36,
                  color: Colors.white,
                  tooltip: c.value.isPlaying
                      ? tr('Dừng', 'Pause')
                      : tr('Phát', 'Play'),
                  icon: Icon(
                    c.value.isPlaying
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                  ),
                  onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
                ),
                const SafeArea(top: false, child: SizedBox(height: 8)),
              ],
            ),
    );
  }
}
