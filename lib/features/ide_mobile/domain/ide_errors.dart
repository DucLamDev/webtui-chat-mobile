/// Lỗi có kiểu từ khung `result.error.code` của IDE (hợp đồng mục 4).
sealed class IdeException implements Exception {
  const IdeException(this.code, this.message);

  final String code;
  final String message;

  /// [hint] (`error.hint`, vd `pubkey`) chỉ được giữ cho `bad_request`.
  factory IdeException.fromCode(String? code, String? message, {String? hint}) {
    final text = (message ?? '').trim();
    return switch (code) {
      'not_found' => IdeNotFound(text),
      'forbidden' => IdeForbidden(text),
      'too_large' => IdeTooLarge(text),
      'bad_request' => IdeBadRequest(text, hint),
      'conflict' => IdeConflict(text),
      'busy' => IdeBusy(text),
      'timeout' => IdeTimeout(text),
      'unsupported' => IdeUnsupported(text),
      'step_required' => IdeStepRequired(text),
      'step_failed' => IdeStepFailed(text),
      // Cổng chưa mở thao tác này cho điện thoại: lời cố định, không thử lại.
      'not_allowed' => const IdeNotAllowed(),
      _ => IdeError(code ?? 'ide_error', text),
    };
  }

  @override
  String toString() => 'IdeException($code: $message)';
}

final class IdeNotFound extends IdeException {
  const IdeNotFound([String message = '']) : super('not_found', message);
}

final class IdeForbidden extends IdeException {
  const IdeForbidden([String message = '']) : super('forbidden', message);
}

final class IdeTooLarge extends IdeException {
  const IdeTooLarge([String message = '']) : super('too_large', message);
}

final class IdeBadRequest extends IdeException {
  const IdeBadRequest([String message = '', this.hint])
    : super('bad_request', message);

  /// Gợi ý máy đọc được kèm lỗi (vd `pubkey`), `null` nếu IDE không gửi.
  final String? hint;
}

final class IdeConflict extends IdeException {
  const IdeConflict([String message = '']) : super('conflict', message);
}

final class IdeBusy extends IdeException {
  const IdeBusy([String message = '']) : super('busy', message);
}

final class IdeTimeout extends IdeException {
  const IdeTimeout([String message = '']) : super('timeout', message);
}

final class IdeUnsupported extends IdeException {
  const IdeUnsupported([String message = '']) : super('unsupported', message);
}

final class IdeStepRequired extends IdeException {
  const IdeStepRequired([String message = ''])
    : super('step_required', message);
}

final class IdeStepFailed extends IdeException {
  const IdeStepFailed([String message = '']) : super('step_failed', message);
  const IdeStepFailed._(super.code, super.message);
}

/// Lời báo khi khoá xác nhận trong chip đã mất hiệu lực.
const ideStepKeyInvalidatedText =
    'Sinh trắc học trên máy đã thay đổi. Cần gắn lại máy với IDE.';

/// Khoá xác nhận mất hiệu lực (thêm / xoá sinh trắc học trên máy): bản gắn
/// không dùng được nữa, phải gắn lại.
final class IdeStepKeyInvalidated extends IdeStepFailed {
  const IdeStepKeyInvalidated()
    : super._('step_key_invalid', ideStepKeyInvalidatedText);
}

/// Lời báo khi cổng trả `not_allowed`.
const ideNotAllowedText = 'Thao tác này chưa được mở cho điện thoại.';

/// Cổng chưa mở thao tác này cho điện thoại (`not_allowed`). Không tự thử lại.
final class IdeNotAllowed extends IdeException {
  const IdeNotAllowed() : super('not_allowed', ideNotAllowedText);
}

final class IdeError extends IdeException {
  const IdeError([super.code = 'ide_error', super.message = '']);
}

/// Mất kết nối / IDE ngoại tuyến khi đang chờ trả lời.
final class IdeOffline extends IdeException {
  const IdeOffline([String message = '']) : super('ide_offline', message);
}

/// Máy này đã bị gỡ gắn (`ide_closed: revoked` hoặc `unauthorized`).
final class IdeRevoked extends IdeException {
  const IdeRevoked([String message = '']) : super('revoked', message);
}

/// Người dùng (hoặc app) huỷ yêu cầu.
final class IdeCancelled extends IdeException {
  const IdeCancelled([String message = '']) : super('cancelled', message);
}
