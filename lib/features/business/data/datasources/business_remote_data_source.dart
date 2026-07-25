import 'dart:convert';

import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/business_dashboard.dart';

final class BusinessRemoteDataSource {
  const BusinessRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<List<DepartmentSummary>> listDepartments({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/departments',
    );
    return envelopeList(
      response.data,
      'departments',
    ).map(_departmentFromMap).toList(growable: false);
  }

  Future<List<TicketSummary>> listTickets({required String workspaceId}) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/tickets',
      queryParameters: const {'limit': 30},
    );
    return envelopeList(
      response.data,
      'tickets',
    ).map(_ticketFromMap).toList(growable: false);
  }

  Future<TicketSummary> createTicket({
    required String workspaceId,
    required CreateTicketDraft draft,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/tickets',
      data: compactMap({
        'channel_id': draft.channelId,
        'title': draft.title,
        'description': draft.description,
        'priority': draft.priority,
        'assigned_to': draft.assignedTo,
      }),
    );
    return _ticketFromMap(envelopeItem(response.data, 'ticket'));
  }

  Future<List<BotSummary>> listBots({required String workspaceId}) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/bots',
    );
    return envelopeList(
      response.data,
      'bots',
    ).map(_botFromMap).toList(growable: false);
  }

  Future<BotAIConfigSummary?> getBotAIConfig({
    required String workspaceId,
    required String botId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/bots/${_e(botId)}/ai-config',
    );
    final map = envelopeItem(response.data, 'config');
    if (map.isEmpty) {
      return null;
    }
    return _aiConfigFromMap(map);
  }

  Future<List<BotFlowSummary>> listBotFlows({
    required String workspaceId,
    required String botId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/bots/${_e(botId)}/flows',
    );
    return envelopeList(
      response.data,
      'flows',
    ).map(_flowFromMap).toList(growable: false);
  }

  Future<List<BotInstallationSummary>> listBotInstallations({
    required String workspaceId,
    required String botId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/bots/${_e(botId)}/installations',
    );
    return envelopeList(
      response.data,
      'installations',
    ).map(_installationFromMap).toList(growable: false);
  }

  Future<BotFlowRunSummary> testBotFlow({
    required String workspaceId,
    required String botId,
    required String flowId,
    required String input,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/bots/${_e(botId)}/flows/${_e(flowId)}/test',
      data: {
        'input': {'message': input},
      },
    );
    return _flowRunFromMap(envelopeItem(response.data, 'run'));
  }

  Future<BotFlowSummary> publishBotFlow({
    required String workspaceId,
    required String botId,
    required String flowId,
  }) async {
    final response = await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/bots/${_e(botId)}/flows/${_e(flowId)}/publish',
      data: const {},
    );
    return _flowFromMap(envelopeItem(response.data, 'flow'));
  }

  Future<TicketSummary> updateTicketStatus({
    required String workspaceId,
    required String ticketId,
    required String status,
  }) async {
    final response = await _api.patch<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/tickets/${_e(ticketId)}',
      data: {'status': status},
    );
    return _ticketFromMap(envelopeItem(response.data, 'ticket'));
  }

  Future<List<WebhookSummary>> listIncomingWebhooks({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/incoming-webhooks',
    );
    return envelopeList(
      response.data,
      'incoming_webhooks',
    ).map((map) => _webhookFromMap(map, 'incoming')).toList(growable: false);
  }

  Future<List<WebhookSummary>> listOutgoingWebhooks({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/outgoing-webhooks',
    );
    return envelopeList(
      response.data,
      'outgoing_webhooks',
    ).map((map) => _webhookFromMap(map, 'outgoing')).toList(growable: false);
  }

  Future<List<CronJobSummary>> listCronJobs({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/cronjobs',
      queryParameters: const {'limit': 30},
    );
    return envelopeList(
      response.data,
      'cronjobs',
    ).map(_cronJobFromMap).toList(growable: false);
  }

  Future<CronJobSummary> updateCronJobStatus({
    required String workspaceId,
    required CronJobSummary cronJob,
    required String status,
  }) async {
    final response = await _api.patch<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/cronjobs/${_e(cronJob.id)}',
      data: {
        'name': cronJob.name,
        'description': cronJob.description,
        'schedule': cronJob.schedule ?? '@daily',
        'runner': cronJob.runner,
        'status': status,
        'payload': cronJob.payload,
      },
    );
    return _cronJobFromMap(envelopeItem(response.data, 'cronjob'));
  }

  Future<void> runCronJob({
    required String workspaceId,
    required String cronJobId,
  }) async {
    await _api.post<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/cronjobs/${_e(cronJobId)}/run',
      data: const {},
    );
  }

  Future<AdminStatsSummary> loadAdminStats({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/admin/stats',
    );
    return _adminStatsFromMap(envelopeItem(response.data, 'stats'));
  }

  Future<AdminHealthSummary> loadAdminHealth({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/admin/health',
    );
    return _adminHealthFromMap(envelopeItem(response.data, 'health'));
  }

  Future<List<ApiTokenSummary>> listApiTokens({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/api-tokens',
    );
    return envelopeList(
      response.data,
      'api_tokens',
    ).map(_apiTokenFromMap).toList(growable: false);
  }

  Future<void> revokeApiToken({
    required String workspaceId,
    required String tokenId,
  }) async {
    await _api.delete<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/api-tokens/${_e(tokenId)}',
    );
  }

  Future<List<AuditLogSummary>> listAuditLogs({
    required String workspaceId,
  }) async {
    final response = await _api.get<Object>(
      '/api/v1/workspaces/${_e(workspaceId)}/audit-logs',
      queryParameters: const {'limit': 20},
    );
    return envelopeList(
      response.data,
      'audit_logs',
    ).map(_auditLogFromMap).toList(growable: false);
  }
}

