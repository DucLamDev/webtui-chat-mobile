import '../../../../core/network/api_response.dart';

final class DepartmentSummary {
  const DepartmentSummary({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.parentId,
    this.memberCount = 0,
    this.leadCount = 0,
    this.channelCount = 0,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? parentId;
  final int memberCount;
  final int leadCount;
  final int channelCount;
}

final class TicketSummary {
  const TicketSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.updatedAt,
    this.description,
    this.channelId,
    this.assignedTo,
  });

  final String id;
  final String title;
  final String status;
  final String priority;
  final String? description;
  final String? channelId;
  final String? assignedTo;
  final DateTime updatedAt;
}

final class CreateTicketDraft {
  const CreateTicketDraft({
    required this.title,
    this.description = '',
    this.priority = 'normal',
    this.channelId,
    this.assignedTo,
  });

  final String title;
  final String description;
  final String priority;
  final String? channelId;
  final String? assignedTo;
}

final class BotSummary {
  const BotSummary({
    required this.id,
    required this.slug,
    required this.name,
    required this.status,
    this.description,
  });

  final String id;
  final String slug;
  final String name;
  final String status;
  final String? description;
}

final class BotAIConfigSummary {
  const BotAIConfigSummary({
    required this.provider,
    required this.model,
    this.secretRef,
  });

  final String provider;
  final String model;
  final String? secretRef;
}

final class BotFlowSummary {
  const BotFlowSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.version,
    this.prompt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String status;
  final int version;
  final String? prompt;
  final DateTime? updatedAt;
}

final class BotInstallationSummary {
  const BotInstallationSummary({
    required this.id,
    required this.scope,
    required this.status,
    this.channelId,
  });

  final String id;
  final String scope;
  final String status;
  final String? channelId;
}

final class BotFlowRunSummary {
  const BotFlowRunSummary({
    required this.id,
    required this.status,
    this.error,
    this.transcript = const {},
  });

  final String id;
  final String status;
  final String? error;
  final JsonMap transcript;
}

final class WebhookSummary {
  const WebhookSummary({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    this.targetUrl,
    this.channelId,
  });

  final String id;
  final String name;
  final String kind;
  final String status;
  final String? targetUrl;
  final String? channelId;
}

final class CronJobSummary {
  const CronJobSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.runner,
    this.schedule,
    this.description,
    this.payload = const {},
    this.nextRunAt,
  });

  final String id;
  final String name;
  final String status;
  final String runner;
  final String? schedule;
  final String? description;
  final JsonMap payload;
  final DateTime? nextRunAt;
}

final class AdminStatsSummary {
  const AdminStatsSummary({
    this.members = 0,
    this.channels = 0,
    this.messages = 0,
    this.files = 0,
    this.bots = 0,
  });

  final int members;
  final int channels;
  final int messages;
  final int files;
  final int bots;
}

final class AdminHealthSummary {
  const AdminHealthSummary({required this.status, this.checks = const {}});

  final String status;
  final Map<String, String> checks;

  bool get isReady => status == 'ready';
}

final class ApiTokenSummary {
  const ApiTokenSummary({
    required this.id,
    required this.name,
    required this.status,
    this.scopes = const [],
    this.lastUsedAt,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String status;
  final List<String> scopes;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;
}

final class AuditLogSummary {
  const AuditLogSummary({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.actorUserId,
    this.entityId,
  });

  final String id;
  final String action;
  final String entityType;
  final DateTime createdAt;
  final String? actorUserId;
  final String? entityId;
}

final class BotWorkspaceDetail {
  const BotWorkspaceDetail({
    required this.bot,
    this.aiConfig,
    this.flows = const [],
    this.installations = const [],
  });

  final BotSummary bot;
  final BotAIConfigSummary? aiConfig;
  final List<BotFlowSummary> flows;
  final List<BotInstallationSummary> installations;
}

final class BusinessDashboardData {
  const BusinessDashboardData({
    required this.workspaceId,
    this.departments = const [],
    this.tickets = const [],
    this.bots = const [],
    this.botDetail,
    this.webhooks = const [],
    this.cronJobs = const [],
    this.adminStats,
    this.adminHealth,
    this.apiTokens = const [],
    this.auditLogs = const [],
    this.errors = const {},
  });

  final String workspaceId;
  final List<DepartmentSummary> departments;
  final List<TicketSummary> tickets;
  final List<BotSummary> bots;
  final BotWorkspaceDetail? botDetail;
  final List<WebhookSummary> webhooks;
  final List<CronJobSummary> cronJobs;
  final AdminStatsSummary? adminStats;
  final AdminHealthSummary? adminHealth;
  final List<ApiTokenSummary> apiTokens;
  final List<AuditLogSummary> auditLogs;
  final Map<String, String> errors;
}
