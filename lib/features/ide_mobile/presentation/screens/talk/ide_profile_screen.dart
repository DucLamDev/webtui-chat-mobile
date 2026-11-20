import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_avatar_encoder.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_profile_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../controllers/ide_controllers.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';
import 'ide_profile_usage.dart';
import 'ide_profile_widgets.dart';
import 'ide_talk_providers.dart';

/// Ảnh gốc quá lớn thì không đọc vào bộ nhớ (chọn ảnh khác).
const ideAvatarMaxSourceBytes = 40 * 1024 * 1024;

/// Hồ sơ của chính mình: ảnh đại diện, dự án, mức dùng AI, agent cá nhân.
class IdeProfileScreen extends ConsumerStatefulWidget {
  const IdeProfileScreen({super.key});

  @override
  ConsumerState<IdeProfileScreen> createState() => _IdeProfileScreenState();
}

class _IdeProfileScreenState extends ConsumerState<IdeProfileScreen> {
  int _days = 30;
  Uint8List? _avatar;
  bool _avatarBusy = false;
  bool _avatarLoaded = false;
  bool _avatarRequested = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadAvatar();
  }

  /// Chưa có op `profile.avatar_get` thì coi như đã xong (không quay mãi, nút
  /// đổi / xoá ảnh không bị khoá). `ready` đến muộn thì tải khi đó.
  void _maybeLoadAvatar() {
    if (_avatarRequested) return;
    if (_has('profile.avatar_get')) {
      _avatarRequested = true;
      unawaited(_loadAvatar());
    } else if (!_avatarLoaded) {
      _avatarLoaded = true;
    }
  }

  /// Đọc (không theo dõi) trạng thái nối; chưa biết `ready` thì coi như KHÔNG
  /// có op.
  bool _has(String op, {bool unknown = false}) {
    final ready = ref.read(ideLinkStatusProvider).valueOrNull?.ready;
    return ready == null ? unknown : ready.hasOp(op);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadAvatar() async {
    try {
      final img = await ref.read(ideProfileServiceProvider).avatarGet();
      if (mounted) setState(() => _avatar = img?.bytes);
    } on Object {
      // Không tải được ảnh thì hiện hình mặc định.
    } finally {
      if (mounted) setState(() => _avatarLoaded = true);
    }
  }

  Future<Uint8List> _readAll(Stream<List<int>> s) async {
    final b = BytesBuilder(copy: false);
    await for (final c in s) {
      b.add(c);
      if (b.length > ideAvatarMaxSourceBytes) throw const IdeAvatarTooLarge();
    }
    return b.takeBytes();
  }

  Future<void> _change(bool camera) async {
    if (_avatarBusy) return;
    setState(() => _avatarBusy = true);
    try {
      final picked = await ref
          .read(ideTalkPickerProvider)
          .pickImage(camera: camera);
      if (picked == null) return;
      if (picked.size > ideAvatarMaxSourceBytes) {
        throw const IdeAvatarTooLarge();
      }
      final source = await _readAll(picked.read());
      final png = await ref.read(ideAvatarEncoderProvider).encode(source);
      if (!mounted) return;
      final ok = await _confirmAvatar(png);
      if (ok != true) return;
      await ref.read(ideProfileServiceProvider).avatarSet(png);
      if (mounted) setState(() => _avatar = png);
      _snack(tr('Đã đổi ảnh đại diện.', 'Profile photo updated.'));
    } on IdeAvatarTooLarge {
      _snack(
        tr(
          'Ảnh quá lớn, hãy chọn ảnh khác.',
          'The image is too large, pick another.',
        ),
      );
    } on IdeAvatarUnreadable {
      _snack(tr('Không đọc được ảnh này.', 'Could not read this image.'));
    } on Object catch (e) {
      // MissingPluginException (Linux), từ chối quyền camera, lỗi IDE...
      _snack(
        e.runtimeType.toString() == 'MissingPluginException'
            ? tr(
                'Máy này không mở được trình chọn ảnh.',
                'This device cannot open the image picker.',
              )
            : ideMoreErrorText(e),
      );
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<bool?> _confirmAvatar(Uint8List png) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Dùng ảnh này?', 'Use this photo?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: Image.memory(
              png,
              width: 128,
              height: 128,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: WebTuiSpacing.md),
          Text(
            key: const Key('avatar_public_note'),
            tr(
              'Ảnh này hiện cho cả công ty.',
              'This photo is visible to the whole company.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: IdeWb.textStrong,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(tr('Huỷ', 'Cancel')),
        ),
        FilledButton(
          key: const Key('avatar_confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(tr('Dùng ảnh này', 'Use photo')),
        ),
      ],
    ),
  );

  Future<void> _remove() async {
    if (_avatarBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xoá ảnh đại diện?', 'Remove profile photo?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Huỷ', 'Cancel')),
          ),
          FilledButton(
            key: const Key('avatar_remove_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Xoá', 'Remove')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _avatarBusy = true);
    try {
      await ref.read(ideProfileServiceProvider).avatarRemove();
      if (mounted) setState(() => _avatar = null);
    } on Object catch (e) {
      _snack(ideMoreErrorText(e));
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Theo dõi để vẽ lại khi danh sách op đổi; các chỗ khác chỉ đọc.
    ref.watch(ideLinkStatusProvider);
    ref.listen(ideLinkStatusProvider, (_, _) => _maybeLoadAvatar());
    return IdeMorePage(
      title: tr('Hồ sơ', 'Profile'),
      body: IdeLoader<IdeProfile>(
        key: ValueKey(_days),
        load: () => ref.read(ideProfileServiceProvider).show(days: _days),
        builder: (context, p, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(WebTuiSpacing.lg),
            children: [
              _Header(
                profile: p,
                avatar: _avatar,
                canChange: _has('profile.avatar_set'),
                canRemove: _has('profile.avatar_remove'),
                busy: _avatarBusy || (!_avatarLoaded && p.hasAvatar),
                onChange: _change,
                onRemove: _remove,
              ),
              ..._sections(p),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(IdeProfile p) {
    final svc = ref.read(ideProfileServiceProvider);
    final daily = _has('profile.usage_daily', unknown: false);
    return [
      if (p.projects.isNotEmpty)
        IdeProfileSection(
          title: tr('Dự án', 'Projects'),
          child: Column(
            children: [
              for (final pr in p.projects)
                IdeKeyValue(
                  ideVisibleText(pr.name),
                  pr.role == 'owner'
                      ? tr('Chủ dự án', 'Owner')
                      : tr('Thành viên', 'Member'),
                ),
            ],
          ),
        ),
      WebTuiSegmentedTabs(
        key: const Key('profile_days'),
        tabs: [
          tr('7 ngày', '7 days'),
          tr('30 ngày', '30 days'),
          tr('90 ngày', '90 days'),
        ],
        selectedIndex: _days == 7 ? 0 : (_days == 30 ? 1 : 2),
        onChanged: (i) => setState(() => _days = const [7, 30, 90][i]),
      ),
      const SizedBox(height: WebTuiSpacing.md),
      IdeProfileSection(
        title: tr('Mức dùng AI', 'AI usage'),
        child: IdeUsageTotals(profile: p),
      ),
      IdeProfileSection(
        title: tr('Biểu đồ', 'Chart'),
        child: daily
            ? IdeProfileAsync<List<IdeUsageDay>>(
                key: ValueKey('daily$_days'),
                load: () => svc.usageDaily(days: _days),
                builder: (_, d) => IdeProfileChart(
                  spec: ideProfileChartSpec(daily: d, byModel: p.byModel),
                ),
              )
            : IdeProfileChart(
                spec: ideProfileChartSpec(daily: null, byModel: p.byModel),
              ),
      ),
      IdeProfileSection(
        title: tr('Theo mô hình', 'By model'),
        child: IdeUsageRows(rows: p.byModel),
      ),
      IdeProfileSection(
        title: tr('Theo dự án', 'By project'),
        child: IdeUsageRows(rows: p.byProject),
      ),
      if (_has('ai.usage', unknown: false))
        IdeProfileSection(
          title: tr('Tài khoản AI đang dùng', 'AI accounts in use'),
          child: IdeProfileAsync<IdeAiUsage>(
            load: () => svc.aiUsage(),
            builder: (_, u) => IdeAiUsageView(usage: u),
          ),
        ),
      if (_has('ai.routes', unknown: false))
        IdeProfileSection(
          title: tr('Hạn mức tài khoản AI', 'AI account quotas'),
          child: IdeProfileAsync<List<IdeAiRoute>>(
            load: () => svc.aiRoutes(),
            builder: (_, r) => IdeAiRoutesView(routes: r),
          ),
        ),
      if (p.agents.isNotEmpty || p.personalAgents.isNotEmpty)
        IdeProfileSection(
          title: tr('Agent của tôi', 'My agents'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in p.agents)
                IdeKeyValue(
                  ideVisibleText('${a.project} / ${a.name}'),
                  [
                    if (a.health.isNotEmpty) ideVisibleText(a.health),
                    if (a.lastAt != null) ideFormatDateTime(a.lastAt!),
                  ].join(' · '),
                ),
              for (final a in p.personalAgents)
                IdeKeyValue(
                  ideVisibleText(a.name),
                  a.enabled ? tr('Đang bật', 'On') : tr('Đang tắt', 'Off'),
                ),
            ],
          ),
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.avatar,
    required this.canChange,
    required this.canRemove,
    required this.busy,
    required this.onChange,
    required this.onRemove,
  });

  final IdeProfile profile;
  final Uint8List? avatar;
  final bool canChange;
  final bool canRemove;
  final bool busy;
  final Future<void> Function(bool camera) onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cache = (72 * dpr).round().clamp(144, 256);
    return Padding(
      padding: const EdgeInsets.only(bottom: WebTuiSpacing.md),
      child: IdeCard(
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 72,
                height: 72,
                child: avatar == null
                    ? ColoredBox(
                        color: IdeWb.chip,
                        child: Icon(
                          Icons.person_rounded,
                          size: 40,
                          color: IdeWb.text2,
                        ),
                      )
                    : Image.memory(
                        avatar!,
                        key: const Key('profile_avatar'),
                        fit: BoxFit.cover,
                        // Giải mã nhỏ theo màn hình, không theo cỡ gốc.
                        cacheWidth: cache,
                        cacheHeight: cache,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.person_rounded),
                      ),
              ),
            ),
            const SizedBox(width: WebTuiSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ideVisibleText(p.displayName),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IdeType.titleMedium.copyWith(
                      color: IdeWb.textStrong,
                    ),
                  ),
                  if (p.email != null && p.email!.isNotEmpty)
                    Text(
                      ideVisibleText(p.email!),
                      overflow: TextOverflow.ellipsis,
                      style: IdeType.bodySmall.copyWith(color: IdeWb.text),
                    ),
                  if (p.admin)
                    Padding(
                      padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                      child: IdeTag(tr('Quản trị', 'Admin')),
                    ),
                  if (canChange || (canRemove && avatar != null))
                    Padding(
                      padding: const EdgeInsets.only(top: WebTuiSpacing.xs),
                      child: Wrap(
                        spacing: WebTuiSpacing.xs,
                        children: [
                          if (canChange)
                            TextButton(
                              key: const Key('avatar_gallery'),
                              onPressed: busy ? null : () => onChange(false),
                              child: Text(tr('Đổi ảnh', 'Change photo')),
                            ),
                          if (canChange)
                            TextButton(
                              key: const Key('avatar_camera'),
                              onPressed: busy ? null : () => onChange(true),
                              child: Text(tr('Chụp ảnh', 'Camera')),
                            ),
                          if (canRemove && avatar != null)
                            TextButton(
                              key: const Key('avatar_remove'),
                              onPressed: busy ? null : onRemove,
                              child: Text(tr('Xoá ảnh', 'Remove')),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
