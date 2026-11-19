import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../application/ide_avatar_encoder.dart';
import '../../../application/ide_profile_service.dart';
import '../../../application/ide_talk_controller.dart';
import '../../../application/ide_talk_service.dart';
import '../../controllers/ide_controllers.dart';
import '../../widgets/ai/ide_ai_commands.dart';

final ideTalkServiceProvider = Provider<IdeTalkService>(
  (ref) => IdeTalkService(ref.watch(ideRpcClientProvider)),
);

final ideProfileServiceProvider = Provider<IdeProfileService>(
  (ref) => IdeProfileService(ref.watch(ideRpcClientProvider)),
);

/// Bộ mã ảnh đại diện (thay được khi test).
final ideAvatarEncoderProvider = Provider<IdeAvatarEncoder>(
  (_) => const DartUiAvatarEncoder(),
);

/// Chọn ảnh / tệp (thay được khi test).
final ideTalkPickerProvider = Provider<IdeAttachmentPicker>(
  (_) => PlatformIdeAttachmentPicker(),
);

/// Một controller cho mỗi cuộc đang mở; đóng màn là huỷ stream.
final ideTalkControllerProvider = StateNotifierProvider.autoDispose
    .family<IdeTalkController, IdeTalkState, String>(
      (ref, id) => IdeTalkController(
        connection: ref.watch(ideConnectionProvider),
        service: ref.watch(ideTalkServiceProvider),
        talkId: id,
      )..start(),
    );

/// Op có trong `ready.ops`? Chưa biết `ready` thì [unknown] (mặc định: có).
bool ideTalkHasOp(WidgetRef ref, String op, {bool unknown = true}) {
  final ready = ref.watch(ideLinkStatusProvider).valueOrNull?.ready;
  return ready == null ? unknown : ready.hasOp(op);
}

/// Như [ideTalkHasOp] nhưng chỉ đọc: dùng trong hàm xử lý bấm, không trong `build`.
bool ideTalkCan(WidgetRef ref, String op, {bool unknown = true}) {
  final ready = ref.read(ideLinkStatusProvider).valueOrNull?.ready;
  return ready == null ? unknown : ready.hasOp(op);
}
