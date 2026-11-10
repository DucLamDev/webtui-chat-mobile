import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/approvals/application/approval_access_policy.dart';
import 'package:webtui_chat/features/approvals/application/approval_notification_actions.dart';
import 'package:webtui_chat/features/approvals/application/use_cases/approval_use_cases.dart';
import 'package:webtui_chat/features/approvals/data/datasources/approval_remote_data_source.dart';
import 'package:webtui_chat/features/approvals/domain/entities/approval.dart';
import 'package:webtui_chat/features/approvals/domain/repositories/approval_repository.dart';
import 'package:webtui_chat/features/approvals/presentation/controllers/approval_detail_controller.dart';
import 'package:webtui_chat/features/approvals/presentation/controllers/approval_list_controller.dart';
import 'package:webtui_chat/features/approvals/presentation/screens/approval_list_screen.dart';
import 'package:webtui_chat/features/workspace/domain/entities/workspace_permission.dart';

Map<String, Object?> _approval({
  String id = 'a1',
  String status = 'pending',
  bool canDecide = true,
}) => {
  'id': id,
  'workspace_id': 'ws',
  'status': status,
  'title': 'Chi 5 triệu',
  'action': 'payment.create',
  'source': 'bot',
  'payload': {'amount': 5000000},
  'required_approvals': 2,
  'approvals_count': 1,
  'expires_at': '2026-11-12T03:00:00Z',
  'can_decide': canDecide,
  'decisions': [
    {'user_id': 'u1', 'decision': 'approve', 'comment': 'ok'},
  ],
};

