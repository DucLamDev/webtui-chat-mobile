import 'dart:typed_data';

import '../../../../core/result/result.dart';
import '../entities/customer_ticket.dart';
import '../entities/customer_ticket_realtime_event.dart';

abstract interface class CustomerTicketRepository {
  Future<Result<CustomerTicketPage>> listTickets({
    required String workspaceId,
    required CustomerTicketFilter filter,
    String search = '',
    int page = 1,
    int perPage = customerTicketDefaultPageSize,
  });

  Future<Result<CustomerTicketDetail>> getTicket({
    required String workspaceId,
    required String ticketId,
  });

  Future<Result<CustomerTicketReplyResult>> reply({
    required String workspaceId,
    required String ticketId,
    required String message,
    List<CustomerTicketImageUpload> images = const [],
    bool force = false,
  });

  Future<Result<CustomerTicketStatus>> setStatus({
    required String workspaceId,
    required String ticketId,
    required CustomerTicketStatus status,
  });

  /// Nhận xử lý ([release] = false) hoặc bỏ nhận; trả người đang xử lý mới.
  Future<Result<CustomerTicketAssignee?>> claim({
    required String workspaceId,
    required String ticketId,
    bool release = false,
    bool force = false,
  });

  /// Yêu cầu AI soạn nháp; nháp đến sau qua realtime / tải lại chi tiết.
  Future<Result<void>> requestAiDraft({
    required String workspaceId,
    required String ticketId,
    String instruction = '',
  });
}

abstract interface class CustomerTicketRealtimeRepository {
  Stream<CustomerTicketRealtimeEvent> watch({required String workspaceId});
}

abstract interface class CustomerTicketImagePickerRepository {
  Future<Result<List<CustomerTicketImageUpload>>> pick({
    required CustomerTicketImageSource source,
    required int limit,
  });
}

/// Tải ảnh khách gửi (URL tuyệt đối ở tên miền khác): không bao giờ gắn token.
abstract interface class CustomerTicketImageRepository {
  Future<Uint8List?> loadImage(String url);
}
