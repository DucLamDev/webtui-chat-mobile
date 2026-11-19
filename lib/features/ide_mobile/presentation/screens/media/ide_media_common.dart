import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../data/ide_connection.dart';
import '../../../domain/ide_errors.dart';
import '../../controllers/ide_controllers.dart';
import '../more/ide_more_common.dart';

/// Op có trong `ready.ops` của IDE đang nối (chưa biết thì coi như chưa có).
bool ideMediaHasOp(WidgetRef ref, String op) =>
    ref.watch(ideLinkStatusProvider).valueOrNull?.ready?.hasOp(op) ?? false;

/// Cổng trước khi gọi op: `null` = đang ready và có đủ [ops] (được gọi).
/// Chưa ready thì hiện đúng trạng thái (đang nối / mất kết nối / bị gỡ); chỉ
/// khi ready mà thiếu op mới báo "không hỗ trợ".
Widget? ideMediaGate(WidgetRef ref, List<String> ops) {
  final st = ref.watch(ideLinkStatusProvider).valueOrNull;
  final ready = st?.phase == IdeLinkPhase.ready ? st?.ready : null;
  if (ready != null) {
    return ops.every(ready.hasOp)
        ? null
        : IdeMoreErrorView(error: const IdeUnsupported());
  }
  return switch (st?.phase) {
    IdeLinkPhase.revoked => WebTuiEmptyState(
      title: tr('Máy này đã bị gỡ', 'This phone was removed'),
      message: tr(
        'IDE đã gỡ điện thoại này. Hãy gắn lại bằng mã QR mới.',
        'The IDE removed this phone. Pair again with a new QR code.',
      ),
      icon: Icons.link_off_rounded,
    ),
    IdeLinkPhase.offline || IdeLinkPhase.idle => WebTuiEmptyState(
      title: tr('Chưa nối IDE', 'IDE not connected'),
      message: tr(
        'Hãy mở IDE trên máy tính, rồi quay lại tab IDE để nối lại.',
        'Open the IDE on your computer, then return to the IDE tab to reconnect.',
      ),
      icon: Icons.cloud_off_rounded,
    ),
    _ => WebTuiLoadingState(
      message: tr('Đang kết nối IDE...', 'Connecting...'),
    ),
  };
}

/// State biết màn có đang được xem không: app ở nền hoặc màn khác phủ lên
/// thì [mediaActive] = false. Khi quay lại gọi [onMediaResumed].
mixin IdeMediaActiveState<T extends StatefulWidget> on State<T> {
  AppLifecycleListener? _life;

  bool get mediaActive {
    if (!mounted) return false;
    final st = WidgetsBinding.instance.lifecycleState;
    if (st != null && st != AppLifecycleState.resumed) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  void onMediaResumed();

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onStateChange: (s) {
        if (s == AppLifecycleState.resumed && mounted) onMediaResumed();
      },
    );
  }

  @override
  void dispose() {
    _life?.dispose();
    super.dispose();
  }
}
