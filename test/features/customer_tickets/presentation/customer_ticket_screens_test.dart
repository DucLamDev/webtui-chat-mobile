import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/network/self_hosted_server_discovery.dart';
import 'package:webtui_chat/design_system/theme/webtui_theme.dart';
import 'package:webtui_chat/features/customer_tickets/application/customer_ticket_access_policy.dart';
import 'package:webtui_chat/features/customer_tickets/domain/entities/customer_ticket.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/controllers/customer_ticket_access_provider.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/screens/customer_ticket_detail_screen.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/screens/customer_ticket_list_screen.dart';
import 'package:webtui_chat/features/customer_tickets/presentation/widgets/customer_ticket_inbox_entry.dart';

import '../support/customer_ticket_fakes.dart';

const _viewer = CustomerTicketAccess(
  serverSupported: true,
  permissionsLoaded: true,
  canView: true,
  canReply: false,
);

const _replier = CustomerTicketAccess(
  serverSupported: true,
  permissionsLoaded: true,
  canView: true,
  canReply: true,
);

/// Máy chủ tự host của khách (không phải máy chủ nội bộ).
SelfHostedServerDiscovery _externalServer() {
  return SelfHostedServerDiscovery(
    instanceId: '11111111-1111-4111-8111-111111111111',
    discoveryVersion: '1',
    domain: 'chat.company.example',
    name: 'Máy chủ thử',
    apiBaseUri: Uri.parse('https://chat.company.example'),
    wsBaseUri: Uri.parse('wss://chat.company.example/ws'),
    registrationMode: 'closed',
    appVersion: '1.0.0',
    apiContractVersion: 1,
    serverVersion: '1.0.0',
    minimumSupportedMobileVersion: '1.0.0',
    capabilities: const SelfHostedCapabilities(),
    zoneKind: 'dedicated',
  );
}