DepartmentSummary _departmentFromMap(JsonMap map) {
  return DepartmentSummary(
    id: stringField(map, const ['id']),
    name: stringField(map, const ['name'], fallback: 'Phòng ban'),
    slug: stringField(map, const ['slug']),
    description: nullableStringField(map, const ['description']),
    parentId: nullableStringField(map, const ['parent_id', 'parentId']),
    memberCount: intField(map, const ['member_count', 'memberCount']),
    leadCount: intField(map, const ['lead_count', 'leadCount']),
    channelCount: intField(map, const ['channel_count', 'channelCount']),
  );
}

TicketSummary _ticketFromMap(JsonMap map) {
  return TicketSummary(
    id: stringField(map, const ['id']),
    title: stringField(map, const ['title'], fallback: 'Ticket'),
    status: stringField(map, const ['status'], fallback: 'open'),
    priority: stringField(map, const ['priority'], fallback: 'normal'),
    description: nullableStringField(map, const ['description']),
    channelId: nullableStringField(map, const ['channel_id', 'channelId']),
    assignedTo: nullableStringField(map, const ['assigned_to', 'assignedTo']),
    updatedAt: dateTimeField(map, const ['updated_at', 'updatedAt']),
  );
}

BotSummary _botFromMap(JsonMap map) {
  return BotSummary(
    id: stringField(map, const ['id', 'bot_id', 'botId']),
    slug: stringField(map, const ['slug']),
    name: stringField(map, const ['name'], fallback: 'Bot'),
    status: stringField(map, const ['status'], fallback: 'active'),
    description: nullableStringField(map, const ['description']),
  );
}

BotAIConfigSummary _aiConfigFromMap(JsonMap map) {
  return BotAIConfigSummary(
    provider: stringField(map, const ['provider'], fallback: 'not_configured'),
    model: stringField(map, const ['model'], fallback: 'not_configured'),
    secretRef: nullableStringField(map, const ['secret_ref', 'secretRef']),
  );
}

BotFlowSummary _flowFromMap(JsonMap map) {
  return BotFlowSummary(
    id: stringField(map, const ['id', 'flow_id', 'flowId']),
    name: stringField(map, const ['name'], fallback: 'Flow'),
    status: stringField(map, const ['status'], fallback: 'draft'),
    version: intField(map, const ['version'], fallback: 1),
    prompt: nullableStringField(map, const ['prompt']),
    updatedAt: nullableDateTimeField(map, const ['updated_at', 'updatedAt']),
  );
}

