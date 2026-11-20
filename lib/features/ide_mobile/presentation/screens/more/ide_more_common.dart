import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_project.dart';
import '../../controllers/ide_project_controllers.dart';
import '../../widgets/ide_step_sheet.dart';

/// Câu dễ hiểu cho lỗi; ưu tiên `message` tiếng Việt của IDE.
String ideMoreErrorText(Object error) {
  if (error is IdeException && error.message.isNotEmpty) return error.message;
  return switch (error) {
    IdeOffline() => tr(
      'IDE trên máy tính đang ngoại tuyến.',
      'The desktop IDE is offline.',
    ),
    IdeForbidden() => tr(
      'Bạn chưa có quyền với chức năng này.',
      'You do not have access to this.',
    ),
    IdeNotFound() => tr('Không tìm thấy.', 'Not found.'),
    IdeCancelled() => tr(
      'Bạn đã huỷ xác nhận, thao tác chưa được thực hiện.',
      'You cancelled the confirmation; nothing was done.',
    ),
    IdeUnsupported() => tr(
      'Bản IDE này chưa hỗ trợ chức năng này.',
      'This IDE version does not support this yet.',
    ),
    _ => tr('Có lỗi, hãy thử lại.', 'Something went wrong, try again.'),
  };
}

/// Trạng thái lỗi đủ loại: không quyền / không thấy / ngoại tuyến / lỗi chung.
class IdeMoreErrorView extends StatelessWidget {
  const IdeMoreErrorView({required this.error, this.onRetry, super.key});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = ideMoreErrorText(error);
    return switch (error) {
      IdeForbidden() => WebTuiEmptyState(
        title: tr('Không có quyền', 'No access'),
        message: text,
        icon: Icons.lock_outline_rounded,
      ),
      IdeNotFound() => WebTuiEmptyState(
        title: tr('Không tìm thấy', 'Not found'),
        message: text,
        icon: Icons.search_off_rounded,
      ),
      IdeUnsupported() => WebTuiEmptyState(
        title: tr('IDE chưa hỗ trợ', 'Not supported'),
        message: text,
        icon: Icons.update_rounded,
      ),
      IdeOffline() => WebTuiErrorState(
        title: tr('IDE ngoại tuyến', 'IDE offline'),
        message: text,
        onRetry: onRetry,
      ),
      _ => WebTuiErrorState(
        title: tr('Không tải được', 'Could not load'),
        message: text,
        onRetry: onRetry,
      ),
    };
  }
}

/// Màn "không tìm thấy" cho đường dẫn có mã sai.
class IdeMoreNotFoundScreen extends StatelessWidget {
  const IdeMoreNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Không tìm thấy', 'Not found')),
        surfaceTintColor: Colors.transparent,
      ),
      body: WebTuiEmptyState(
        title: tr('Không tìm thấy', 'Not found'),
        message: tr(
          'Liên kết này không đúng hoặc đã bị xoá.',
          'This link is wrong or was removed.',
        ),
        icon: Icons.search_off_rounded,
      ),
    );
  }
}

/// Tải một lần rồi hiện: đang tải / lỗi (thử lại) / nội dung. Tải lại giữ nội
/// dung cũ; lỗi lúc tải lại chỉ báo bằng thanh nhắn.
class IdeLoader<T> extends StatefulWidget {
  const IdeLoader({
    required this.load,
    required this.builder,
    this.loadingKey,
    super.key,
  });

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() reload,
  )
  builder;
  final Key? loadingKey;

  @override
  State<IdeLoader<T>> createState() => _IdeLoaderState<T>();
}

class _IdeLoaderState<T> extends State<IdeLoader<T>> {
  T? _data;
  bool _has = false;
  Object? _error;
  bool _loading = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final seq = ++_seq;
    if (!_has) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await widget.load();
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = data;
        _has = true;
        _loading = false;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted || seq != _seq) return;
      if (_has) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ideMoreErrorText(e))));
        return;
      }
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_has) return widget.builder(context, _data as T, _run);
    if (_loading) {
      return WebTuiLoadingState(
        key: widget.loadingKey,
        message: tr('Đang tải...', 'Loading...'),
      );
    }
    return IdeMoreErrorView(error: _error ?? const IdeError(), onRetry: _run);
  }
}

/// Nút chọn dự án gọn: chạm mở bảng chọn. Ghi lại vào
/// `ideSelectedProjectNameProvider` để các màn khác theo cùng dự án.
class IdeProjectBar extends StatelessWidget {
  const IdeProjectBar({
    required this.projects,
    required this.current,
    required this.onPick,
    super.key,
  });

