import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
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
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Mã QR này không phải mã đăng nhập máy tính.',
          code: 'QR_PAYLOAD_INVALID',
        ),
      );
    }
    final origin = _loadServerOrigin();
    if (origin == null || !payload.belongsToServer(origin)) {
      return FailureResult(
        Failure(
          kind: FailureKind.validation,
          message:
              'Mã QR thuộc máy chủ ${payload.domain}, không phải máy chủ bạn '
              'đang đăng nhập. Ứng dụng không gửi gì đi.',
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
    return 'Mã QR không còn hiệu lực. Hãy tải lại mã trên máy tính rồi quét lại.';
  }
  if (failure.hasCode(QrLoginErrorCode.taken)) {
    return 'Mã QR này đã được quét bằng thiết bị khác.';
  }
  if (failure.hasCode(QrLoginErrorCode.expired)) {
    return 'Mã QR đã hết hạn. Hãy tải mã mới trên máy tính rồi quét lại.';
  }
  if (failure.hasCode(QrLoginErrorCode.disabled)) {
    return 'Tổ chức đang tắt đăng nhập bằng mã QR.';
  }
  if (failure.hasCode(QrLoginErrorCode.rateLimited) ||
      failure.kind == FailureKind.rateLimited) {
    return 'Bạn thao tác quá nhanh. Vui lòng thử lại sau ít phút.';
  }
  if (failure.hasCode('DEVICE_APPROVAL_PENDING')) {
    return 'Thiết bị này đang chờ duyệt nên chưa thể duyệt đăng nhập cho máy khác.';
  }
  return failure.message;
}