void main() {
  group('ApprovalRemoteDataSource', () {
    test('list gửi status + cursor và đọc approvals / next_cursor', () async {
      final api = _Transport({
        'data': {
          'approvals': [_approval(), _approval(id: 'a2', canDecide: false)],
          'next_cursor': 'c2',
        },
      });
      final page = await ApprovalRemoteDataSource(
        api,
      ).list(workspaceId: 'ws', filter: ApprovalFilter.done, cursor: 'c1');
      expect(api.path, '/api/v1/workspaces/ws/approvals');
      expect(api.query, {'status': 'done', 'limit': 50, 'cursor': 'c1'});
      expect(page.items.map((e) => e.id), ['a1', 'a2']);
      expect(page.nextCursor, 'c2');
      final first = page.items.first;
      expect(first.canDecide, isTrue);
      expect(first.status, ApprovalStatus.pending);
      expect(first.sourceLabel, 'Bot');
      expect(first.decisions.single.decision, ApprovalDecisionKind.approve);
      expect(page.items.last.canDecide, isFalse);
    });

    test('thiếu can_decide thì coi là không được duyệt', () {
      final map = _approval()..remove('can_decide');
      expect(approvalFromMap(map).canDecide, isFalse);
    });

    test('decide POST đúng đường dẫn và nội dung', () async {
      final api = _Transport({
        'data': {'approval': _approval(status: 'approved')},
      });
      final result = await ApprovalRemoteDataSource(api).decide(
        workspaceId: 'ws',
        approvalId: 'a 1',
        decision: ApprovalDecisionKind.reject,
        comment: 'không hợp lệ',
      );
      expect(api.path, '/api/v1/workspaces/ws/approvals/a%201/decisions');
      expect(api.body, {'decision': 'reject', 'comment': 'không hợp lệ'});
      expect(result.status, ApprovalStatus.approved);
    });
  });

  group('ApprovalAccess', () {
    test('không hỗ trợ khi máy chủ không có discovery', () {
      final access = ApprovalAccess.resolve(discovery: null, permissions: null);
      expect(access.serverSupported, isFalse);
      expect(access.canView, isFalse);
    });

    ApprovalAccess accessFor({
      bool serverSupported = true,
      PermissionSet? permissions,
      bool loading = false,
      String? requested,
    }) => approvalAccessFor(
      serverSupported: serverSupported,
      permissions: permissions,
      permissionsLoading: loading,
      activeWorkspaceId: 'ws-a',
      requestedWorkspaceId: requested,
    );

    PermissionSet perms(List<String> codes) => PermissionSet([
      for (final code in codes)
        WorkspacePermission(
          id: code,
          code: code,
          module: 'approval',
          action: 'view',
          name: code,
        ),
    ]);

    test('workspace đang mở dùng quyền đã tải', () {
      expect(accessFor(permissions: perms(['approval.view'])).canView, isTrue);
      expect(accessFor(permissions: perms(['message.send'])).canView, isFalse);
      expect(accessFor(loading: true).isPending, isTrue);
      final loaded = accessFor();
      expect(loaded.isPending, isFalse);
      expect(loaded.canView, isFalse);
      expect(
        accessFor(
          serverSupported: false,
          permissions: perms(['approval.view']),
        ).canView,
        isFalse,
      );
    });

    test('workspace khác (mở từ thông báo) để máy chủ kiểm quyền', () {
      final other = accessFor(permissions: perms(const []), requested: 'ws-b');
      expect(other.canView, isTrue);
      expect(other.isPending, isFalse);
      expect(
        accessFor(permissions: perms(const []), requested: ' ws-a ').canView,
        isFalse,
      );
      expect(
        accessFor(serverSupported: false, requested: 'ws-b').canView,
        isFalse,
      );
    });
  });

  group('ApprovalListController', () {
    test('tải danh sách, rỗng, lỗi và 403', () async {
      final repo = _FakeRepository()..pages = [const ApprovalPage(items: [])];
      final controller = ApprovalListController.forTesting(repository: repo);
      await controller.load();
      expect(controller.state.hasLoaded, isTrue);
      expect(controller.state.items, isEmpty);
      expect(controller.state.errorMessage, isNull);

      repo.listFailure = const Failure(
        kind: FailureKind.network,
        message: 'Mất kết nối',
      );
      await controller.load();
      expect(controller.state.errorMessage, 'Mất kết nối');

      repo.listFailure = const Failure(
        kind: FailureKind.forbidden,
        message: 'no',
      );
      await controller.load();
      expect(controller.state.forbidden, isTrue);
      expect(controller.state.errorMessage, isNull);
      controller.dispose();
    });

    test('đổi tab, tải thêm theo cursor và bỏ trùng', () async {
      final repo = _FakeRepository()
        ..pages = [
          ApprovalPage(items: [approvalFromMap(_approval())], nextCursor: 'n'),
          ApprovalPage(
            items: [
              approvalFromMap(_approval()),
              approvalFromMap(_approval(id: 'a2')),
            ],
          ),
        ];
      final controller = ApprovalListController.forTesting(repository: repo);
      await controller.load();
      expect(controller.state.hasMore, isTrue);
      await controller.loadMore();
      expect(controller.state.items.map((e) => e.id), ['a1', 'a2']);
      expect(controller.state.hasMore, isFalse);
      expect(repo.cursors, [null, 'n']);

      repo.pages = [const ApprovalPage(items: [])];
      await controller.setFilter(ApprovalFilter.done);
      expect(repo.filters.last, ApprovalFilter.done);
      expect(controller.state.items, isEmpty);
      controller.dispose();
    });

    test('refresh im lặng: lỗi mạng không xoá danh sách đang có', () async {
      final repo = _FakeRepository()
        ..pages = [
          ApprovalPage(items: [approvalFromMap(_approval())]),
        ];
      final controller = ApprovalListController.forTesting(repository: repo);
      await controller.load();
      repo.listFailure = const Failure(kind: FailureKind.network, message: 'x');
      await controller.refresh();
      expect(controller.state.items, hasLength(1));
      expect(controller.state.errorMessage, isNull);
      controller.dispose();
    });
  });

  group('ApprovalDetailController', () {
    test('duyệt thành công cập nhật phiếu', () async {
      final repo = _FakeRepository()
        ..detail = approvalFromMap(_approval())
        ..decided = approvalFromMap(_approval(status: 'approved'));
      final controller = ApprovalDetailController.forTesting(repository: repo);
      await controller.load();
      expect(controller.state.approval!.canDecide, isTrue);
      final ok = await controller.decide(ApprovalDecisionKind.approve);
      expect(ok, isTrue);
      expect(controller.state.approval!.status, ApprovalStatus.approved);
      expect(controller.state.actionMessage, 'Đã duyệt yêu cầu.');
      controller.dispose();
    });

    test('403 và 409 báo lỗi rõ ràng bằng tiếng Việt', () async {
      final repo = _FakeRepository()..detail = approvalFromMap(_approval());
      final controller = ApprovalDetailController.forTesting(repository: repo);
      await controller.load();
      repo.decideFailure = const Failure(
        kind: FailureKind.forbidden,
        message: 'forbidden',
        code: 'APPROVAL_FORBIDDEN',
      );
      expect(await controller.decide(ApprovalDecisionKind.approve), isFalse);
      expect(
        controller.state.actionMessage,
        'Bạn không có quyền duyệt yêu cầu này.',
      );
      repo.decideFailure = const Failure(
        kind: FailureKind.conflict,
        message: 'conflict',
        code: 'APPROVAL_NOT_PENDING',
      );
      expect(await controller.decide(ApprovalDecisionKind.reject), isFalse);
      expect(
        controller.state.actionMessage,
        'Yêu cầu không còn ở trạng thái chờ duyệt.',
      );
      controller.dispose();
    });

    test('403 khi tải chi tiết hiện trạng thái không quyền', () async {
      final repo = _FakeRepository()
        ..detailFailure = const Failure(
          kind: FailureKind.forbidden,
          message: 'x',
        );
      final controller = ApprovalDetailController.forTesting(repository: repo);
      await controller.load();
      expect(controller.state.forbidden, isTrue);
      controller.dispose();
    });
  });

  group('ApprovalNotificationActionHandler', () {
    test('Duyệt thành công báo kết quả', () async {
      final repo = _FakeRepository()
        ..decided = approvalFromMap(_approval(status: 'approved'));
      final reports = <String>[];
      final handler = ApprovalNotificationActionHandler(
        decide: DecideApprovalRequestUseCase(repo),
        report: ({required approvalId, required title, required body}) async =>
            reports.add('$approvalId|$title|$body'),
      );
      expect(
        await handler.handle(
          workspaceId: 'ws',
          approvalId: 'a1',
          approve: true,
        ),
        isTrue,
      );
      expect(repo.lastDecision, ApprovalDecisionKind.approve);
      expect(reports.single, 'a1|Đã duyệt yêu cầu|Chi 5 triệu');
    });

    test('Từ chối bị 409 vẫn báo lỗi, không im lặng', () async {
      final repo = _FakeRepository()
        ..decideFailure = const Failure(
          kind: FailureKind.conflict,
          message: 'x',
          code: 'APPROVAL_ALREADY_DECIDED',
        );
      final reports = <String>[];
      final handler = ApprovalNotificationActionHandler(
        decide: DecideApprovalRequestUseCase(repo),
        report: ({required approvalId, required title, required body}) async =>
            reports.add('$title|$body'),
      );
      expect(
        await handler.handle(
          workspaceId: 'ws',
          approvalId: 'a1',
          approve: false,
        ),
        isFalse,
      );
      expect(repo.lastDecision, ApprovalDecisionKind.reject);
      expect(
        reports.single,
        'Chưa từ chối được|Bạn đã quyết định yêu cầu này rồi.',
      );
    });

    const instance = '33333333-3333-4333-8333-333333333333';
    final now = DateTime.utc(2026, 11, 10, 12);

    ApprovalNotificationActionHandler handlerFor(
      _FakeRepository repo,
      List<String> reports,
    ) => ApprovalNotificationActionHandler(
      decide: DecideApprovalRequestUseCase(repo),
      report: ({required approvalId, required title, required body}) async =>
          reports.add('$approvalId|$title|$body'),
      now: () => now,
    );

    test('mỗi quyết định gửi theo workspace của nó, không bỏ', () async {
      final repo = _FakeRepository()
        ..decided = approvalFromMap(_approval(status: 'approved'));
      final reports = <String>[];
      await handlerFor(repo, reports).handleAll([
        (
          instanceId: instance,
          decidedAt: now.subtract(const Duration(minutes: 5)),
          workspaceId: 'ws-a',
          approvalId: 'a1',
          approve: true,
        ),
        (
          instanceId: instance.toUpperCase(),
          decidedAt: null,
          workspaceId: 'ws-b',
          approvalId: 'b1',
          approve: false,
        ),
      ], activeInstanceId: instance);
      expect(repo.decidedWorkspaces, ['ws-a/a1', 'ws-b/b1']);
      expect(reports, hasLength(2));
    });

    test('máy chủ khác hoặc quá 24 giờ: không gửi mà báo rõ', () async {
      final repo = _FakeRepository()
        ..decided = approvalFromMap(_approval(status: 'approved'));
      final reports = <String>[];
      await handlerFor(repo, reports).handleAll([
        (
          instanceId: '44444444-4444-4444-8444-444444444444',
          decidedAt: now,
          workspaceId: 'ws-a',
          approvalId: 'x1',
          approve: true,
        ),
        (
          instanceId: null,
          decidedAt: now,
          workspaceId: 'ws-a',
          approvalId: 'x2',
          approve: true,
        ),
        (
          instanceId: instance,
          decidedAt: now.subtract(const Duration(hours: 25)),
          workspaceId: 'ws-a',
          approvalId: 'x3',
          approve: false,
        ),
      ], activeInstanceId: instance);
      expect(repo.decidedWorkspaces, isEmpty);
      expect(reports, [
        'x1|Chưa duyệt được|Yêu cầu thuộc máy chủ khác. Mở app trên máy chủ đó để xử lý.',
        'x2|Chưa duyệt được|Yêu cầu thuộc máy chủ khác. Mở app trên máy chủ đó để xử lý.',
        'x3|Chưa từ chối được|Lần bấm đã quá 24 giờ nên chưa gửi. Mở yêu cầu để xử lý lại.',
      ]);
    });
  });

  test('đường dẫn chi tiết mã hoá mã yêu cầu và kèm workspace', () {
    expect(
      approvalDetailLocation(approvalId: ' a/1 ', workspaceId: 'ws-b'),
      '/approvals/a%2F1?workspaceId=ws-b',
    );
  });
}

