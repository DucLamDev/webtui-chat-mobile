import 'dart:typed_data';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/customer_ticket.dart';
import '../../domain/entities/customer_ticket_realtime_event.dart';
import '../../domain/repositories/customer_ticket_repository.dart';

/// Mã lỗi máy chủ trả khi gửi / nhận ticket mà người khác đang xử lý.
const customerTicketClaimedCode = 'TICKET_CLAIMED';

bool isCustomerTicketClaimedFailure(Failure failure) {
  return failure.code?.trim().toUpperCase() == customerTicketClaimedCode;
}

final _holderPattern = RegExp(r'đang do (.+?) xử lý', caseSensitive: false);

/// Tên người đang giữ ticket, đọc từ câu lỗi `TICKET_CLAIMED` của máy chủ
/// ("Ticket đang do X xử lý."); không đọc được thì dùng [fallback].
String customerTicketHolderName(Failure failure, {String? fallback}) {
  final match = _holderPattern.firstMatch(failure.message);
  final fromMessage = match?.group(1)?.trim();
  if (fromMessage != null && fromMessage.isNotEmpty) return fromMessage;
  final name = fallback?.trim();
  return name == null || name.isEmpty ? 'Người khác' : name;
}

final _ticketIdPattern = RegExp(r'^\d{1,19}$');

Failure? _scopeFailure(String workspaceId, [String? ticketId]) {
  if (workspaceId.trim().isEmpty) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Chưa chọn workspace.',
      code: 'CUSTOMER_TICKET_WORKSPACE_REQUIRED',
    );
  }
  if (ticketId != null && !_ticketIdPattern.hasMatch(ticketId.trim())) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Mã ticket không hợp lệ.',
      code: 'CUSTOMER_TICKET_ID_INVALID',
    );
  }
  return null;
}

final class ListCustomerTicketsUseCase {
  const ListCustomerTicketsUseCase(this._repository);

  final CustomerTicketRepository _repository;

  Future<Result<CustomerTicketPage>> execute({
    required String workspaceId,
    required CustomerTicketFilter filter,
    String search = '',
    int page = 1,
    int perPage = customerTicketDefaultPageSize,
  }) {
    final failure = _scopeFailure(workspaceId);
    if (failure != null) return Future.value(FailureResult(failure));
    var query = search.trim();
    if (query.runes.length > customerTicketMaxSearchLength) {
      query = String.fromCharCodes(
        query.runes.take(customerTicketMaxSearchLength),
      ).trim();
    }
    return _repository.listTickets(
      workspaceId: workspaceId.trim(),
      filter: filter,
      search: query,
      page: page < 1 ? 1 : page,
      perPage: perPage.clamp(1, customerTicketMaxPageSize),
    );
  }
}

/// Số ticket chưa trả lời cho ô "Ticket khách" ở hộp thư (một yêu cầu nhẹ,
/// `per_page=1`).
final class CountUnansweredCustomerTicketsUseCase {
  const CountUnansweredCustomerTicketsUseCase(this._repository);

  final CustomerTicketRepository _repository;

  Future<Result<int>> execute(String workspaceId) async {
    final failure = _scopeFailure(workspaceId);
    if (failure != null) return FailureResult(failure);
    final result = await _repository.listTickets(
      workspaceId: workspaceId.trim(),
      filter: CustomerTicketFilter.unanswered,
      perPage: 1,
    );
    return switch (result) {
      Success(value: final page) => Success(
        page.counts.unanswered > 0 || page.counts.total > 0
            ? page.counts.unanswered
            : page.total,
      ),
      FailureResult(failure: final failure) => FailureResult(failure),
    };
  }
}

final class LoadCustomerTicketUseCase {
  const LoadCustomerTicketUseCase(this._repository);

  final CustomerTicketRepository _repository;

  Future<Result<CustomerTicketDetail>> execute({
    required String workspaceId,
    required String ticketId,
  }) {
    final failure = _scopeFailure(workspaceId, ticketId);
    if (failure != null) return Future.value(FailureResult(failure));
    return _repository.getTicket(
      workspaceId: workspaceId.trim(),
      ticketId: ticketId.trim(),
    );
  }
}

final class ReplyCustomerTicketUseCase {
  const ReplyCustomerTicketUseCase(this._repository);

  final CustomerTicketRepository _repository;

  Future<Result<CustomerTicketReplyResult>> execute({
    required String workspaceId,
    required String ticketId,
    required String message,
    List<CustomerTicketImageUpload> images = const [],
    bool force = false,
  }) {
    final failure =
        _scopeFailure(workspaceId, ticketId) ??
        validateCustomerTicketReply(message: message, images: images);
    if (failure != null) return Future.value(FailureResult(failure));
    return _repository.reply(
      workspaceId: workspaceId.trim(),
      ticketId: ticketId.trim(),
      message: normalizeCustomerTicketReply(message),
      images: images,
      force: force,
    );
  }
}

String normalizeCustomerTicketReply(String message) {
  return message.replaceAll('\r\n', '\n').trim();
}

/// Giống máy chủ: cần nội dung hoặc ảnh; nội dung tối đa 4.000 ký tự; tối đa
/// 3 ảnh PNG / JPEG / GIF / WEBP, mỗi ảnh tối đa 5 MB.
Failure? validateCustomerTicketReply({
  required String message,
  List<CustomerTicketImageUpload> images = const [],
}) {
  final text = normalizeCustomerTicketReply(message);
  if (text.isEmpty && images.isEmpty) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Nhập nội dung trả lời hoặc đính kèm ảnh.',
      code: 'CUSTOMER_TICKET_REPLY_EMPTY',
    );
  }
  if (text.runes.length > customerTicketMaxReplyLength) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Nội dung trả lời tối đa 4.000 ký tự.',
      code: 'CUSTOMER_TICKET_REPLY_TOO_LONG',
    );
  }
  if (images.length > customerTicketMaxImages) {
    return const Failure(
      kind: FailureKind.validation,
      message: 'Tối đa 3 ảnh mỗi lần trả lời.',
      code: 'CUSTOMER_TICKET_TOO_MANY_IMAGES',
    );
  }
  for (final image in images) {
    final problem = customerTicketImageProblem(image);
    if (problem != null) {
      return Failure(
        kind: FailureKind.validation,
        message: problem,
        code: 'CUSTOMER_TICKET_IMAGE_INVALID',
      );
    }
  }
  return null;
}

