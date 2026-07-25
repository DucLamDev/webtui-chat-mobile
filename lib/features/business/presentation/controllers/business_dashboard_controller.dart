import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../application/use_cases/business_dashboard_use_cases.dart';
import '../../domain/entities/business_dashboard.dart';

final businessDashboardControllerProvider = StateNotifierProvider.autoDispose
    .family<BusinessDashboardController, BusinessDashboardState, String>((
      ref,
      workspaceId,
    ) {
      return BusinessDashboardController(
        workspaceId: workspaceId,
        loadUseCase: ref.watch(loadBusinessDashboardUseCaseProvider),
        createTicketUseCase: ref.watch(createTicketUseCaseProvider),
        testBotFlowUseCase: ref.watch(testBotFlowUseCaseProvider),
        publishBotFlowUseCase: ref.watch(publishBotFlowUseCaseProvider),
        updateTicketStatusUseCase: ref.watch(updateTicketStatusUseCaseProvider),
        revokeApiTokenUseCase: ref.watch(revokeApiTokenUseCaseProvider),
        runCronJobUseCase: ref.watch(runCronJobUseCaseProvider),
        updateCronJobStatusUseCase: ref.watch(
          updateCronJobStatusUseCaseProvider,
        ),
      )..load();
    });

final class BusinessDashboardState {
  const BusinessDashboardState({
    required this.workspaceId,
    this.data,
    this.isLoading = false,
    this.isRefreshing = false,
    this.isTestingFlow = false,
    this.errorMessage,
    this.noticeMessage,
    this.lastFlowRun,
  });

  final String workspaceId;
  final BusinessDashboardData? data;
  final bool isLoading;
  final bool isRefreshing;
  final bool isTestingFlow;
  final String? errorMessage;
  final String? noticeMessage;
  final BotFlowRunSummary? lastFlowRun;

  BusinessDashboardState copyWith({
    BusinessDashboardData? data,
    bool? isLoading,
    bool? isRefreshing,
    bool? isTestingFlow,
    String? errorMessage,
    String? noticeMessage,
    BotFlowRunSummary? lastFlowRun,
    bool clearError = false,
    bool clearNotice = false,
  }) {
    return BusinessDashboardState(
      workspaceId: workspaceId,
      data: data ?? this.data,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isTestingFlow: isTestingFlow ?? this.isTestingFlow,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      noticeMessage: clearNotice ? null : noticeMessage ?? this.noticeMessage,
      lastFlowRun: lastFlowRun ?? this.lastFlowRun,
    );
  }
}

