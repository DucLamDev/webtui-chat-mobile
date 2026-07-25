import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/business_dashboard.dart';
import '../../domain/repositories/business_repository.dart';

final class LoadBusinessDashboardUseCase {
  const LoadBusinessDashboardUseCase(this._repository);

  final BusinessRepository _repository;

  Future<BusinessDashboardData> execute({required String workspaceId}) async {
    final errors = <String, String>{};
    final departments = await _collect<List<DepartmentSummary>>(
      key: 'departments',
      errors: errors,
      action: () => _repository.listDepartments(workspaceId: workspaceId),
      fallback: const [],
    );
    final tickets = await _collect<List<TicketSummary>>(
      key: 'tickets',
      errors: errors,
      action: () => _repository.listTickets(workspaceId: workspaceId),
      fallback: const [],
    );
    final bots = await _collect<List<BotSummary>>(
      key: 'bots',
      errors: errors,
      action: () => _repository.listBots(workspaceId: workspaceId),
      fallback: const [],
    );
    final webhooks = await _collect<List<WebhookSummary>>(
      key: 'webhooks',
      errors: errors,
      action: () => _repository.listWebhooks(workspaceId: workspaceId),
      fallback: const [],
    );
    final cronJobs = await _collect<List<CronJobSummary>>(
      key: 'automation',
      errors: errors,
      action: () => _repository.listCronJobs(workspaceId: workspaceId),
      fallback: const [],
    );
    final adminStats = await _collect<AdminStatsSummary?>(
      key: 'admin',
      errors: errors,
      action: () => _repository.loadAdminStats(workspaceId: workspaceId),
      fallback: null,
    );
    final adminHealth = await _collect<AdminHealthSummary?>(
      key: 'admin_health',
      errors: errors,
      action: () => _repository.loadAdminHealth(workspaceId: workspaceId),
      fallback: null,
    );
    final apiTokens = await _collect<List<ApiTokenSummary>>(
      key: 'api_tokens',
      errors: errors,
      action: () => _repository.listApiTokens(workspaceId: workspaceId),
      fallback: const [],
    );
    final auditLogs = await _collect<List<AuditLogSummary>>(
      key: 'audit',
      errors: errors,
      action: () => _repository.listAuditLogs(workspaceId: workspaceId),
      fallback: const [],
    );

    BotWorkspaceDetail? botDetail;
    if (bots.isNotEmpty) {
      final selectedBot = bots.first;
      final aiConfig = await _collect<BotAIConfigSummary?>(
        key: 'bot_ai',
        errors: errors,
        action: () => _repository.getBotAIConfig(
          workspaceId: workspaceId,
          botId: selectedBot.id,
        ),
        fallback: null,
      );
      final flows = await _collect<List<BotFlowSummary>>(
        key: 'bot_flows',
        errors: errors,
        action: () => _repository.listBotFlows(
          workspaceId: workspaceId,
          botId: selectedBot.id,
        ),
        fallback: const [],
      );
      final installations = await _collect<List<BotInstallationSummary>>(
        key: 'bot_installations',
        errors: errors,
        action: () => _repository.listBotInstallations(
          workspaceId: workspaceId,
          botId: selectedBot.id,
        ),
        fallback: const [],
      );
      botDetail = BotWorkspaceDetail(
        bot: selectedBot,
        aiConfig: aiConfig,
        flows: flows,
        installations: installations,
      );
    }

    return BusinessDashboardData(
      workspaceId: workspaceId,
      departments: departments,
      tickets: tickets,
      bots: bots,
      botDetail: botDetail,
      webhooks: webhooks,
      cronJobs: cronJobs,
      adminStats: adminStats,
      adminHealth: adminHealth,
      apiTokens: apiTokens,
      auditLogs: auditLogs,
      errors: errors,
    );
  }
}

final class CreateTicketUseCase {
  const CreateTicketUseCase(this._repository);

  final BusinessRepository _repository;

  Future<Result<TicketSummary>> execute({
    required String workspaceId,
    required CreateTicketDraft draft,
  }) {
    final trimmedTitle = draft.title.trim();
    if (trimmedTitle.isEmpty) {
      return Future.value(
        const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Cần nhập tiêu đề ticket.',
            code: 'VALIDATION_ERROR',
          ),
        ),
      );
    }
    return _repository.createTicket(
      workspaceId: workspaceId,
      draft: CreateTicketDraft(
        title: trimmedTitle,
        description: draft.description.trim(),
        priority: draft.priority.trim().isEmpty ? 'normal' : draft.priority,
        channelId: _blankToNull(draft.channelId),
        assignedTo: _blankToNull(draft.assignedTo),
      ),
    );
  }
}

final class TestBotFlowUseCase {
  const TestBotFlowUseCase(this._repository);

  final BusinessRepository _repository;

  Future<Result<BotFlowRunSummary>> execute({
    required String workspaceId,
    required String botId,
    required String flowId,
    required String input,
  }) {
    return _repository.testBotFlow(
      workspaceId: workspaceId,
      botId: botId,
      flowId: flowId,
      input: input.trim().isEmpty ? 'Xin chao' : input.trim(),
    );
  }
}

final class PublishBotFlowUseCase {
  const PublishBotFlowUseCase(this._repository);

  final BusinessRepository _repository;

  Future<Result<BotFlowSummary>> execute({
    required String workspaceId,
    required String botId,
    required String flowId,
  }) {
    return _repository.publishBotFlow(
      workspaceId: workspaceId,
      botId: botId,
      flowId: flowId,
    );
  }
}

final class UpdateTicketStatusUseCase {
  const UpdateTicketStatusUseCase(this._repository);

  final BusinessRepository _repository;

  Future<Result<TicketSummary>> execute({
    required String workspaceId,
    required String ticketId,
    required String status,
  }) {
    return _repository.updateTicketStatus(
      workspaceId: workspaceId,
      ticketId: ticketId,
      status: status,
    );
  }
}

final class RevokeApiTokenUseCase {
  const RevokeApiTokenUseCase(this._repository);

  final BusinessRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String tokenId,
  }) {
    return _repository.revokeApiToken(
      workspaceId: workspaceId,
      tokenId: tokenId,
    );
  }
}

final class RunCronJobUseCase {
  const RunCronJobUseCase(this._repository);

  final BusinessRepository _repository;

  Future<Result<void>> execute({
    required String workspaceId,
    required String cronJobId,
  }) {
    return _repository.runCronJob(
      workspaceId: workspaceId,
      cronJobId: cronJobId,
    );
  }
}

final class UpdateCronJobStatusUseCase {
  const UpdateCronJobStatusUseCase(this._repository);

  final BusinessRepository _repository;

  Future<Result<CronJobSummary>> execute({
    required String workspaceId,
    required CronJobSummary cronJob,
    required String status,
  }) {
    return _repository.updateCronJobStatus(
      workspaceId: workspaceId,
      cronJob: cronJob,
      status: status,
    );
  }
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Future<T> _collect<T>({
  required String key,
  required Map<String, String> errors,
  required Future<Result<T>> Function() action,
  required T fallback,
}) async {
  final result = await action();
  return switch (result) {
    Success<T>(value: final value) => value,
    FailureResult<T>(failure: final failure) => () {
      errors[key] = failure.message;
      return fallback;
    }(),
  };
}