Future<void> _pumpTicketApp(
  WidgetTester tester, {
  required String location,
  required FakeCustomerTicketRepository repository,
  CustomerTicketAccess? access = _replier,
  FakeCustomerTicketRealtimeRepository? realtime,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/customer-tickets',
        builder: (context, state) => CustomerTicketListScreen(
          workspaceId: state.uri.queryParameters['workspaceId'],
        ),
      ),
      GoRoute(
        path: '/customer-tickets/:ticket_id',
        builder: (context, state) => CustomerTicketDetailScreen(
          ticketId: state.pathParameters['ticket_id'] ?? '',
          workspaceId: state.uri.queryParameters['workspaceId'],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (access != null)
          customerTicketAccessProvider.overrideWithValue(access)
        else
          activeServerDiscoveryProvider.overrideWithValue(_externalServer()),
        customerTicketRepositoryProvider.overrideWithValue(repository),
        customerTicketRealtimeRepositoryProvider.overrideWithValue(
          realtime ?? FakeCustomerTicketRealtimeRepository(),
        ),
        customerTicketImagePickerRepositoryProvider.overrideWithValue(
          FakeCustomerTicketImagePicker(),
        ),
        customerTicketImageRepositoryProvider.overrideWithValue(
          FakeCustomerTicketImageRepository(),
        ),
        profileRepositoryProvider.overrideWithValue(
          const FakeProfileRepository('user-me'),
        ),
        customerTicketClockProvider.overrideWithValue(() => sampleNow),
      ],
      child: MaterialApp.router(
        theme: WebTuiTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('danh sách hiện đủ nhãn của từng ticket', (tester) async {
    final repository = FakeCustomerTicketRepository(
      pages: [
        samplePage([
          sampleSummary(
            newMessageCount: 2,
            assignee: const CustomerTicketAssignee(
              userId: 'user-me',
              name: 'Tôi',
            ),
            hasAiDraft: true,
          ),
          sampleSummary(
            ticketId: '1002',
            customerName: 'Khách Hai',
            waiting: const Duration(hours: 3),
            lastSender: CustomerTicketSender.staff,
            lastStaffName: 'Lan',
            preview: 'Bên em đang kiểm tra',
            assignee: const CustomerTicketAssignee(
              userId: 'user-lan',
              name: 'Lan',
            ),
          ),
          sampleSummary(
            ticketId: '1003',
            customerName: '',
            status: CustomerTicketStatus.answered,
            waiting: const Duration(minutes: 5),
          ),
        ]),
      ],
    );

    await _pumpTicketApp(
      tester,
      location: '/customer-tickets?workspaceId=ws-1',
      repository: repository,
    );

    expect(repository.listCalls.single.workspaceId, 'ws-1');
    expect(find.text('Chưa trả lời 3'), findsOneWidget);
    expect(find.text('#1001 · Khách Thử Nghiệm'), findsOneWidget);
    expect(find.text('Chờ 45 phút'), findsOneWidget);
    expect(find.text('Chờ 3 giờ'), findsOneWidget);
    expect(find.text('2 tin mới'), findsOneWidget);
    expect(find.text('Bạn đang xử lý'), findsOneWidget);
    expect(find.text('Lan đang xử lý'), findsOneWidget);
    expect(find.text('Có nháp AI'), findsOneWidget);
    expect(find.text('Đã trả lời'), findsWidgets);
    expect(find.text('#1003 · khach1003@example.test'), findsOneWidget);
    expect(find.textContaining('Lan: '), findsOneWidget);
    // 09:15 giờ Việt Nam (máy test có thể ở múi giờ khác).
    expect(find.text('09:15'), findsOneWidget);

    await tester.tap(find.text('Đã trả lời').first);
    await tester.pumpAndSettle();
    expect(repository.listCalls.last.filter, CustomerTicketFilter.answered);
  });

  testWidgets('danh sách: không có quyền thì không gọi máy chủ', (
    tester,
  ) async {
    final repository = FakeCustomerTicketRepository();
    await _pumpTicketApp(
      tester,
      location: '/customer-tickets?workspaceId=ws-1',
      repository: repository,
      access: const CustomerTicketAccess(
        serverSupported: true,
        permissionsLoaded: true,
        canView: false,
        canReply: false,
      ),
    );
    expect(find.byKey(const Key('customer_ticket_no_access')), findsOneWidget);
    expect(repository.listCalls, isEmpty);
  });

  testWidgets('máy chủ không phải nội bộ: vào thẳng URL báo không có quyền', (
    tester,
  ) async {
    final repository = FakeCustomerTicketRepository();
    // Không ghi đè quyền: provider thật thấy không có discovery nội bộ.
    await _pumpTicketApp(
      tester,
      location: '/customer-tickets/1001?workspaceId=ws-1',
      repository: repository,
      access: null,
    );
    expect(find.byKey(const Key('customer_ticket_no_access')), findsOneWidget);
    expect(repository.detailCalls, 0);
  });

  testWidgets('chi tiết: gửi trả lời, người khác giữ thì hỏi rồi gửi force', (
    tester,
  ) async {
    final repository = FakeCustomerTicketRepository(
      detail: sampleDetail(
        assignee: const CustomerTicketAssignee(userId: 'user-lan', name: 'Lan'),
        aiDraft: const CustomerTicketAiDraft(
          text: 'Chào anh, bên em đã kiểm tra máy chủ.',
          confidence: 0.82,
          category: 'ky_thuat',
          needsHuman: true,
        ),
      ),
    )..replyFailures.add(claimedFailure('Lan'));

    await _pumpTicketApp(
      tester,
      location: '/customer-tickets/1001?workspaceId=ws-1',
      repository: repository,
    );

    expect(find.text('#1001'), findsOneWidget);
    expect(find.text('Trợ lý ảo'), findsOneWidget);
    expect(find.text('Tự tin 82%'), findsOneWidget);
    expect(find.text('Kỹ thuật'), findsOneWidget);
    expect(find.text('Lan đang xử lý ticket này.'), findsOneWidget);
    expect(find.byKey(const Key('customer_ticket_read_only')), findsNothing);

    await tester.tap(find.text('Dùng câu này'));
    await tester.pump();
    final composer = tester.widget<TextField>(
      find.byKey(const Key('customer_ticket_composer')),
    );
    expect(composer.controller?.text, 'Chào anh, bên em đã kiểm tra máy chủ.');

    await tester.enterText(
      find.byKey(const Key('customer_ticket_composer')),
      'Bên em đã khởi động lại máy chủ.',
    );
    await tester.tap(find.byKey(const Key('customer_ticket_send')));
    await tester.pumpAndSettle();

    expect(find.text('Lan đang xử lý ticket này. Vẫn gửi?'), findsOneWidget);
    await tester.tap(find.text('Vẫn gửi'));
    await tester.pumpAndSettle();

    expect(repository.replyCalls, hasLength(2));
    expect(repository.replyCalls.first.force, isFalse);
    expect(repository.replyCalls.last.force, isTrue);
    expect(
      repository.replyCalls.last.message,
      'Bên em đã khởi động lại máy chủ.',
    );
    expect(find.text('Đã gửi trả lời cho khách.'), findsOneWidget);
    final cleared = tester.widget<TextField>(
      find.byKey(const Key('customer_ticket_composer')),
    );
    expect(cleared.controller?.text, isEmpty);
  });

  testWidgets('chi tiết: không có order.ticket_reply thì chỉ xem', (
    tester,
  ) async {
    final repository = FakeCustomerTicketRepository();
    await _pumpTicketApp(
      tester,
      location: '/customer-tickets/1001?workspaceId=ws-1',
      repository: repository,
      access: _viewer,
    );

    expect(find.text('Máy chủ không vào được'), findsOneWidget);
    expect(find.byKey(const Key('customer_ticket_composer')), findsNothing);
    expect(find.byKey(const Key('customer_ticket_ai_card')), findsNothing);
    expect(find.byKey(const Key('customer_ticket_read_only')), findsOneWidget);
    expect(find.textContaining('Chỉ xem'), findsOneWidget);

    await tester.tap(find.byKey(const Key('customer_ticket_menu')));
    await tester.pumpAndSettle();
    expect(find.text('Nhận xử lý'), findsNothing);
    expect(find.text('Đã xử lý'), findsNothing);
    expect(find.text('Thông tin khách'), findsOneWidget);
    await tester.tap(find.text('Thông tin khách'));
    await tester.pumpAndSettle();
    expect(find.text('#501'), findsOneWidget);
    expect(find.text('1.250.000 đ'), findsOneWidget);
    expect(find.textContaining('Tự gia hạn'), findsOneWidget);
  });

  testWidgets('chi tiết: menu nhận xử lý và đánh dấu đã xử lý', (tester) async {
    final repository = FakeCustomerTicketRepository();
    await _pumpTicketApp(
      tester,
      location: '/customer-tickets/1001?workspaceId=ws-1',
      repository: repository,
    );

    await tester.tap(find.byKey(const Key('customer_ticket_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhận xử lý'));
    await tester.pumpAndSettle();
    expect(repository.claimCalls.single.release, isFalse);

    await tester.tap(find.byKey(const Key('customer_ticket_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đã xử lý'));
    await tester.pumpAndSettle();
    expect(repository.statusCalls.single, CustomerTicketStatus.answered);
  });

  group('lối vào ở tab Nghiệp vụ', () {
    Future<void> pumpEntry(
      WidgetTester tester, {
      required FakeCustomerTicketRepository repository,
      CustomerTicketAccess? access,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            if (access != null)
              customerTicketAccessProvider.overrideWithValue(access)
            else
              activeServerDiscoveryProvider.overrideWithValue(
                _externalServer(),
              ),
            customerTicketRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: WebTuiTheme.light(),
            home: const Scaffold(
              body: CustomerTicketInboxEntry(workspaceId: 'ws-1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('đủ quyền: hiện ô kèm số ticket chưa trả lời', (tester) async {
      final repository = FakeCustomerTicketRepository(
        pages: [
          samplePage(
            [sampleSummary()],
            total: 5,
            counts: const CustomerTicketCounts(
              unanswered: 5,
              answered: 1,
              total: 6,
            ),
          ),
        ],
      );
      await pumpEntry(tester, repository: repository, access: _viewer);

      expect(find.byKey(const Key('customer_ticket_entry')), findsOneWidget);
      expect(find.text('Ticket khách'), findsOneWidget);
      expect(find.text('5 ticket chưa trả lời'), findsOneWidget);
      expect(repository.listCalls.single.perPage, 1);
      expect(
        repository.listCalls.single.filter,
        CustomerTicketFilter.unanswered,
      );
    });

    testWidgets('thiếu quyền order.view: không hiện, không gọi máy chủ', (
      tester,
    ) async {
      final repository = FakeCustomerTicketRepository();
      await pumpEntry(
        tester,
        repository: repository,
        access: const CustomerTicketAccess(
          serverSupported: true,
          permissionsLoaded: true,
          canView: false,
          canReply: false,
        ),
      );
      expect(find.byKey(const Key('customer_ticket_entry')), findsNothing);
      expect(repository.listCalls, isEmpty);
    });

    testWidgets('máy chủ không phải nội bộ: không hiện', (tester) async {
      final repository = FakeCustomerTicketRepository();
      // Provider quyền thật: không có discovery nội bộ.
      await pumpEntry(tester, repository: repository);
      expect(find.byKey(const Key('customer_ticket_entry')), findsNothing);
      expect(repository.listCalls, isEmpty);
    });
  });
}
