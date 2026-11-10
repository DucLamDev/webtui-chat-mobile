import '../../../../core/result/result.dart';
import '../entities/qr_login.dart';

/// Phía điện thoại (máy tin cậy) của đăng nhập QR: quét rồi đồng ý / từ chối.
abstract interface class QrLoginRepository {
  Future<Result<QrLoginScan>> scan(QrLoginPayload payload);

  Future<Result<String>> approve(QrLoginPayload payload);

  Future<Result<String>> reject(QrLoginPayload payload);
}
