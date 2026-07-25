import '../../../../core/result/result.dart';
import '../entities/business_dashboard.dart';

abstract interface class BusinessRepository {
  Future<Result<List<DepartmentSummary>>> listDepartments({
    required String workspaceId,
  });

  Future<Result<List<TicketSummary>>> listTickets({
    required String workspaceId,
  });

  Future<Result<TicketSummary>> createTicket({
    required String workspaceId,
    required CreateTicketDraft draft,
  });

  Future<Result<List<BotSummary>>> listBots({required String workspaceId});

  Future<Result<BotAIConfigSummary?>> getBotAIConfig({
    required String workspaceId,
    required String botId,
  });

  Future<Result<List<BotFlowSummary>>> listBotFlows({
    required String workspaceId,
    required String botId,
  });

  Future<Result<List<BotInstallationSummary>>> listBotInstallations({
    required String workspaceId,
    required String botId,
  });

  Future<Result<BotFlowRunSummary>> testBotFlow({
    required String workspaceId,
    required String botId,
    required String flowId,
    required String input,
  });

  Future<Result<BotFlowSummary>> publishBotFlow({
    required String workspaceId,
    required String botId,
    required String flowId,
  });

  Future<Result<TicketSummary>> updateTicketStatus({
    required String workspaceId,
    required String ticketId,
    required String status,
  });

  Future<Result<List<WebhookSummary>>> listWebhooks({
    required String workspaceId,
  });

  Future<Result<List<CronJobSummary>>> listCronJobs({
    required String workspaceId,
  });

  Future<Result<CronJobSummary>> updateCronJobStatus({
    required String workspaceId,
    required CronJobSummary cronJob,
    required String status,
  });

  Future<Result<void>> runCronJob({
    required String workspaceId,
    required String cronJobId,
  });

  Future<Result<AdminStatsSummary>> loadAdminStats({
    required String workspaceId,
  });

  Future<Result<AdminHealthSummary>> loadAdminHealth({
    required String workspaceId,
  });

  Future<Result<List<ApiTokenSummary>>> listApiTokens({
    required String workspaceId,
  });

  Future<Result<void>> revokeApiToken({
    required String workspaceId,
    required String tokenId,
  });

  Future<Result<List<AuditLogSummary>>> listAuditLogs({
    required String workspaceId,
  });
}