final class BusinessDashboardController
    extends StateNotifier<BusinessDashboardState> {
  BusinessDashboardController({
    required String workspaceId,
    required LoadBusinessDashboardUseCase loadUseCase,
    required CreateTicketUseCase createTicketUseCase,
    required TestBotFlowUseCase testBotFlowUseCase,
    required PublishBotFlowUseCase publishBotFlowUseCase,
    required UpdateTicketStatusUseCase updateTicketStatusUseCase,
    required RevokeApiTokenUseCase revokeApiTokenUseCase,
    required RunCronJobUseCase runCronJobUseCase,
    required UpdateCronJobStatusUseCase updateCronJobStatusUseCase,
  }) : _loadUseCase = loadUseCase,
       _createTicketUseCase = createTicketUseCase,
       _testBotFlowUseCase = testBotFlowUseCase,
       _publishBotFlowUseCase = publishBotFlowUseCase,
       _updateTicketStatusUseCase = updateTicketStatusUseCase,
       _revokeApiTokenUseCase = revokeApiTokenUseCase,
       _runCronJobUseCase = runCronJobUseCase,
       _updateCronJobStatusUseCase = updateCronJobStatusUseCase,
       super(BusinessDashboardState(workspaceId: workspaceId));

  final LoadBusinessDashboardUseCase _loadUseCase;
  final CreateTicketUseCase _createTicketUseCase;
  final TestBotFlowUseCase _testBotFlowUseCase;
  final PublishBotFlowUseCase _publishBotFlowUseCase;
  final UpdateTicketStatusUseCase _updateTicketStatusUseCase;
  final RevokeApiTokenUseCase _revokeApiTokenUseCase;
  final RunCronJobUseCase _runCronJobUseCase;
  final UpdateCronJobStatusUseCase _updateCronJobStatusUseCase;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _loadUseCase.execute(workspaceId: state.workspaceId);
      state = state.copyWith(data: data, isLoading: false);
    } on Object {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Không thể tải module nghiệp vụ.',
      );
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final data = await _loadUseCase.execute(workspaceId: state.workspaceId);
      state = state.copyWith(data: data, isRefreshing: false);
    } on Object {
      state = state.copyWith(
        isRefreshing: false,
        errorMessage: 'Không thể làm mới module nghiệp vụ.',
      );
    }
  }

  Future<void> testFlow(BotWorkspaceDetail detail, BotFlowSummary flow) async {
    state = state.copyWith(isTestingFlow: true, clearError: true);
    final result = await _testBotFlowUseCase.execute(
      workspaceId: state.workspaceId,
      botId: detail.bot.id,
      flowId: flow.id,
      input: 'Khách cần hỗ trợ đơn hàng mẫu',
    );
    switch (result) {
      case Success<BotFlowRunSummary>(value: final run):
        state = state.copyWith(
          isTestingFlow: false,
          lastFlowRun: run,
          noticeMessage: run.error?.isNotEmpty == true
              ? 'Flow test lỗi: ${run.error}'
              : 'Flow test đã tạo run ${run.status}.',
        );
      case FailureResult<BotFlowRunSummary>(failure: final failure):
        state = state.copyWith(
          isTestingFlow: false,
          errorMessage: failure.message,
        );
    }
  }

  Future<void> createTicket(CreateTicketDraft draft) async {
    final result = await _createTicketUseCase.execute(
      workspaceId: state.workspaceId,
      draft: draft,
    );
    switch (result) {
      case Success<TicketSummary>(value: final ticket):
        final data = state.data;
        if (data == null) {
          return;
        }
        state = state.copyWith(
          data: _copyDashboardData(data, tickets: [ticket, ...data.tickets]),
          noticeMessage: 'Ticket đã được tạo.',
        );
      case FailureResult<TicketSummary>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> publishFlow(
    BotWorkspaceDetail detail,
    BotFlowSummary flow,
  ) async {
    final result = await _publishBotFlowUseCase.execute(
      workspaceId: state.workspaceId,
      botId: detail.bot.id,
      flowId: flow.id,
    );
    switch (result) {
      case Success<BotFlowSummary>(value: final published):
        final data = state.data;
        if (data == null) {
          return;
        }
        state = state.copyWith(
          data: _replaceFlow(data, detail, published),
          noticeMessage: 'Flow đã publish.',
        );
      case FailureResult<BotFlowSummary>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> updateTicketStatus(TicketSummary ticket, String status) async {
    final result = await _updateTicketStatusUseCase.execute(
      workspaceId: state.workspaceId,
      ticketId: ticket.id,
      status: status,
    );
    switch (result) {
      case Success<TicketSummary>(value: final updated):
        final data = state.data;
        if (data == null) {
          return;
        }
        state = state.copyWith(
          data: _copyDashboardData(
            data,
            tickets: [
              for (final item in data.tickets)
                if (item.id == updated.id) updated else item,
            ],
          ),
          noticeMessage: 'Ticket đã chuyển sang $status.',
        );
      case FailureResult<TicketSummary>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> revokeApiToken(ApiTokenSummary token) async {
    final result = await _revokeApiTokenUseCase.execute(
      workspaceId: state.workspaceId,
      tokenId: token.id,
    );
    switch (result) {
      case Success<void>():
        final data = state.data;
        if (data == null) {
          return;
        }
        state = state.copyWith(
          data: _copyDashboardData(
            data,
            apiTokens: [
              for (final item in data.apiTokens)
                if (item.id != token.id) item,
            ],
          ),
          noticeMessage: 'API token đã được thu hồi.',
        );
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> runCronJob(CronJobSummary cronJob) async {
    final result = await _runCronJobUseCase.execute(
      workspaceId: state.workspaceId,
      cronJobId: cronJob.id,
    );
    switch (result) {
      case Success<void>():
        state = state.copyWith(noticeMessage: 'Cronjob đã được chạy thủ công.');
      case FailureResult<void>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }

  Future<void> updateCronJobStatus(
    CronJobSummary cronJob,
    String status,
  ) async {
    final result = await _updateCronJobStatusUseCase.execute(
      workspaceId: state.workspaceId,
      cronJob: cronJob,
      status: status,
    );
    switch (result) {
      case Success<CronJobSummary>(value: final updated):
        final data = state.data;
        if (data == null) {
          return;
        }
        state = state.copyWith(
          data: _copyDashboardData(
            data,
            cronJobs: [
              for (final item in data.cronJobs)
                if (item.id == updated.id) updated else item,
            ],
          ),
          noticeMessage: 'Cronjob đã chuyển sang $status.',
        );
      case FailureResult<CronJobSummary>(failure: final failure):
        state = state.copyWith(errorMessage: failure.message);
    }
  }
}

BusinessDashboardData _replaceFlow(
  BusinessDashboardData data,
  BotWorkspaceDetail detail,
  BotFlowSummary flow,
) {
  return BusinessDashboardData(
    workspaceId: data.workspaceId,
    departments: data.departments,
    tickets: data.tickets,
    bots: data.bots,
    botDetail: BotWorkspaceDetail(
      bot: detail.bot,
      aiConfig: detail.aiConfig,
      flows: [
        for (final item in detail.flows)
          if (item.id == flow.id) flow else item,
      ],
      installations: detail.installations,
    ),
    webhooks: data.webhooks,
    cronJobs: data.cronJobs,
    adminStats: data.adminStats,
    adminHealth: data.adminHealth,
    apiTokens: data.apiTokens,
    auditLogs: data.auditLogs,
    errors: data.errors,
  );
}

BusinessDashboardData _copyDashboardData(
  BusinessDashboardData data, {
  List<TicketSummary>? tickets,
  List<CronJobSummary>? cronJobs,
  List<ApiTokenSummary>? apiTokens,
}) {
  return BusinessDashboardData(
    workspaceId: data.workspaceId,
    departments: data.departments,
    tickets: tickets ?? data.tickets,
    bots: data.bots,
    botDetail: data.botDetail,
    webhooks: data.webhooks,
    cronJobs: cronJobs ?? data.cronJobs,
    adminStats: data.adminStats,
    adminHealth: data.adminHealth,
    apiTokens: apiTokens ?? data.apiTokens,
    auditLogs: data.auditLogs,
    errors: data.errors,
  );
}
