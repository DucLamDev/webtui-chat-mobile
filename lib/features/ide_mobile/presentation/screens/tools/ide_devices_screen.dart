import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_more_time.dart';
import '../../../domain/ide_server_models.dart';
import '../../../domain/ide_visible_text.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';
import 'ide_tools_common.dart';

/// Điện thoại đã gắn (Phụ lục C3).
class IdeDevicesScreen extends ConsumerStatefulWidget {
  const IdeDevicesScreen({super.key});

  @override
  ConsumerState<IdeDevicesScreen> createState() => _IdeDevicesScreenState();
}

class _IdeDevicesScreenState extends ConsumerState<IdeDevicesScreen> {
  String? _busyId;

  Future<void> _revoke(IdeDevice d, Future<void> Function() reload) async {
    if (_busyId != null) return;
    // "Máy này" = device_id khớp credentials đã lưu, không chỉ tin `current` từ IDE.
    String? myId;
    try {
      myId = (await ref.read(ideCredentialsProvider.future))?.deviceId;
    } on Object {
      myId = null;
    }
    if (!mounted) return;
    final self = myId != null && myId.isNotEmpty && d.id == myId;
    final ok = await showWebTuiConfirmDialog(
      context,
      title: self
          ? tr('Gỡ máy này?', 'Unlink this phone?')
          : tr('Thu hồi máy này?', 'Revoke this phone?'),
      message: self
          ? tr(
              'Bạn sẽ bị đăng xuất khỏi IDE trên điện thoại này và phải ghép lại.',
              'You will be signed out of the IDE on this phone and must pair again.',
            )
          : tr(
              'Điện thoại ${ideVisibleText(d.name)} sẽ không dùng được IDE nữa.',
              '${ideVisibleText(d.name)} will no longer be able to use the IDE.',
            ),
      confirmLabel: self ? tr('Gỡ ghép', 'Unlink') : tr('Thu hồi', 'Revoke'),
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = d.id);
    // Lấy sẵn trước khi chờ: rời màn lúc đang gỡ thì `ref` hết dùng được, mà
    // máy này vẫn phải xoá ghép (IDE đã thu hồi khoá).
    final devices = ref.read(ideDevicesServiceProvider);
    final pairing = self ? ref.read(idePairingServiceProvider) : null;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // Gỡ chính máy này mà IDE báo lỗi (hết giờ chờ, IDE đã thu hồi trước,
      // mất mạng): vẫn gỡ ở máy chủ chat + xoá khoá trên điện thoại, không để
      // sót khoá. Gỡ máy khác mà lỗi thì báo lỗi như thường.
      // Không tin cờ `current` IDE trả về để xoá khoá ở máy: chỉ so mã máy đã
      // lưu. Đọc khoá lỗi nên tưởng máy khác thì IDE thu hồi sẽ đóng stream
      // `revoked`, luồng đó so mã máy rồi mới dọn.
      Object? revokeError;
      try {
        await devices.revoke(d.id);
      } on Object catch (e) {
        // Người dùng tự huỷ / không qua được bước xác nhận: dừng, giữ khoá.
        if (!self ||
            e is IdeCancelled ||
            e is IdeStepFailed ||
            e is IdeStepRequired) {
          rethrow;
        }
        revokeError = e;
      }
      if (pairing != null) {
        try {
          await pairing.removeThisDevice();
        } finally {
          container
            ..invalidate(ideCredentialsProvider)
            ..invalidate(ideCapabilitiesProvider);
        }
        if (revokeError != null) {
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  tr(
                    'Đã gỡ trên điện thoại này. IDE chưa xác nhận thu hồi; '
                        'kiểm lại danh sách máy trên IDE máy tính.',
                    'Unlinked on this phone. The IDE did not confirm the '
                        'revoke; check the device list in the desktop IDE.',
                  ),
                ),
              ),
            );
        }
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        return;
      }
      if (!mounted) return;
      await reload();
    } on Object catch (e) {
      if (mounted) ideToolsError(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRevoke = ideToolsHas(ref, 'devices.revoke');
    return IdeMorePage(
      title: tr('Điện thoại đã gắn', 'Linked phones'),
      body: !ideToolsHas(ref, 'devices.list')
          ? ideToolsUnsupported()
          : IdeLoader<List<IdeDevice>>(
              load: () => ref.read(ideDevicesServiceProvider).list(),
              builder: (context, items, reload) {
                if (items.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 320,
                          child: WebTuiEmptyState(
                            title: tr(
                              'Chưa có điện thoại nào',
                              'No linked phones',
                            ),
                            message: tr(
                              'Ghép điện thoại bằng mã trên máy chủ IDE.',
                              'Pair a phone with a code from your IDE server.',
                            ),
                            icon: Icons.smartphone_outlined,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.separated(
                    key: const Key('ide_devices_list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(WebTuiSpacing.lg),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: WebTuiSpacing.sm),
                    itemBuilder: (_, i) {
                      final d = items[i];
                      return IdeCard(
                        key: Key('ide_device_${d.id}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: WebTuiSpacing.sm,
                              runSpacing: WebTuiSpacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  ideVisibleText(
                                    d.name.isEmpty
                                        ? tr('Điện thoại', 'Phone')
                                        : d.name,
                                  ),
                                  style: IdeType.titleMedium.copyWith(
                                    color: IdeWb.textStrong,
                                  ),
                                ),
                                if (d.current)
                                  IdeTag(
                                    tr('Máy này', 'This phone'),
                                    color: IdeWb.ok,
                                  ),
                              ],
                            ),
                            const SizedBox(height: WebTuiSpacing.xs),
                            ToolInfoRow(
                              tr('Ghép lúc', 'Paired'),
                              d.createdAt == null
                                  ? ideToolsDash
                                  : ideFormatDateTime(d.createdAt!),
                            ),
                            ToolInfoRow(
                              tr('Dùng gần nhất', 'Last used'),
                              d.lastUsed == null
                                  ? ideToolsDash
                                  : ideFormatDateTime(d.lastUsed!),
                            ),
                            if (canRevoke)
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton(
                                  key: Key('ide_device_revoke_${d.id}'),
                                  style: ideToolsBtn(color: IdeWb.danger),
                                  onPressed: _busyId != null
                                      ? null
                                      : () => _revoke(d, reload),
                                  child: Text(
                                    d.current
                                        ? tr('Gỡ máy này', 'Unlink this phone')
                                        : tr('Thu hồi', 'Revoke'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