  final List<IdeProject> projects;
  final IdeProject current;
  final ValueChanged<IdeProject> onPick;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<IdeProject>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in projects)
                ListTile(
                  key: Key('ide_project_option_${p.name}'),
                  minVerticalPadding: 12,
                  leading: Icon(
                    p.name == current.name
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: p.name == current.name
                        ? WebTuiColors.primary
                        : WebTuiColors.textMuted,
                  ),
                  title: Text(p.title),
                  subtitle: p.branch.isEmpty ? null : Text(p.branch),
                  onTap: () => Navigator.of(ctx).pop(p),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${tr('Dự án', 'Project')}: ${current.title}',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('ide_project_bar'),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        onTap: projects.length > 1 ? () => _open(context) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WebTuiSpacing.md,
              vertical: WebTuiSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: WebTuiColors.surface,
              borderRadius: BorderRadius.circular(WebTuiRadii.md),
              border: Border.all(color: WebTuiColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 20,
                  color: WebTuiColors.textSecondary,
                ),
                const SizedBox(width: WebTuiSpacing.sm),
                Expanded(
                  child: Text(
                    current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WebTuiTypography.titleMedium.copyWith(
                      color: WebTuiColors.textPrimary,
                    ),
                  ),
                ),
                if (current.branch.isNotEmpty) ...[
                  const SizedBox(width: WebTuiSpacing.sm),
                  Text(
                    current.branch,
                    style: WebTuiTypography.bodySmall.copyWith(
                      color: WebTuiColors.textMuted,
                    ),
                  ),
                ],
                if (projects.length > 1)
                  Icon(
                    Icons.expand_more_rounded,
                    color: WebTuiColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lấy danh sách dự án, hiện thanh chọn dự án rồi dựng [builder] cho dự án
/// đang chọn (dựng lại khi đổi dự án). [initial] là `project` trên đường dẫn.
class IdeProjectScope extends ConsumerStatefulWidget {
  const IdeProjectScope({
    required this.builder,
    this.initial,
    this.showBar = true,
    super.key,
  });

  final String? initial;
  final bool showBar;
  final Widget Function(BuildContext context, IdeProject project) builder;

  @override
  ConsumerState<IdeProjectScope> createState() => _IdeProjectScopeState();
}

class _IdeProjectScopeState extends ConsumerState<IdeProjectScope> {
  String? _name;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = i == null || i.isEmpty ? null : i;
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(ideProjectsProvider);
    return list.when(
      loading: () =>
          WebTuiLoadingState(message: tr('Đang tải...', 'Loading...')),
      error: (e, _) => IdeMoreErrorView(
        error: e,
        onRetry: () => ref.invalidate(ideProjectsProvider),
      ),
      data: (projects) {
        if (projects.isEmpty) {
          return WebTuiEmptyState(
            title: tr('Chưa có dự án', 'No projects'),
            message: tr(
              'Tài khoản của bạn chưa có dự án nào trên IDE.',
              'Your account has no projects on the IDE yet.',
            ),
            icon: Icons.folder_off_outlined,
          );
        }
        final selected = _name ?? ref.watch(ideSelectedProjectNameProvider);
        final current = projects.firstWhere(
          (p) => p.name == selected,
          orElse: () => projects.first,
        );
        return Column(
          children: [
            if (widget.showBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WebTuiSpacing.lg,
                  WebTuiSpacing.sm,
                  WebTuiSpacing.lg,
                  WebTuiSpacing.xs,
                ),
                child: IdeProjectBar(
                  projects: projects,
                  current: current,
                  onPick: (p) {
                    setState(() => _name = p.name);
                    ref.read(ideSelectedProjectNameProvider.notifier).state =
                        p.name;
                  },
                ),
              ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(current.name),
                child: widget.builder(context, current),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Khung màn con: thanh tiêu đề + nội dung.
class IdeMorePage extends ConsumerStatefulWidget {
  const IdeMorePage({
    required this.title,
    required this.body,
    this.actions,
    this.floating,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floating;

  @override
  ConsumerState<IdeMorePage> createState() => _IdeMorePageState();
}

class _IdeMorePageState extends ConsumerState<IdeMorePage> {
  late final IdeStepPresenterLease _lease;

  @override
  void initState() {
    super.initState();
    // Mở thẳng từ thông báo (không có màn IDE phía dưới) vẫn phải hiện được
    // bảng vân tay khi thao tác cần xác nhận.
    _lease = IdeStepPresenterLease(ref.read(ideStepPresenterProvider.notifier));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lease.acquire(context, () => mounted);
    });
  }

  @override
  void dispose() {
    _lease.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebTuiColors.page,
      appBar: AppBar(
        title: Text(widget.title),
        actions: widget.actions,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: widget.floating,
      body: SafeArea(top: false, child: widget.body),
    );
  }
}

/// Thẻ nội dung nền sáng / tối theo token.
class IdeCard extends StatelessWidget {
  const IdeCard({required this.child, this.onTap, this.padding, super.key});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(WebTuiSpacing.md),
      child: child,
    );
    return Material(
      color: WebTuiColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        side: BorderSide(color: WebTuiColors.border),
      ),
      child: SizedBox(
        width: double.infinity,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: content,
                ),
              ),
      ),
    );
  }
}

/// Nhãn nhỏ (trạng thái, loại).
class IdeTag extends StatelessWidget {
  const IdeTag(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? WebTuiColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(WebTuiRadii.xs),
      ),
      child: Text(
        text,
        style: WebTuiTypography.labelSmall.copyWith(
          color: c,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
