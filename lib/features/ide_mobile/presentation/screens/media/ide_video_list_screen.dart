import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_appscreen_controller.dart' show ideLastLines;
import '../../../application/ide_media_service.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_media_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../controllers/ide_project_ops_controllers.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';
import 'ide_media_common.dart';

/// Nhãn + màu trạng thái video.
(String, Color) ideVideoStateTag(String state) =>
    switch (IdeVideoState.parse(state)) {
      IdeVideoState.daXuat => (tr('Đã xuất', 'Exported'), IdeWb.ok),
      IdeVideoState.nhap => (tr('Bản nháp', 'Draft'), IdeWb.warn),
      IdeVideoState.kichBan => (tr('Kịch bản', 'Script'), IdeWb.text),
      IdeVideoState.loi => (tr('Lỗi', 'Error'), IdeWb.danger),
      null => (state.isEmpty ? '—' : ideVisibleText(state), IdeWb.text2),
    };

/// Studio video: danh sách video của dự án (xem, tải; không dựng / lưu).
class IdeVideoListScreen extends ConsumerWidget {
  const IdeVideoListScreen({
    this.project,
    this.refreshInterval = const Duration(seconds: 5),
    super.key,
  });

  final String? project;
  final Duration refreshInterval;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Chưa ready / thiếu op: hiện trạng thái, không gọi `video.list`.
    final gate = ideMediaGate(ref, const ['video.list']);
    return IdeMorePage(
      title: tr('Studio video', 'Video studio'),
      body:
          gate ??
          IdeProjectScope(
            initial: project,
            builder: (context, p) => _VideoListBody(
              project: p.name,
              refreshInterval: refreshInterval,
            ),
          ),
    );
  }
}

class _VideoListBody extends ConsumerStatefulWidget {
  const _VideoListBody({required this.project, required this.refreshInterval});

  final String project;
  final Duration refreshInterval;

  @override
  ConsumerState<_VideoListBody> createState() => _VideoListBodyState();
}

