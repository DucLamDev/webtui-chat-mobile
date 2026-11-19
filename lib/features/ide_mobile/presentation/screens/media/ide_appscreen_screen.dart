import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_colors.dart';
import '../../../../../design_system/tokens/webtui_radii.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../design_system/tokens/webtui_typography.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_appscreen_controller.dart';
import '../../../application/ide_media_service.dart';
import '../../../data/ide_connection.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_media_models.dart';
import '../../../domain/ide_project.dart';
import '../../../domain/ide_visible_text.dart';
import '../../controllers/ide_controllers.dart';
import '../../controllers/ide_project_ops_controllers.dart';
import '../more/ide_more_common.dart';
import 'ide_media_common.dart';

/// Màn hình app: xem trước app Flutter của dự án (CHỈ XEM, không chạm / gõ).
class IdeAppScreenScreen extends ConsumerWidget {
  const IdeAppScreenScreen({this.project, super.key});

  final String? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IdeMorePage(
      title: tr('Màn hình app', 'App screen'),
      body: IdeProjectScope(
        initial: project,
        builder: (context, p) => _AppBody(project: p),
      ),
    );
  }
}

class _AppBody extends ConsumerStatefulWidget {
  const _AppBody({required this.project});

  final IdeProject project;

  @override
  ConsumerState<_AppBody> createState() => _AppBodyState();
}

