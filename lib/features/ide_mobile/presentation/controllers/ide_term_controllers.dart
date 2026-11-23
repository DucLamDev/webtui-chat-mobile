import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../application/ide_term_controller.dart';
import '../../data/ide_connection.dart';
import '../../domain/ide_term.dart';
import 'ide_controllers.dart';

/// Một controller cho mỗi terminal đang mở (theo tên phiên hoặc phiên mới).
final ideTermControllerProvider = StateNotifierProvider.autoDispose
    .family<IdeTermController, IdeTermSnapshot, IdeTermOpenTarget>((
      ref,
      target,
    ) {
      return IdeTermController(
        connection: ref.watch(ideConnectionProvider),
        target: target,
      )..start();
    });

/// Danh sách `term.list`; tải lại khi nối lại được.
final ideTermListProvider = FutureProvider.autoDispose<List<IdeTermItem>>((
  ref,
) async {
  final status = ref.watch(ideLinkStatusProvider).valueOrNull;
  if (status?.phase != IdeLinkPhase.ready || ideTermDisabled(status?.ready)) {
    return const [];
  }
  final data = await ref.read(ideRpcClientProvider).call('term.list', const {});
  return parseIdeTermItems(data);
});

/// Máy SSH chọn được (`term.targets`); lỗi thì chỉ còn Shell / Claude / Codex.
final ideTermTargetsProvider = FutureProvider.autoDispose<IdeTermTargets>((
  ref,
) async {
  final data = await ref
      .read(ideRpcClientProvider)
      .call('term.targets', const {});
  return IdeTermTargets.parse(data);
});
