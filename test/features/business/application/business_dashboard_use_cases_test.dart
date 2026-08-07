import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/business/application/use_cases/business_dashboard_use_cases.dart';
import 'package:webtui_chat/features/business/domain/entities/business_dashboard.dart';
import 'package:webtui_chat/features/business/domain/repositories/business_repository.dart';

void main() {
  test('loads independent dashboard modules concurrently', () async {
    final repository = _ConcurrentBusinessRepository();

    final data = await LoadBusinessDashboardUseCase(
      repository,
    ).execute(workspaceId: 'workspace-1');

    expect(data.workspaceId, 'workspace-1');
    expect(repository.peakRequests, 9);
  });
}

final class _ConcurrentBusinessRepository implements BusinessRepository {
  int _activeRequests = 0;
  int peakRequests = 0;

  Future<Result<T>> _result<T>(T value) async {
    _activeRequests += 1;
    if (_activeRequests > peakRequests) {
      peakRequests = _activeRequests;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _activeRequests -= 1;
    return Success<T>(value);
  }

  @override
  Future<Result<List<DepartmentSummary>>> listDepartments({
    required String workspaceId,
  }) => _result(const []);

  @override
  Future<Result<List<TicketSummary>>> listTickets({
    required String workspaceId,
  }) => _result(const []);

  @override
  Future<Result<List<BotSummary>>> listBots({required String workspaceId}) =>
      _result(const []);

  @override
  Future<Result<List<WebhookSummary>>> listWebhooks({
    required String workspaceId,
  }) => _result(const []);

  @override
  Future<Result<List<CronJobSummary>>> listCronJobs({
    required String workspaceId,
  }) => _result(const []);

  @override
  Future<Result<AdminStatsSummary>> loadAdminStats({
    required String workspaceId,
  }) => _result(const AdminStatsSummary());

  @override
  Future<Result<AdminHealthSummary>> loadAdminHealth({
    required String workspaceId,
  }) => _result(const AdminHealthSummary(status: 'ready'));

  @override
  Future<Result<List<ApiTokenSummary>>> listApiTokens({
    required String workspaceId,
  }) => _result(const []);

  @override
  Future<Result<List<AuditLogSummary>>> listAuditLogs({
    required String workspaceId,
  }) => _result(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