class _AppBodyState extends ConsumerState<_AppBody>
    with IdeMediaActiveState<_AppBody> {
  late final IdeAppScreenController _c;

  bool _confirming = false;

  bool _has(String op) =>
      ref.read(ideLinkStatusProvider).valueOrNull?.ready?.hasOp(op) ?? false;

  bool _linkReady() =>
      ref.read(ideLinkStatusProvider).valueOrNull?.phase == IdeLinkPhase.ready;

  @override
  void initState() {
    super.initState();
    _c = IdeAppScreenController(
      media: ref.read(ideMediaServiceProvider),
      jobs: ref.read(ideProjectServiceProvider),
      project: widget.project.name,
      canRun: () => _has('appscreen.run'),
      hasCheck: () => _has('appscreen.check'),
      linkReady: _linkReady,
      isActive: () => mediaActive,
    )..addListener(_changed);
    // Chờ biết danh sách op của IDE rồi mới tải (để chọn đúng op được gọi).
    ref
        .read(ideLinkStatusProvider.future)
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() {
          if (mounted) _c.load();
        });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void onMediaResumed() => _c.resume();

  @override
  void dispose() {
    _c
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _openSetup() async {
    final r = await showModalBottomSheet<_Setup>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: _SetupForm(
            key: const Key('ide_app_setup_sheet'),
            status: _c.status,
            initialDevice: _c.session?.device,
            initialDark: _c.session?.dark ?? false,
            submitLabel: tr('Áp dụng', 'Apply'),
            onSubmit: (s) => Navigator.of(ctx).pop(s),
          ),
        ),
      ),
    );
    if (r != null && mounted) {
      await _c.run(device: r.device, dark: r.dark);
    }
  }

  Future<void> _confirmStop() async {
    if (_confirming) return;
    _confirming = true;
    final bool ok;
    try {
      ok = await showWebTuiConfirmDialog(
        context,
        title: tr('Dừng màn hình app?', 'Stop the app screen?'),
        message: tr(
          'Phiên xem trước sẽ đóng, mở lại sẽ dựng lại từ đầu.',
          'The preview session closes; opening again rebuilds it.',
        ),
        confirmLabel: tr('Dừng', 'Stop'),
        destructive: true,
      );
    } finally {
      _confirming = false;
    }
    if (ok && mounted) await _c.stop();
  }

  @override
  Widget build(BuildContext context) {
    final gate = ideMediaGate(ref, const [
      'appscreen.status',
      'appscreen.frame',
    ]);
    if (gate != null) return gate;
    switch (_c.phase) {
      case IdeAppPhase.loading:
        return WebTuiLoadingState(message: tr('Đang tải...', 'Loading...'));
      case IdeAppPhase.error:
        return IdeMoreErrorView(
          error: _c.error ?? const IdeError(),
          onRetry: _c.load,
        );
      case IdeAppPhase.noTool:
        return WebTuiEmptyState(
          title: tr('Chưa dùng được', 'Not available'),
          message: tr(
            'Máy chưa cài công cụ, nhờ quản trị.',
            'The machine has no tools installed; ask an admin.',
          ),
          icon: Icons.build_circle_outlined,
        );
      case IdeAppPhase.ready:
        break;
    }
    final canRun = ideMediaHasOp(ref, 'appscreen.run');
    final canStop = ideMediaHasOp(ref, 'appscreen.stop');
    final s = _c.session;
    final muted = WebTuiTypography.bodySmall.copyWith(
      color: WebTuiColors.textMuted,
    );
    final lines = _c.log;
    final progress = _c.running
        ? IdeCard(
            key: const Key('ide_app_job'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Đang mở màn hình app…', 'Opening the app screen…'),
                  style: WebTuiTypography.titleMedium,
                ),
                const SizedBox(height: WebTuiSpacing.sm),
                const LinearProgressIndicator(),
                for (final l in lines)
                  Text(
                    ideVisibleText(l),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
              ],
            ),
          )
        : null;
    final problem = _c.runError == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
            child: Text(
              ideVisibleText(_c.runError!),
              key: const Key('ide_app_run_error'),
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.danger,
              ),
            ),
          );
    if (s == null) {
      return ListView(
        padding: const EdgeInsets.all(WebTuiSpacing.lg),
        children: [
          IdeCard(
            key: const Key('ide_app_none'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Chưa mở màn hình app', 'The app screen is not open'),
                  style: WebTuiTypography.titleMedium,
                ),
                const SizedBox(height: WebTuiSpacing.xs),
                Text(
                  tr(
                    'Mở để xem trước app của dự án này (chỉ xem, không chạm được).',
                    'Open to preview this project\'s app (view only).',
                  ),
                  style: muted,
                ),
                if (canRun) ...[
                  const SizedBox(height: WebTuiSpacing.md),
                  _SetupForm(
                    status: _c.status,
                    initialDevice: null,
                    initialDark: false,
                    submitLabel: tr('Mở', 'Open'),
                    busy: _c.running,
                    onSubmit: (v) => _c.run(device: v.device, dark: v.dark),
                  ),
                ],
              ],
            ),
          ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(top: WebTuiSpacing.md),
              child: progress,
            ),
          ?problem,
          Padding(
            padding: const EdgeInsets.only(top: WebTuiSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('ide_app_refresh'),
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: _c.running ? null : _c.load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(tr('Làm mới', 'Refresh')),
              ),
            ),
          ),
        ],
      );
    }
    final device = _c.status.devices
        .where((d) => d.key == s.device)
        .map((d) => d.label)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: WebTuiSpacing.sm,
            runSpacing: WebTuiSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IdeTag(
                _c.building
                    ? tr('Đang dựng…', 'Building…')
                    : tr('Đang chạy', 'Running'),
                color: _c.building
                    ? WebTuiColors.accentAmber
                    : WebTuiColors.accentGreen,
              ),
              Text(
                ideVisibleText(device ?? (s.device.isEmpty ? '—' : s.device)),
                key: const Key('ide_app_device'),
                style: WebTuiTypography.bodyMedium,
              ),
              if (_c.frameFailing)
                IdeTag(
                  tr('Mất kết nối, đang thử lại', 'Offline, retrying'),
                  color: WebTuiColors.danger,
                ),
              if (canRun)
                TextButton(
                  key: const Key('ide_app_change'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: _c.running || _c.stopping ? null : _openSetup,
                  child: Text(tr('Đổi thiết lập', 'Change setup')),
                ),
              if (canStop)
                TextButton(
                  key: const Key('ide_app_stop'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    foregroundColor: WebTuiColors.danger,
                  ),
                  onPressed: _c.running || _c.stopping ? null : _confirmStop,
                  child: Text(tr('Dừng', 'Stop')),
                ),
            ],
          ),
          ?progress,
          ?problem,
          const SizedBox(height: WebTuiSpacing.sm),
          Expanded(
            child: _FrameView(frame: _c.frame, building: _c.building),
          ),
        ],
      ),
    );
  }
}

