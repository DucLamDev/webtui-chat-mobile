import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/qr_login.dart';
import '../../domain/repositories/qr_login_repository.dart';

/// Kiểm mã QR quét được trước khi gửi bất cứ gì lên máy chủ: đúng định dạng
/// `vpsttt-login:v1` và đúng tên miền máy chủ đang đăng nhập.
final class ReadQrLoginPayloadUseCase {
  const ReadQrLoginPayloadUseCase({required Uri? Function() loadServerOrigin})
    : _loadServerOrigin = loadServerOrigin;

  final Uri? Function() _loadServerOrigin;

  Result<QrLoginPayload> execute(String raw) {
    final payload = QrLoginPayload.tryParse(raw);
    if (payload == null) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: tr(
            'Mã QR này không phải mã đăng nhập máy tính.',
            'This QR code is not a desktop sign-in code.',
          ),
          code: 'QR_PAYLOAD_INVALID',
        ),
      );
    }
    final origin = _loadServerOrigin();
    if (origin == null || !payload.belongsToServer(origin)) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: tr(
            'Mã QR thuộc máy chủ ${payload.domain}, không phải máy chủ bạn '
                'đang đăng nhập. Ứng dụng không gửi gì đi.',
            'This QR code belongs to server ${payload.domain}, not the server '
                'you are signed in to. Nothing was sent.',
          ),
          code: 'QR_DOMAIN_MISMATCH',
        ),
      );
    }
    return Success(payload);
  }
}

final class ScanQrLoginUseCase {
  const ScanQrLoginUseCase(this._repository);

  final QrLoginRepository _repository;

  Future<Result<QrLoginScan>> execute(QrLoginPayload payload) {
    return _repository.scan(payload);
  }
}

final class DecideQrLoginUseCase {
  const DecideQrLoginUseCase(this._repository);

  final QrLoginRepository _repository;

  Future<Result<String>> execute(
    QrLoginPayload payload, {
    required bool approve,
  }) {
    return approve ? _repository.approve(payload) : _repository.reject(payload);
  }
}

/// Câu báo lỗi tiếng Việt cho từng mã lỗi QR của máy chủ.
String qrLoginFailureMessage(Failure failure) {
  if (failure.hasCode(QrLoginErrorCode.notFound)) {
    return tr(
      'Mã QR không còn hiệu lực. Hãy tải lại mã trên máy tính rồi quét lại.',
      'This QR code is no longer valid. Reload the code on your computer and scan again.',
    );
  }
  if (failure.hasCode(QrLoginErrorCode.taken)) {
    return tr(
      'Mã QR này đã được quét bằng thiết bị khác.',
      'This QR code was already scanned on another device.',
    );
  }
  if (failure.hasCode(QrLoginErrorCode.expired)) {
    return tr(
      'Mã QR đã hết hạn. Hãy tải mã mới trên máy tính rồi quét lại.',
      'This QR code has expired. Load a new code on your computer and scan again.',
    );
  }
  if (failure.hasCode(QrLoginErrorCode.disabled)) {
    return tr(
      'Tổ chức đang tắt đăng nhập bằng mã QR.',
      'Your organization has turned off QR code sign-in.',
    );
  }
  if (failure.hasCode(QrLoginErrorCode.rateLimited) ||
      failure.kind == FailureKind.rateLimited) {
    return tr(
      'Bạn thao tác quá nhanh. Vui lòng thử lại sau ít phút.',
      'You are going too fast. Please try again in a few minutes.',
    );
  }
  if (failure.hasCode('DEVICE_APPROVAL_PENDING')) {
    return tr(
      'Thiết bị này đang chờ duyệt nên chưa thể duyệt đăng nhập cho máy khác.',
      'This device is waiting for approval, so it cannot approve sign-ins for other devices yet.',
    );
  }
  return failure.message;
}