BotInstallationSummary _installationFromMap(JsonMap map) {
  final channelId = nullableStringField(map, const ['channel_id', 'channelId']);
  return BotInstallationSummary(
    id: stringField(map, const ['id', 'installation_id', 'installationId']),
    scope: channelId == null ? 'workspace' : 'channel',
    status: stringField(map, const ['status'], fallback: 'active'),
    channelId: channelId,
  );
}

BotFlowRunSummary _flowRunFromMap(JsonMap map) {
  return BotFlowRunSummary(
    id: stringField(map, const ['id', 'run_id', 'runId']),
    status: stringField(map, const ['status'], fallback: 'queued'),
    error: nullableStringField(map, const ['error']),
    transcript: jsonMap(map['transcript']),
  );
}

WebhookSummary _webhookFromMap(JsonMap map, String kind) {
  return WebhookSummary(
    id: stringField(map, const ['id', 'webhook_id', 'webhookId']),
    name: stringField(map, const ['name'], fallback: '$kind webhook'),
    kind: kind,
    status: stringField(map, const ['status'], fallback: 'active'),
    targetUrl: nullableStringField(map, const ['target_url', 'targetUrl']),
    channelId: nullableStringField(map, const ['channel_id', 'channelId']),
  );
}

CronJobSummary _cronJobFromMap(JsonMap map) {
  return CronJobSummary(
    id: stringField(map, const ['id', 'cronjob_id', 'cronJobId']),
    name: stringField(map, const ['name'], fallback: 'Cronjob'),
    status: stringField(map, const ['status'], fallback: 'active'),
    runner: stringField(map, const ['runner'], fallback: 'worker'),
    schedule: nullableStringField(map, const ['schedule']),
    description: nullableStringField(map, const ['description']),
    payload: jsonMap(map['payload']),
    nextRunAt: nullableDateTimeField(map, const ['next_run_at', 'nextRunAt']),
  );
}

AdminStatsSummary _adminStatsFromMap(JsonMap map) {
  return AdminStatsSummary(
    members: intField(map, const ['members', 'members_count', 'membersCount']),
    channels: intField(map, const ['channels', 'channels_count']),
    messages: intField(map, const ['messages', 'messages_count']),
    files: intField(map, const ['files', 'files_count']),
    bots: intField(map, const ['bots', 'bots_count']),
  );
}

AdminHealthSummary _adminHealthFromMap(JsonMap map) {
  final checks = jsonMap(
    map['checks'],
  ).map((key, value) => MapEntry(key, value.toString()));
  return AdminHealthSummary(
    status: stringField(map, const ['status'], fallback: 'unknown'),
    checks: checks,
  );
}

ApiTokenSummary _apiTokenFromMap(JsonMap map) {
  final scopes = jsonMapList(map['scopes'])
      .map((scope) => stringField(scope, const ['code']))
      .where((code) => code.isNotEmpty)
      .toList(growable: false);
  return ApiTokenSummary(
    id: stringField(map, const ['id', 'token_id', 'tokenId']),
    name: stringField(map, const ['name'], fallback: 'API token'),
    status: stringField(map, const ['status'], fallback: 'active'),
    scopes: scopes,
    lastUsedAt: nullableDateTimeField(map, const [
      'last_used_at',
      'lastUsedAt',
    ]),
    expiresAt: nullableDateTimeField(map, const ['expires_at', 'expiresAt']),
    createdAt: nullableDateTimeField(map, const ['created_at', 'createdAt']),
  );
}

AuditLogSummary _auditLogFromMap(JsonMap map) {
  return AuditLogSummary(
    id: stringField(map, const ['id', 'audit_log_id', 'auditLogId']),
    action: stringField(map, const ['action'], fallback: 'unknown'),
    entityType: stringField(map, const [
      'entity_type',
      'entityType',
    ], fallback: 'system'),
    actorUserId: nullableStringField(map, const [
      'actor_user_id',
      'actorUserId',
    ]),
    entityId: nullableStringField(map, const ['entity_id', 'entityId']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

String _e(String value) => Uri.encodeComponent(value);

String prettyJson(JsonMap value) {
  if (value.isEmpty) {
    return '';
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}
