import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/error/failure.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/design_system/tokens/webtui_colors.dart';
import 'package:webtui_chat/features/conversations/domain/entities/channel_exit.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';
import 'package:webtui_chat/features/conversations/domain/repositories/channel_exit_repository.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/channel_membership_events.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/channel_exit_actions.dart';
import 'package:webtui_chat/features/conversations/presentation/widgets/chat_room_app_bar.dart';

ConversationSummary _group({
  ConversationKind kind = ConversationKind.channel,
  ChannelVisibility visibility = ChannelVisibility.private,
  bool canLeave = true,
  bool canDelete = true,
}) {
  return ConversationSummary(
    id: 'ch-1',
    workspaceId: 'ws',
    channelId: 'ch-1',
    kind: kind,
    title: 'Nhóm A',
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 16),
    channelVisibility: visibility,
    membershipStatus: MembershipStatus.active,
    canLeave: canLeave,
    canDelete: canDelete,
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final leaveRow = find.byKey(const ValueKey('channel-leave-group'));
  final deleteRow = find.byKey(const ValueKey('channel-delete-group'));

  group('màn thông tin nhóm', () {
    Future<void> pump(WidgetTester tester, ConversationSummary channel) {
      return tester.pumpWidget(
        MaterialApp(
          theme: WebTuiTheme.light(),
          home: Scaffold(
            body: ListView(
              children: [
                ChannelExitSettings(
                  channel: channel,
                  onLeave: () {},
                  onDelete: () {},
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('đủ cờ: có "Rời nhóm" và "Xoá nhóm" (ghi rõ cho mọi người)', (
      tester,
    ) async {
      await pump(tester, _group());
      expect(find.text('Rời nhóm'), findsOneWidget);
      expect(find.text('Xoá nhóm'), findsOneWidget);
      expect(find.text('Xoá cho mọi thành viên'), findsOneWidget);
      expect(tester.getSize(leaveRow).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(deleteRow).height, greaterThanOrEqualTo(48));
    });

    testWidgets('chỉ có cờ rời: không có nút xoá', (tester) async {
      await pump(tester, _group(canDelete: false));
      expect(leaveRow, findsOneWidget);
      expect(deleteRow, findsNothing);
    });

    testWidgets('không có cờ (máy chủ cũ) hoặc chat 1-1: ẩn hẳn', (
      tester,
    ) async {
      await pump(tester, _group(canLeave: false, canDelete: false));
      expect(leaveRow, findsNothing);
      expect(deleteRow, findsNothing);

      await pump(
        tester,
        _group(
          kind: ConversationKind.direct,
          visibility: ChannelVisibility.direct,
        ),
      );
      expect(leaveRow, findsNothing);
      expect(deleteRow, findsNothing);
    });

    testWidgets('kênh công khai (quản trị): ghi "Xoá kênh"', (tester) async {
      await pump(tester, _group(visibility: ChannelVisibility.public));
      expect(leaveRow, findsNothing);
      expect(find.text('Xoá kênh'), findsOneWidget);
    });
  });

  test('chữ đỏ đủ tương phản (≥ 4.5:1) trên nền sáng và nền tối', () {
    addTearDown(() => WebTuiColors.apply(Brightness.light));
    for (final brightness in Brightness.values) {
      WebTuiColors.apply(brightness);
      expect(
        _contrast(channelExitDangerText, WebTuiColors.surface),
        greaterThanOrEqualTo(4.5),
        reason: brightness.name,
      );
    }
  });

  group('menu ≡ phòng chat', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      VoidCallback? onLeave,
      VoidCallback? onDelete,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: WebTuiTheme.light(),
          home: Scaffold(
            appBar: ChatRoomAppBar(
              title: 'Nhóm A',
              noticeBot: false,
              directChat: false,
              memberCount: 3,
              callsEnabled: false,
              onCall: (_) {},
              onSearch: () {},
              onTools: () {},
              onDetails: () {},
              onLeaveGroup: onLeave,
              onDeleteGroup: onDelete,
            ),
          ),
        ),
      );
    }

    testWidgets('có quyền: hiện "Rời nhóm", "Xoá nhóm", bấm gọi đúng việc', (
      tester,
    ) async {
      var left = 0;
      var deleted = 0;
      await pumpBar(tester, onLeave: () => left++, onDelete: () => deleted++);
      await tester.tap(find.byKey(const Key('chat_room_more_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Rời nhóm'), findsOneWidget);
      expect(find.text('Xoá nhóm'), findsOneWidget);
      expect(find.text('Xoá cho mọi thành viên'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('chat_room_leave_group'))).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('Rời nhóm'));
      await tester.pumpAndSettle();
      expect(left, 1);

      await tester.tap(find.byKey(const Key('chat_room_more_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá nhóm'));
      await tester.pumpAndSettle();
      expect(deleted, 1);
    });

    testWidgets('không có quyền: menu không có hai mục', (tester) async {
      await pumpBar(tester);
      await tester.tap(find.byKey(const Key('chat_room_more_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Chi tiết kênh'), findsOneWidget);
      expect(find.text('Rời nhóm'), findsNothing);
      expect(find.text('Xoá nhóm'), findsNothing);
    });
  });

  group('luồng xác nhận → gọi máy chủ → về Tin nhắn', () {
    late _FakeRepository repository;

    Future<ProviderContainer> pumpFlow(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/room',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Danh sách Tin nhắn')),
          ),
          GoRoute(
            path: '/room',
            builder: (_, _) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Column(
                  children: [
                    const Text('Phòng chat'),
                    TextButton(
                      onPressed: () => confirmAndLeaveGroup(
                        context,
                        ref,
                        workspaceId: 'ws',
                        channel: _group(),
                      ),
                      child: const Text('bấm rời'),
                    ),
                    TextButton(
                      onPressed: () => confirmAndDeleteGroup(
                        context,
                        ref,
                        workspaceId: 'ws',
                        channel: _group(),
                      ),
                      child: const Text('bấm xoá'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [
          channelExitRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: WebTuiTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('rời nhóm: khoá nút khi đang chạy, xong thì về danh sách', (
      tester,
    ) async {
      repository = _FakeRepository();
      final pending = Completer<Result<ChannelLeaveResult>>();
      repository.leaveResponse = pending.future;
      final container = await pumpFlow(tester);

      await tester.tap(find.text('bấm rời'));
      await tester.pumpAndSettle();
      expect(find.text('Rời nhóm?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
      await tester.pump();
      // Đang chạy: nút chính quay vòng, bấm lại không gọi thêm lần nữa.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('webtui_dialog_confirm')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(repository.calls, ['leave ws/ch-1']);

      pending.complete(
        const Success(ChannelLeaveResult(channelId: 'ch-1', archived: false)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Danh sách Tin nhắn'), findsOneWidget);
      expect(find.text('Phòng chat'), findsNothing);
      expect(find.text('Đã rời nhóm'), findsOneWidget);
      final signal = container.read(channelRemovalSignalProvider);
      expect(signal?.channelId, 'ch-1');
      expect(signal?.reason, ChannelRemovalReason.left);
      expect(signal?.initiatedHere, isTrue);
    });

    testWidgets('xoá nhóm: báo "Đã xoá nhóm" và về danh sách', (tester) async {
      repository = _FakeRepository();
      await pumpFlow(tester);

      await tester.tap(find.text('bấm xoá'));
      await tester.pumpAndSettle();
      expect(find.text('Xoá nhóm cho mọi thành viên?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(repository.calls, ['delete ws/ch-1']);
      expect(find.text('Danh sách Tin nhắn'), findsOneWidget);
      expect(find.text('Đã xoá nhóm'), findsOneWidget);
    });

    testWidgets('lỗi: báo trong hộp, ở lại phòng, thử lại được', (
      tester,
    ) async {
      repository = _FakeRepository()
        ..deleteResponse = Future.value(
          const FailureResult<void>(
            Failure(kind: FailureKind.forbidden, message: 'Forbidden'),
          ),
        );
      await pumpFlow(tester);

      await tester.tap(find.text('bấm xoá'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('channel-exit-error')), findsOneWidget);
      expect(find.text('Bạn không có quyền xoá nhóm này.'), findsOneWidget);
      expect(find.text('Danh sách Tin nhắn'), findsNothing);

      // Nút chính bấm lại được (không còn khoá).
      await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
      await tester.pumpAndSettle();
      expect(repository.calls, ['delete ws/ch-1', 'delete ws/ch-1']);

      await tester.tap(find.byKey(const Key('webtui_dialog_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Phòng chat'), findsOneWidget);
    });

    testWidgets('huỷ: không gọi máy chủ', (tester) async {
      repository = _FakeRepository();
      await pumpFlow(tester);

      await tester.tap(find.text('bấm rời'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('webtui_dialog_cancel')));
      await tester.pumpAndSettle();

      expect(repository.calls, isEmpty);
      expect(find.text('Phòng chat'), findsOneWidget);
    });
  });

  group('nhận tín hiệu nhóm không còn', () {
    testWidgets('màn đang mở nhóm bị xoá: về danh sách, báo "Nhóm đã bị xoá"', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/room',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Danh sách Tin nhắn')),
          ),
          GoRoute(
            path: '/room',
            builder: (_, _) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.listen<ChannelRemovalSignal?>(
                    channelRemovalSignalProvider,
                    (_, next) {
                      if (next == null) return;
                      closeForRemovedChannel(
                        context,
                        next,
                        workspaceId: 'ws',
                        channelId: 'ch-xoa',
                      );
                    },
                  );
                  return const Text('Phòng chat');
                },
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: WebTuiTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nhóm khác bị xoá: không đóng.
      container
          .read(channelRemovalSignalProvider.notifier)
          .state = const ChannelRemovalSignal(
        workspaceId: 'ws',
        channelId: 'nhom-khac',
        reason: ChannelRemovalReason.deleted,
        serial: 1,
      );
      await tester.pumpAndSettle();
      expect(find.text('Phòng chat'), findsOneWidget);

      container
          .read(channelRemovalSignalProvider.notifier)
          .state = const ChannelRemovalSignal(
        workspaceId: 'ws',
        channelId: 'ch-xoa',
        reason: ChannelRemovalReason.deleted,
        serial: 2,
      );
      await tester.pumpAndSettle();
      expect(find.text('Danh sách Tin nhắn'), findsOneWidget);
      expect(find.text('Nhóm đã bị xoá'), findsOneWidget);
    });
  });
}

final class _FakeRepository implements ChannelExitRepository {
  final calls = <String>[];
  Future<Result<ChannelLeaveResult>>? leaveResponse;
  Future<Result<void>>? deleteResponse;

  @override
  Future<Result<ChannelLeaveResult>> leave({
    required String workspaceId,
    required String channelId,
  }) {
    calls.add('leave $workspaceId/$channelId');
    return leaveResponse ??
        Future.value(
          const Success(ChannelLeaveResult(channelId: 'ch-1', archived: false)),
        );
  }

  @override
  Future<Result<void>> delete({
    required String workspaceId,
    required String channelId,
  }) {
    calls.add('delete $workspaceId/$channelId');
    return deleteResponse ?? Future.value(const Success<void>(null));
  }

  @override
  Future<void> forgetLocally({
    required String workspaceId,
    required String channelId,
  }) async {}
}
