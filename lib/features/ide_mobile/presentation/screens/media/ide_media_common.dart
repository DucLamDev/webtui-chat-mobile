import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/ide_controllers.dart';

/// Op có trong `ready.ops` của IDE đang nối (chưa biết thì coi như chưa có).
bool ideMediaHasOp(WidgetRef ref, String op) =>
    ref.watch(ideLinkStatusProvider).valueOrNull?.ready?.hasOp(op) ?? false;

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