class _VideoListBodyState extends ConsumerState<_VideoListBody>
    with IdeMediaActiveState<_VideoListBody> {
  late final IdePoller _poller;
  List<IdeVideoRow>? _rows;
  Object? _error;
  bool _loading = true;
  bool _syncing = false;
  List<String> _log = const [];
  int _seq = 0;
  bool _disposed = false;

  IdeMediaService get _svc => ref.read(ideMediaServiceProvider);

  @override
  void initState() {
    super.initState();
    _poller = IdePoller(
      interval: widget.refreshInterval,
      // Chỉ hỏi lại khi có video đang chạy, màn đang hiện, không đang đồng bộ.
      shouldRun: () =>
          !_disposed &&
          mediaActive &&
          !_syncing &&
          (_rows?.any((r) => r.running) ?? false),
      task: () => _load(silent: true),
    );
    unawaited(_load());
  }

  @override
  void onMediaResumed() {
    if (_rows?.any((r) => r.running) ?? false) unawaited(_poller.poke());
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final seq = ++_seq;
    if (!silent && _rows == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _svc.videoList(widget.project);
      if (!mounted || seq != _seq) return;
      _setRows(rows);
    } on Object catch (e) {
      if (!mounted || seq != _seq) return;
      if (_rows != null) {
        if (!silent) _snack(ideMoreErrorText(e));
        return;
      }
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _setRows(List<IdeVideoRow> rows) {
    setState(() {
      _rows = rows;
      _loading = false;
      _error = null;
    });
    if (rows.any((r) => r.running)) {
      _poller.start();
    } else {
      _poller.stop();
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Đồng bộ từ máy dựng (`video.list {sync:true}`, việc nền).
  Future<void> _sync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _log = const [];
    });
    try {
      final job = await _svc.videoSync(widget.project);
      final out = await ref
          .read(ideProjectServiceProvider)
          .waitJob(
            job,
            isCancelled: () => _disposed,
            onLog: (t) {
              if (mounted) setState(() => _log = ideLastLines(t, 14));
            },
          );
      if (!mounted) return;
      if (out.ok && out.result is Map) {
        _setRows(ideParseVideoList(out.result));
      } else if (out.ok) {
        await _load(silent: true);
      } else {
        _snack(
          _log.isNotEmpty
              ? ideVisibleText(_log.last)
              : tr('Đồng bộ chưa xong.', 'Sync did not finish.'),
        );
      }
    } on IdeCancelled {
      // Huỷ do rời màn: không còn gì để cập nhật; ngoài ra nhả cờ ở finally.
    } on Object catch (e) {
      if (mounted) _snack(ideMoreErrorText(e));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows == null) {
      if (_loading) {
        return WebTuiLoadingState(message: tr('Đang tải...', 'Loading...'));
      }
      final error = _error ?? const IdeError();
      // Thẻ báo chỉ cao theo nội dung, không kéo hết màn.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dự án không làm video (`bad_request`): không phải lỗi mạng, thử lại
          // cũng vậy, nên không có nút Thử lại.
          if (error is IdeBadRequest)
            WebTuiEmptyState(
              key: const Key('ide_video_not_video'),
              title: tr('Không có video', 'No videos'),
              message: error.message.isEmpty
                  ? tr(
                      'Dự án này không phải dự án Video.',
                      'This is not a video project.',
                    )
                  : ideVisibleText(error.message),
              icon: Icons.movie_outlined,
            )
          else
            IdeMoreErrorView(error: error, onRetry: _load),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.xs,
            WebTuiSpacing.lg,
            0,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('ide_video_sync'),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: _syncing ? null : _sync,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(tr('Đồng bộ', 'Sync')),
            ),
          ),
        ),
        if (_syncing && _log.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                ideVisibleText(_log.last),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _sync,
            child: rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 320,
                        child: WebTuiEmptyState(
                          title: tr('Chưa có video', 'No videos yet'),
                          message: tr(
                            'Dự án này chưa có video. Kéo xuống để đồng bộ.',
                            'This project has no videos yet. Pull down to sync.',
                          ),
                          icon: Icons.movie_outlined,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(WebTuiSpacing.lg),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: WebTuiSpacing.sm),
                    itemBuilder: (context, i) => _VideoCard(
                      row: rows[i],
                      onTap: () => context.push(
                        Uri(
                          path: '/ide/video/${rows[i].slug}',
                          queryParameters: {'project': widget.project},
                        ).toString(),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.row, required this.onTap});

  final IdeVideoRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = ideVideoStateTag(row.state);
    final st = row.status;
    final muted = IdeType.bodySmall.copyWith(color: IdeWb.text2);
    final scenes = row.scenes == null
        ? '—'
        : '${row.scenes} ${tr('cảnh', 'scenes')}';
    return IdeCard(
      key: Key('ide_video_${row.slug}'),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  ideVisibleText(row.title),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: IdeType.titleMedium,
                ),
              ),
              const SizedBox(width: WebTuiSpacing.sm),
              IdeTag(label, color: color),
            ],
          ),
          const SizedBox(height: WebTuiSpacing.xs),
          Text(
            [
              if (row.ratio.isNotEmpty) ideVisibleText(row.ratio),
              scenes,
              ideMediaDuration(row.seconds),
            ].join(' · '),
            style: muted,
          ),
          if (st != null && st.running) ...[
            const SizedBox(height: WebTuiSpacing.sm),
            LinearProgressIndicator(
              key: Key('ide_video_progress_${row.slug}'),
              value: st.fraction,
            ),
            const SizedBox(height: WebTuiSpacing.xs),
            Text(
              [
                if (st.step.isNotEmpty) ideVisibleText(st.step),
                if (st.done != null && st.total != null)
                  '${st.done}/${st.total}',
                if (st.note.isNotEmpty) ideVisibleText(st.note),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ] else if (IdeVideoState.parse(row.state) == IdeVideoState.loi &&
              row.error.isNotEmpty)
            Text(
              ideVisibleText(row.error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IdeType.bodySmall.copyWith(color: IdeWb.danger),
            ),
        ],
      ),
    );
  }
}