final class _FakeRepository implements ApprovalRepository {
  List<ApprovalPage> pages = [];
  Failure? listFailure;
  ApprovalRequest? detail;
  Failure? detailFailure;
  ApprovalRequest? decided;
  Failure? decideFailure;
  ApprovalDecisionKind? lastDecision;
  final decidedWorkspaces = <String>[];
  final List<String?> cursors = [];
  final List<ApprovalFilter> filters = [];
  int _page = 0;

  @override
  Future<Result<ApprovalPage>> list({
    required String workspaceId,
    required ApprovalFilter filter,
    String? cursor,
    int limit = 50,
  }) async {
    cursors.add(cursor);
    filters.add(filter);
    final failure = listFailure;
    if (failure != null) {
      listFailure = null;
      return FailureResult(failure);
    }
    final page = pages[_page < pages.length ? _page : pages.length - 1];
    _page++;
    return Success(page);
  }

  @override
  Future<Result<ApprovalRequest>> get({
    required String workspaceId,
    required String approvalId,
  }) async {
    final failure = detailFailure;
    if (failure != null) return FailureResult(failure);
    return Success(detail!);
  }

  @override
  Future<Result<ApprovalRequest>> decide({
    required String workspaceId,
    required String approvalId,
    required ApprovalDecisionKind decision,
    String comment = '',
  }) async {
    lastDecision = decision;
    decidedWorkspaces.add('$workspaceId/$approvalId');
    final failure = decideFailure;
    if (failure != null) return FailureResult(failure);
    return Success(decided ?? detail!);
  }
}

final class _Transport implements ApiTransport {
  _Transport(this.response);

  final Object? response;
  String? path;
  Object? body;
  Map<String, dynamic>? query;

  Response<T> _r<T>(String p) => Response<T>(
    data: response as T?,
    requestOptions: RequestOptions(path: p),
    statusCode: 200,
  );

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    this.path = path;
    query = queryParameters;
    return _r(path);
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    this.path = path;
    body = data;
    return _r(path);
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
