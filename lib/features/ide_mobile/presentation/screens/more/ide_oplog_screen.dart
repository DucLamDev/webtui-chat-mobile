import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_log_models.dart';
import '../../../domain/ide_more_time.dart';
import '../../controllers/ide_more_controllers.dart';
import 'ide_more_common.dart';

String ideOplogKindLabel(String kind) => switch (kind) {
  'ai' => 'AI',
  'deploy' => tr('Triển khai', 'Deploy'),
  'git' => 'Git',
  'agent' => tr('AI Agent', 'AI Agent'),
  'quick' => tr('Thao tác nhanh', 'Quick'),
  'ssh' => 'SSH',
  'admin' => tr('Quản trị', 'Admin'),
  _ => kind,
};

/// Nhật ký thao tác: lọc loại / số ngày, tìm, tải thêm theo `before: next`.
class IdeOplogScreen extends ConsumerWidget {
  const IdeOplogScreen({this.project, super.key});

  final String? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IdeMorePage(
      title: tr('Nhật ký thao tác', 'Activity log'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) => _OplogBody(project: p.name),
      ),
    );
  }
}

const _dayOptions = [1, 7, 30, 90];

class _OplogBody extends ConsumerStatefulWidget {
  const _OplogBody({required this.project});

  final String project;

  @override
  ConsumerState<_OplogBody> createState() => _OplogBodyState();
}

class _OplogBodyState extends ConsumerState<_OplogBody> {
  final _search = TextEditingController();
  int _kind = 0; // 0 = tất cả, 1.. = ideOplogKinds
  int _days = 1; // chỉ số trong _dayOptions (mặc định 7 ngày)
  String _q = '';
  IdeOplogFeed? _feed;
  Object? _error;
  bool _loading = true;
  bool _more = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _kinds => _kind == 0 ? const [] : [ideOplogKinds[_kind - 1]];

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
      _more = false;
    });
    try {
      final page = await ref
          .read(ideMoreServiceProvider)
          .oplog(
            widget.project,
            days: _dayOptions[_days],
            kinds: _kinds,
            q: _q,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        _feed = IdeOplogFeed.first(page);
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final feed = _feed;
    if (feed == null || !feed.hasMore || _more) return;
    final seq = _seq;
    setState(() => _more = true);
    try {
      final page = await ref
          .read(ideMoreServiceProvider)
          .oplog(
            widget.project,
            days: _dayOptions[_days],
            before: feed.next,
            kinds: _kinds,
            q: _q,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        _feed = feed.append(page);
        _more = false;
      });
    } on Object catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _more = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ideMoreErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.xs,
            WebTuiSpacing.lg,
            0,
          ),
          child: WebTuiSearchBar(
            hintText: tr('Tìm trong nhật ký', 'Search the log'),
            controller: _search,
            onChanged: (v) {
              final q = v.trim();
              if (q == _q) return;
              _q = q;
              _load();
            },
          ),
        ),
        WebTuiFilterChipBar(
          chips: [
            WebTuiFilterChipData(label: tr('Tất cả', 'All')),
            for (final k in ideOplogKinds)
              WebTuiFilterChipData(label: ideOplogKindLabel(k)),
          ],
          selectedIndex: _kind,
          onSelected: (i) {
            setState(() => _kind = i);
            _load();
          },
          semanticLabel: tr('Lọc loại', 'Filter by kind'),
        ),
        WebTuiFilterChipBar(
          chips: [
            for (final d in _dayOptions)
              WebTuiFilterChipData(
                label: d == 1
                    ? tr('Hôm nay', 'Today')
                    : '$d ${tr('ngày', 'days')}',
              ),
          ],
          selectedIndex: _days,
          onSelected: (i) {
            setState(() => _days = i);
            _load();
          },
          semanticLabel: tr('Khoảng thời gian', 'Time range'),
        ),
        Expanded(child: _content(feed)),
      ],
    );
  }

  Widget _content(IdeOplogFeed? feed) {
    if (_loading && feed == null) {
      return WebTuiLoadingState(message: tr('Đang tải...', 'Loading...'));
    }
    if (_error != null && feed == null) {
      return IdeMoreErrorView(error: _error!, onRetry: _load);
    }
    if (_error != null) {
      return IdeMoreErrorView(error: _error!, onRetry: _load);
    }
    if (_loading) {
      return WebTuiLoadingState(message: tr('Đang tải...', 'Loading...'));
    }
    if (feed == null || feed.events.isEmpty) {
      return WebTuiEmptyState(
        title: tr('Không có thao tác', 'Nothing here'),
        message: tr(
          'Không có thao tác nào khớp bộ lọc này.',
          'No activity matches these filters.',
        ),
        icon: Icons.history_rounded,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        key: const Key('ide_oplog_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        itemCount: feed.events.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
              child: Text(
                '${feed.matched > 0 ? feed.matched : feed.events.length} '
                '${tr('thao tác', 'events')}'
                '${feed.bad > 0 ? ' · ${feed.bad} ${tr('lỗi', 'failed')}' : ''}',
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
            );
          }
          if (i == feed.events.length + 1) {
            if (!feed.hasMore) return const SizedBox(height: 16);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
              child: Center(
                child: _more
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : OutlinedButton(
                        key: const Key('ide_oplog_more'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(160, 44),
                        ),
                        onPressed: _loadMore,
                        child: Text(tr('Tải thêm', 'Load more')),
                      ),
              ),
            );
          }
          return _EventTile(feed.events[i - 1]);
        },
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.e);
  final IdeOpEvent e;

  @override
  Widget build(BuildContext context) {
    final color = switch (e.level) {
      'bad' => WebTuiColors.danger,
      'ok' => WebTuiColors.accentGreen,
      _ => WebTuiColors.textSecondary,
    };
    final t = e.time;
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
      child: IdeCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IdeTag(ideOplogKindLabel(e.kind), color: color),
                const SizedBox(width: WebTuiSpacing.sm),
                Expanded(
                  child: Text(
                    e.action,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.bodyMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (t != null)
                  Text(
                    ideFormatDateTime(t),
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
              ],
            ),
            if (e.detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                child: Text(
                  e.detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: WebTuiTypography.bodySmall.copyWith(
                    color: WebTuiColors.textSecondary,
                  ),
                ),
              ),
            Text(
              [
                if (e.user.isNotEmpty) e.user,
                if (e.target.isNotEmpty) e.target,
                if (e.name.isNotEmpty) e.name,
                if (e.sha.isNotEmpty)
                  e.sha.substring(0, e.sha.length.clamp(0, 7)),
              ].join(' · '),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
