import '../../../../core/result/result.dart';
import '../entities/device_approval.dart';

abstract interface class DeviceApprovalRepository {
  /// Trạng thái chờ duyệt của phiên đang dùng (gọi được khi phiên còn chờ).
  Future<Result<MyDeviceApproval>> mine();

  /// Các phiên đang chờ mà người gọi có quyền duyệt.
  Future<Result<List<DeviceApprovalRequest>>> listPending(
    DeviceApprovalScope scope,
  );

  Future<Result<DeviceApprovalResult>> approve(String sessionId);

  Future<Result<DeviceApprovalResult>> reject(String sessionId);
}
