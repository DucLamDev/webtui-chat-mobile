import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/network/api_transport.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/notifications/application/use_cases/notification_use_cases.dart';
import 'package:webtui_chat/features/notifications/data/datasources/notification_remote_data_source.dart';
import 'package:webtui_chat/features/notifications/domain/entities/mobile_notification.dart';
import 'package:webtui_chat/features/notifications/domain/repositories/notification_repository.dart';
import 'package:webtui_chat/features/notifications/presentation/controllers/notification_center_controller.dart';
import 'package:webtui_chat/features/notifications/presentation/screens/notifications_screen.dart';

void main() {
  group('DeleteNotificationUseCase', () {
    test('xoá được thì thành công', () async {
      final repository = _FakeNotificationRepository();
      final result = await DeleteNotificationUseCase(
        repository,
      ).execute(notificationId: ' n-1 ');

      expect(result.isSuccess, isTrue);
      expect(repository.deletedIds, ['n-1']);
    });

    test('thông báo đã bị xoá ở thiết bị khác: coi như xong', () async {
      final repository = _FakeNotificationRepository(
        deleteFailure: const Failure(
          kind: FailureKind.notFound,
          message: 'Không tìm thấy thông báo.',
          code: 'NOTIFICATION_NOT_FOUND',
        ),
      );

      final result = await DeleteNotificationUseCase(
        repository,
      ).execute(notificationId: 'n-1');

      expect(result.isSuccess, isTrue);
    });

    test('máy chủ cũ chưa có API xoá: báo cần cập nhật máy chủ', () async {
      final repository = _FakeNotificationRepository(
        deleteFailure: const Failure(
          kind: FailureKind.notFound,
          message: 'Không tìm thấy dữ liệu.',
        ),
      );

      final result = await DeleteNotificationUseCase(
        repository,
      ).execute(notificationId: 'n-1');

      final failure = (result as FailureResult<void>).failure;
      expect(failure.code, 'NOTIFICATION_DELETE_UNSUPPORTED');
      expect(failure.message, notificationDeleteUnsupportedMessage);
    });

    test('lỗi mạng giữ nguyên câu báo lỗi', () async {
      final repository = _FakeNotificationRepository(
        deleteFailure: const Failure(
          kind: FailureKind.network,
          message: 'Mất kết nối mạng.',
        ),
      );

      final result = await DeleteNotificationUseCase(
        repository,
      ).execute(notificationId: 'n-1');

      expect(
        (result as FailureResult<void>).failure.message,
        'Mất kết nối mạng.',
      );
    });

    test('thiếu mã thông báo thì không gọi máy chủ', () async {
      final repository = _FakeNotificationRepository();
      final result = await DeleteNotificationUseCase(
        repository,
      ).execute(notificationId: '  ');

      expect(result.isFailure, isTrue);
      expect(repository.deletedIds, isEmpty);
    });
  });

  group('NotificationRemoteDataSource xoá', () {
    test('gọi DELETE đúng đường dẫn', () async {
      final transport = _RecordingApiTransport();
      final remote = NotificationRemoteDataSource(transport);

      await remote.deleteNotification(notificationId: 'n/1');
      await remote.deleteAllNotifications(workspaceId: 'ws-1');

      expect(transport.calls, [
        'DELETE /api/v1/notifications/n%2F1 {}',
        'DELETE /api/v1/notifications {workspace_id: ws-1}',
      ]);
    });
  });

  group('NotificationCenterController xoá', () {
    test('xoá lỗi thì trả thông báo về đúng chỗ cũ', () async {
      final repository = _FakeNotificationRepository(
        items: [
          _notification('n-1'),
          _notification('n-2'),
          _notification('n-3'),
        ],
        deleteFailure: const Failure(
          kind: FailureKind.network,
          message: 'Mất kết nối mạng.',
        ),
      );
      final controller = _controller(repository);
      await controller.load();

      final error = await controller.delete(controller.state.notifications[1]);

      expect(error, 'Mất kết nối mạng.');
      expect(controller.state.notifications.map((item) => item.id), [
        'n-1',
        'n-2',
        'n-3',
      ]);
    });

    test('xoá tất cả thành công thì danh sách rỗng', () async {
      final repository = _FakeNotificationRepository(
        items: [_notification('n-1'), _notification('n-2')],
      );
      final controller = _controller(repository);
      await controller.load();

      expect(await controller.deleteAll(), isNull);
      expect(controller.state.notifications, isEmpty);
      expect(repository.deletedAllWorkspaceIds, ['ws-1']);
    });

    test('xoá tất cả lỗi thì giữ nguyên danh sách', () async {
      final repository = _FakeNotificationRepository(
        items: [_notification('n-1')],
        deleteFailure: const Failure(
          kind: FailureKind.server,
          message: 'Máy chủ đang bận.',
        ),
      );
      final controller = _controller(repository);
      await controller.load();

      expect(await controller.deleteAll(), 'Máy chủ đang bận.');
      expect(controller.state.notifications, hasLength(1));
      expect(controller.state.isDeletingAll, isFalse);
    });
  });

  group('Màn Thông báo', () {
    testWidgets('vuốt sang trái để xoá một thông báo', (tester) async {
      final repository = _FakeNotificationRepository(
        items: [_notification('n-1'), _notification('n-2')],
      );
      await _pumpScreen(tester, repository);

      await tester.drag(find.text('Thông báo n-1'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, ['n-1']);
      expect(find.text('Thông báo n-1'), findsNothing);
      expect(find.text('Thông báo n-2'), findsOneWidget);
      expect(find.text('Đã xoá thông báo.'), findsOneWidget);
    });

    testWidgets('giữ lâu để mở menu xoá', (tester) async {
      final repository = _FakeNotificationRepository(
        items: [_notification('n-1')],
      );
      await _pumpScreen(tester, repository);

      await tester.longPress(find.text('Thông báo n-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification_action_delete')));
      await tester.pumpAndSettle();

      expect(repository.deletedIds, ['n-1']);
      expect(find.text('Chưa có thông báo'), findsOneWidget);
    });

    testWidgets('xoá tất cả phải xác nhận', (tester) async {
      final repository = _FakeNotificationRepository(
        items: [_notification('n-1'), _notification('n-2')],
      );
      await _pumpScreen(tester, repository);

      await tester.tap(find.byKey(const Key('notifications_delete_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(repository.deletedAllWorkspaceIds, isEmpty);

      await tester.tap(find.byKey(const Key('notifications_delete_all')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('notifications_delete_all_confirm')),
      );
      await tester.pumpAndSettle();

      expect(repository.deletedAllWorkspaceIds, ['ws-1']);
      expect(find.text('Chưa có thông báo'), findsOneWidget);
      expect(find.text('Đã xoá tất cả thông báo.'), findsOneWidget);
    });
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeNotificationRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: NotificationsScreen(workspaceId: 'ws-1')),
    ),
  );
  await tester.pumpAndSettle();
}

NotificationCenterController _controller(NotificationRepository repository) {
  return NotificationCenterController(
    workspaceId: 'ws-1',
    listUseCase: ListNotificationsUseCase(repository),
    markReadUseCase: MarkNotificationReadUseCase(repository),
    markAllReadUseCase: MarkAllNotificationsReadUseCase(repository),
    deleteUseCase: DeleteNotificationUseCase(repository),
    deleteAllUseCase: DeleteAllNotificationsUseCase(repository),
  );
}

MobileNotification _notification(String id) {
  return MobileNotification(
    id: id,
    workspaceId: 'ws-1',
    type: 'system',
    title: 'Thông báo $id',
    body: 'Nội dung $id',
    createdAt: DateTime.utc(2026, 11, 2, 9),
  );
}

final class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository({this.items = const [], this.deleteFailure});

  final List<MobileNotification> items;
  final Failure? deleteFailure;
  final deletedIds = <String>[];
  final deletedAllWorkspaceIds = <String>[];

  @override
  Future<Result<List<MobileNotification>>> listNotifications({
    required String workspaceId,
    int limit = 50,
  }) async => Success(items);

  @override
  Future<Result<void>> deleteNotification({
    required String notificationId,
  }) async {
    if (deleteFailure case final failure?) return FailureResult(failure);
    deletedIds.add(notificationId);
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteAllNotifications({
    required String workspaceId,
  }) async {
    if (deleteFailure case final failure?) return FailureResult(failure);
    deletedAllWorkspaceIds.add(workspaceId);
    return const Success(null);
  }

  @override
  Future<Result<void>> markRead({required String notificationId}) async =>
      const Success(null);

  @override
  Future<Result<void>> markAllRead({required String workspaceId}) async =>
      const Success(null);

  @override
  Future<Result<NotificationPreference>> getPreference({
    required String workspaceId,
  }) => throw UnimplementedError();

  @override
  Future<Result<NotificationPreference>> savePreference(
    NotificationPreference preference,
  ) => throw UnimplementedError();

  @override
  Future<Result<List<PushDeviceRegistration>>> listPushDevices() =>
      throw UnimplementedError();

  @override
  Future<Result<void>> unregisterPushDevice({required String deviceId}) =>
      throw UnimplementedError();
}

final class _RecordingApiTransport implements ApiTransport {
  final calls = <String>[];

  Response<T> _ok<T>(String path) =>
      Response<T>(requestOptions: RequestOptions(path: path), statusCode: 204);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    calls.add('DELETE $path ${queryParameters ?? {}}');
    return _ok<T>(path);
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();

  @override
  Future<Response<T>> post<T>(
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

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => throw UnimplementedError();
}
