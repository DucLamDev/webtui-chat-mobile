import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../domain/entities/business_dashboard.dart';
import '../../domain/repositories/business_repository.dart';
import '../datasources/business_remote_data_source.dart';

final class BusinessRepositoryImpl implements BusinessRepository {
  const BusinessRepositoryImpl(this._remote);

  final BusinessRemoteDataSource _remote;

  @override
  Future<Result<List<DepartmentSummary>>> listDepartments({
    required String workspaceId,
  }) {
    return guardResult(() => _remote.listDepartments(workspaceId: workspaceId));
  }

  @override
  Future<Result<List<TicketSummary>>> listTickets({
    required String workspaceId,
  }) {
    return guardResult(() => _remote.listTickets(workspaceId: workspaceId));
  }

  @override
  Future<Result<TicketSummary>> createTicket({
    required String workspaceId,
    required CreateTicketDraft draft,
  }) {
    return guardResult(
      () => _remote.createTicket(workspaceId: workspaceId, draft: draft),
    );
  }

  @override
  Future<Result<List<BotSummary>>> listBots({required String workspaceId}) {
    return guardResult(() => _remote.listBots(workspaceId: workspaceId));
  }

  @override
  Future<Result<BotAIConfigSummary?>> getBotAIConfig({
    required String workspaceId,
    required String botId,
  }) {
    return guardResult(
      () => _remote.getBotAIConfig(workspaceId: workspaceId, botId: botId),
    );
  }

  @override
  Future<Result<List<BotFlowSummary>>> listBotFlows({
    required String workspaceId,
    required String botId,
  }) {
    return guardResult(
      () => _remote.listBotFlows(workspaceId: workspaceId, botId: botId),
    );
  }

  @override
  Future<Result<List<BotInstallationSummary>>> listBotInstallations({
    required String workspaceId,
    required String botId,
  }) {
    return guardResult(
      () =>
          _remote.listBotInstallations(workspaceId: workspaceId, botId: botId),
    );
  }

  @override
  Future<Result<BotFlowRunSummary>> testBotFlow({
    required String workspaceId,
    required String botId,
    required String flowId,
    required String input,
  }) {
    return guardResult(
      () => _remote.testBotFlow(
        workspaceId: workspaceId,
        botId: botId,
        flowId: flowId,
        input: input,
      ),
    );
  }

  @override
  Future<Result<BotFlowSummary>> publishBotFlow({
    required String workspaceId,
    required String botId,
    required String flowId,
  }) {
    return guardResult(
      () => _remote.publishBotFlow(
        workspaceId: workspaceId,
        botId: botId,
        flowId: flowId,
      ),
    );
  }

  @override
  Future<Result<TicketSummary>> updateTicketStatus({
    required String workspaceId,
    required String ticketId,
    required String status,
  }) {
    return guardResult(
      () => _remote.updateTicketStatus(
        workspaceId: workspaceId,
        ticketId: ticketId,
        status: status,
      ),
    );
  }

  @override
  Future<Result<List<WebhookSummary>>> listWebhooks({
    required String workspaceId,
  }) {
    return guardResult(() async {
      final incoming = await _remote.listIncomingWebhooks(
        workspaceId: workspaceId,
      );
      final outgoing = await _remote.listOutgoingWebhooks(
        workspaceId: workspaceId,
      );
      return [...incoming, ...outgoing];
    });
  }

  @override
  Future<Result<List<CronJobSummary>>> listCronJobs({
    required String workspaceId,
  }) {
    return guardResult(() => _remote.listCronJobs(workspaceId: workspaceId));
  }

  @override
  Future<Result<CronJobSummary>> updateCronJobStatus({
    required String workspaceId,
    required CronJobSummary cronJob,
    required String status,
  }) {
    return guardResult(
      () => _remote.updateCronJobStatus(
        workspaceId: workspaceId,
        cronJob: cronJob,
        status: status,
      ),
    );
  }

  @override
  Future<Result<void>> runCronJob({
    required String workspaceId,
    required String cronJobId,
  }) {
    return guardResult(
      () => _remote.runCronJob(workspaceId: workspaceId, cronJobId: cronJobId),
    );
  }

  @override
  Future<Result<AdminStatsSummary>> loadAdminStats({
    required String workspaceId,
  }) {
    return guardResult(() => _remote.loadAdminStats(workspaceId: workspaceId));
  }

  @override
  Future<Result<AdminHealthSummary>> loadAdminHealth({
    required String workspaceId,
  }) {
    return guardResult(() => _remote.loadAdminHealth(workspaceId: workspaceId));
  }

  @override
  Future<Result<List<ApiTokenSummary>>> listApiTokens({
    required String workspaceId,
  }) {
    return guardResult(() => _remote.listApiTokens(workspaceId: workspaceId));
  }

  @override
  Future<Result<void>> revokeApiToken({
    required String workspaceId,
    required String tokenId,
  }) {
    return guardResult(
      () => _remote.revokeApiToken(workspaceId: workspaceId, tokenId: tokenId),
    );
  }

  @override
  Future<Result<List<AuditLogSummary>>> listAuditLogs({
    required String workspaceId,
  }) {
    return guardResult(() => _remote.listAuditLogs(workspaceId: workspaceId));
  }
}