String? customerTicketImageProblem(CustomerTicketImageUpload image) {
  if (!customerTicketAllowedImageTypes.contains(image.mimeType)) {
    return 'Ảnh ${image.name} không được hỗ trợ (chỉ PNG, JPEG, GIF, WEBP).';
  }
  if (image.byteSize <= 0) {
    return 'Ảnh ${image.name} trống.';
  }
  if (image.byteSize > customerTicketMaxImageBytes) {
    return 'Ảnh ${image.name} lớn hơn 5 MB.';
  }
  return null;
}

final class SetCustomerTicketStatusUseCase {
  const SetCustomerTicketStatusUseCase(this._repository);

  final CustomerTicketRepository _repository;

  Future<Result<CustomerTicketStatus>> execute({
    required String workspaceId,
    required String ticketId,
    required CustomerTicketStatus status,
  }) {
    final failure = _scopeFailure(workspaceId, ticketId);
    if (failure != null) return Future.value(FailureResult(failure));
    if (status != CustomerTicketStatus.answered &&
        status != CustomerTicketStatus.unanswered) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Trạng thái ticket không hợp lệ.',
            code: 'CUSTOMER_TICKET_STATUS_INVALID',
          ),
        ),
      );
    }
    return _repository.setStatus(
      workspaceId: workspaceId.trim(),
      ticketId: ticketId.trim(),
      status: status,
    );
  }
}

final class ClaimCustomerTicketUseCase {
  const ClaimCustomerTicketUseCase(this._repository);

  final CustomerTicketRepository _repository;

  Future<Result<CustomerTicketAssignee?>> execute({
    required String workspaceId,
    required String ticketId,
    bool release = false,
    bool force = false,
  }) {
    final failure = _scopeFailure(workspaceId, ticketId);
    if (failure != null) return Future.value(FailureResult(failure));
    return _repository.claim(
      workspaceId: workspaceId.trim(),
      ticketId: ticketId.trim(),
      release: release,
      force: force,
    );
  }
}

final class RequestCustomerTicketAiDraftUseCase {
  const RequestCustomerTicketAiDraftUseCase(this._repository);

  final CustomerTicketRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String ticketId,
    String instruction = '',
  }) {
    final failure = _scopeFailure(workspaceId, ticketId);
    if (failure != null) return Future.value(FailureResult(failure));
    final text = instruction.trim();
    if (text.runes.length > customerTicketMaxInstructionLength) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Gợi ý cho AI tối đa 1.000 ký tự.',
            code: 'CUSTOMER_TICKET_INSTRUCTION_TOO_LONG',
          ),
        ),
      );
    }
    return _repository.requestAiDraft(
      workspaceId: workspaceId.trim(),
      ticketId: ticketId.trim(),
      instruction: text,
    );
  }
}

final class WatchCustomerTicketsUseCase {
  const WatchCustomerTicketsUseCase(this._repository);

  final CustomerTicketRealtimeRepository _repository;

  Stream<CustomerTicketRealtimeEvent> execute(String workspaceId) {
    if (workspaceId.trim().isEmpty) return const Stream.empty();
    return _repository.watch(workspaceId: workspaceId.trim());
  }
}

final class PickCustomerTicketImagesUseCase {
  const PickCustomerTicketImagesUseCase(this._repository);

  final CustomerTicketImagePickerRepository _repository;

  /// [alreadySelected] ảnh đang chờ gửi: chỉ cho chọn thêm tới đủ 3 ảnh. Ảnh
  /// sai định dạng / quá 5 MB bị bỏ và báo lý do.
  Future<Result<CustomerTicketImagePick>> execute({
    required CustomerTicketImageSource source,
    required int alreadySelected,
  }) async {
    final remaining = customerTicketMaxImages - alreadySelected;
    if (remaining <= 0) {
      return const FailureResult(
        Failure(
          kind: FailureKind.validation,
          message: 'Tối đa 3 ảnh mỗi lần trả lời.',
          code: 'CUSTOMER_TICKET_TOO_MANY_IMAGES',
        ),
      );
    }
    final result = await _repository.pick(source: source, limit: remaining);
    switch (result) {
      case FailureResult(failure: final failure):
        return FailureResult(failure);
      case Success(value: final picked):
        final accepted = <CustomerTicketImageUpload>[];
        String? rejected;
        for (final image in picked) {
          final problem = customerTicketImageProblem(image);
          if (problem != null) {
            rejected ??= problem;
            continue;
          }
          if (accepted.length >= remaining) {
            rejected ??= 'Tối đa 3 ảnh mỗi lần trả lời.';
            continue;
          }
          accepted.add(image);
        }
        return Success(
          CustomerTicketImagePick(images: accepted, rejectedReason: rejected),
        );
    }
  }
}

final class LoadCustomerTicketImageUseCase {
  const LoadCustomerTicketImageUseCase(this._repository);

  final CustomerTicketImageRepository _repository;

  Future<Uint8List?> execute(String url) {
    if (url.trim().isEmpty) return Future.value();
    return _repository.loadImage(url);
  }
}
