import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/error/failure.dart';

/// My Note chỉ hiện khi máy chủ bật `capabilities.my_notes` (máy chủ vẫn kiểm
/// cờ ở mọi API, ẩn ở đây chỉ để đỡ bấm nhầm).
final myNotesEnabledProvider = Provider<bool>((ref) {
  return ref.watch(activeServerDiscoveryProvider)?.capabilities.myNotes ??
      false;
});

const myNotesDisabledMessage =
    'My Note chưa được bật trên máy chủ này. Hãy liên hệ quản trị viên.';

bool isMyNotesFeatureDisabled(Failure failure) =>
    failure.code == 'FEATURE_DISABLED';

bool isMyNoteVersionConflict(Failure failure) =>
    failure.code == 'NOTE_VERSION_CONFLICT';

String myNotesErrorText(Failure failure) {
  if (isMyNotesFeatureDisabled(failure)) return myNotesDisabledMessage;
  return userFacingErrorMessage(failure);
}
