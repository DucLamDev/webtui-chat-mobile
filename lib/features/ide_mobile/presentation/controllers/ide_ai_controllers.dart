import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../application/ide_ai_session_controller.dart';

/// Mã máy cố định cho phiên AI (`mobile-<uuid>`).
final ideClientIdStoreProvider = Provider<IdeClientIdStore>(
  (ref) => IdeClientIdStore(ref.watch(secureKeyValueStoreProvider)),
);

/// Một controller cho mỗi phiên đang mở (theo mã phiên hoặc phiên mới).
final ideAiSessionControllerProvider = StateNotifierProvider.autoDispose
    .family<IdeAiSessionController, IdeAiSnapshot, IdeAiOpenTarget>((
      ref,
      target,
    ) {
      final controller = IdeAiSessionController(
        connection: ref.watch(ideConnectionProvider),
        target: target,
        clientId: ref.watch(ideClientIdStoreProvider).get,
        stepHandler: ref.watch(ideStepUpProvider).confirm,
      )..start();
      return controller;
    });
