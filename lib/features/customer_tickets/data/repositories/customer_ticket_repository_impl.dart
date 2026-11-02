import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/customer_ticket.dart';
import '../../domain/repositories/customer_ticket_repository.dart';
import '../datasources/customer_ticket_remote_data_source.dart';

final class CustomerTicketRepositoryImpl implements CustomerTicketRepository {
  const CustomerTicketRepositoryImpl(this._remote);

  final CustomerTicketRemoteDataSource _remote;

  @override
  Future<Result<CustomerTicketPage>> listTickets({
    required String workspaceId,
    required CustomerTicketFilter filter,
    String search = '',
    int page = 1,
    int perPage = customerTicketDefaultPageSize,
  }) {
    return guardResult(
      () => _remote.listTickets(
        workspaceId: workspaceId,
        filter: filter,
        search: search,
        page: page,
        perPage: perPage,
      ),
    );
  }

  @override
  Future<Result<CustomerTicketDetail>> getTicket({
    required String workspaceId,
    required String ticketId,
  }) {
    return guardResult(
      () => _remote.getTicket(workspaceId: workspaceId, ticketId: ticketId),
    );
  }

  @override
  Future<Result<CustomerTicketReplyResult>> reply({
    required String workspaceId,
    required String ticketId,
    required String message,
    List<CustomerTicketImageUpload> images = const [],
    bool force = false,
  }) {
    return guardResult(
      () => _remote.reply(
        workspaceId: workspaceId,
        ticketId: ticketId,
        message: message,
        images: images,
        force: force,
      ),
    );
  }

  @override
  Future<Result<CustomerTicketStatus>> setStatus({
    required String workspaceId,
    required String ticketId,
    required CustomerTicketStatus status,
  }) {
    return guardResult(
      () => _remote.setStatus(
        workspaceId: workspaceId,
        ticketId: ticketId,
        status: status,
      ),
    );
  }

  @override
  Future<Result<CustomerTicketAssignee?>> claim({
    required String workspaceId,
    required String ticketId,
    bool release = false,
    bool force = false,
  }) {
    return guardResult(
      () => _remote.claim(
        workspaceId: workspaceId,
        ticketId: ticketId,
        release: release,
        force: force,
      ),
    );
  }

  @override
  Future<Result<void>> requestAiDraft({
    required String workspaceId,
    required String ticketId,
    String instruction = '',
  }) {
    return guardResult(
      () => _remote.requestAiDraft(
        workspaceId: workspaceId,
        ticketId: ticketId,
        instruction: instruction,
      ),
    );
  }
}