class _Setup {
  const _Setup(this.device, this.dark);
  final String? device;
  final bool dark;
}

class _SetupForm extends StatefulWidget {
  const _SetupForm({
    required this.status,
    required this.initialDevice,
    required this.initialDark,
    required this.submitLabel,
    required this.onSubmit,
    this.busy = false,
    super.key,
  });

  final IdeAppStatus status;
  final String? initialDevice;
  final bool initialDark;
  final String submitLabel;
  final bool busy;
  final void Function(_Setup) onSubmit;

  @override
  State<_SetupForm> createState() => _SetupFormState();
}

class _SetupFormState extends State<_SetupForm> {
  String? _device;
  late bool _dark = widget.initialDark;

  @override
  void initState() {
    super.initState();
    final keys = widget.status.devices.map((d) => d.key).toList();
    final i = widget.initialDevice;
    _device = i != null && keys.contains(i)
        ? i
        : (keys.contains('iphone') ? 'iphone' : keys.firstOrNull);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(WebTuiSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.status.devices.isNotEmpty) ...[
            Text(tr('Loại máy', 'Device'), style: WebTuiTypography.titleMedium),
            const SizedBox(height: WebTuiSpacing.sm),
            Wrap(
              spacing: WebTuiSpacing.sm,
              runSpacing: WebTuiSpacing.sm,
              children: [
                for (final d in widget.status.devices)
                  ChoiceChip(
                    key: Key('ide_app_dev_${d.key}'),
                    label: Text(ideVisibleText(d.label)),
                    selected: _device == d.key,
                    onSelected: (_) => setState(() => _device = d.key),
                  ),
              ],
            ),
          ],
          SwitchListTile(
            key: const Key('ide_app_dark'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Nền tối', 'Dark background')),
            value: _dark,
            onChanged: (v) => setState(() => _dark = v),
          ),
          const SizedBox(height: WebTuiSpacing.sm),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              key: const Key('ide_app_submit'),
              onPressed: widget.busy
                  ? null
                  : () => widget.onSubmit(_Setup(_device, _dark)),
              child: Text(widget.submitLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Khung ảnh xem trước: được phóng to / thu nhỏ, không có thao tác nào khác.
class _FrameView extends StatelessWidget {
  const _FrameView({required this.frame, required this.building});

  final IdeAppFrame? frame;
  final bool building;

  @override
  Widget build(BuildContext context) {
    final f = frame;
    return Container(
      key: const Key('ide_app_frame'),
      decoration: BoxDecoration(
        color: WebTuiColors.surface,
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
        border: Border.all(color: WebTuiColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: f == null
          ? Center(
              child: Text(
                building
                    ? tr('Đang dựng…', 'Building…')
                    : tr('Đang chờ khung hình…', 'Waiting for a frame…'),
                style: WebTuiTypography.bodyMedium.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              ),
            )
          : Semantics(
              image: true,
              label: tr('Xem trước màn hình app', 'App screen preview'),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: f.aspect,
                    child: Image(
                      image: ResizeImage(
                        MemoryImage(f.bytes),
                        width: ideFrameMaxSide,
                        height: ideFrameMaxSide,
                        policy: ResizeImagePolicy.fit,
                      ),
                      gaplessPlayback: true,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
