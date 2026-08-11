import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';
import 'package:webtui_chat/app/router/app_router.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/features/auth/application/legal_acceptance_access_policy.dart';
import 'package:webtui_chat/features/auth/domain/entities/legal_acceptance.dart';
import 'package:webtui_chat/features/auth/presentation/controllers/legal_acceptance_controller.dart';
import 'package:webtui_chat/features/auth/presentation/widgets/legal_acceptance_gate.dart';

void main() {
  testWidgets('requires an explicit checkbox before submitting acceptance', (
    tester,
  ) async {
    final policy = LegalAcceptanceAccessPolicy();
    var submissions = 0;
    final controller = _controller(
      policy: policy,
      load: ({required workspaceId}) async =>
          Success(_acceptance(complete: false, workspaceId: workspaceId)),
      submit:
          ({
            required workspaceId,
            required termsVersion,
            required privacyVersion,
          }) async {
            submissions++;
            expect(workspaceId, 'workspace-1');
            expect(termsVersion, '2026-08-07');
            expect(privacyVersion, '2026-08-07');
            return Success(
              _acceptance(complete: true, workspaceId: workspaceId),
            );
          },
    );
    final router = _router();
    final harnessKey = GlobalKey<_GateHarnessState>();
    addTearDown(router.dispose);
    addTearDown(policy.dispose);

    await tester.pumpWidget(
      _scope(
        controller: controller,
        router: router,
        child: _GateHarness(key: harnessKey, router: router),
      ),
    );
    await tester.pumpAndSettle();

    final acceptButton = tester.widget<FilledButton>(
      find.byKey(const Key('legal_gate_accept')),
    );
    expect(acceptButton.onPressed, isNull);
    expect(policy.canCreateUserContent, isFalse);

    await tester.tap(find.byKey(const Key('legal_gate_checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('legal_gate_accept')));
    await tester.pumpAndSettle();

    expect(submissions, 1);
    expect(controller.state.status, LegalAcceptanceStatus.complete);
    expect(policy.canCreateUserContent, isTrue);
    expect(find.byKey(const Key('legal_gate_checkbox')), findsNothing);

    harnessKey.currentState!.setAccessToken(null);
    await tester.pumpAndSettle();
    expect(controller.state.status, LegalAcceptanceStatus.idle);
    expect(policy.canCreateUserContent, isFalse);
  });

  testWidgets(
    'keeps safety navigation available and reloads on server or workspace switch',
    (tester) async {
      final policy = LegalAcceptanceAccessPolicy();
      final loadedWorkspaces = <String>[];
      final controller = _controller(
        policy: policy,
        load: ({required workspaceId}) async {
          loadedWorkspaces.add(workspaceId);
          return Success(
            _acceptance(complete: false, workspaceId: workspaceId),
          );
        },
      );
      final router = _router();
      final harnessKey = GlobalKey<_GateHarnessState>();
      addTearDown(router.dispose);
      addTearDown(policy.dispose);

      await tester.pumpWidget(
        _scope(
          controller: controller,
          router: router,
          child: _GateHarness(key: harnessKey, router: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(loadedWorkspaces, ['workspace-1']);

      final settingsButton = find.byKey(const Key('legal_gate_settings'));
      await tester.ensureVisible(settingsButton);
      await tester.tap(settingsButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_page')), findsOneWidget);
      expect(find.byKey(const Key('legal_gate_open')), findsOneWidget);

      harnessKey.currentState!.setServer(
        Uri.parse('https://SERVER-ONE.example:443'),
      );
      await tester.pumpAndSettle();
      expect(loadedWorkspaces, [
        'workspace-1',
      ], reason: 'Equivalent normalized origins share a scope.');

      harnessKey.currentState!.setServer(
        Uri.parse('https://server-two.example'),
      );
      await tester.pumpAndSettle();
      expect(loadedWorkspaces, ['workspace-1', 'workspace-1']);
      expect(find.byKey(const Key('legal_gate_account')), findsOneWidget);

      final accountButton = find.byKey(const Key('legal_gate_account'));
      await tester.ensureVisible(accountButton);
      await tester.tap(accountButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy_page')), findsOneWidget);

      harnessKey.currentState!.setWorkspace('workspace-2');
      await tester.pumpAndSettle();
      expect(loadedWorkspaces, ['workspace-1', 'workspace-1', 'workspace-2']);
      expect(controller.state.gateVisible, isTrue);
      expect(policy.canCreateUserContent, isFalse);
    },
  );

  testWidgets('waits fail-closed until a selected workspace is available', (
    tester,
  ) async {
    final policy = LegalAcceptanceAccessPolicy();
    final loadedWorkspaces = <String>[];
    final controller = _controller(
      policy: policy,
      load: ({required workspaceId}) async {
        loadedWorkspaces.add(workspaceId);
        return Success(_acceptance(complete: false, workspaceId: workspaceId));
      },
    );
    final router = _router();
    final harnessKey = GlobalKey<_GateHarnessState>();
    addTearDown(router.dispose);
    addTearDown(policy.dispose);

    await tester.pumpWidget(
      _scope(
        controller: controller,
        router: router,
        child: _GateHarness(
          key: harnessKey,
          router: router,
          initialWorkspaceId: null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(loadedWorkspaces, isEmpty);
    expect(controller.state.status, LegalAcceptanceStatus.idle);
    expect(policy.canCreateUserContent, isFalse);
    expect(find.byKey(const Key('legal_gate_loading')), findsOneWidget);

    harnessKey.currentState!.setWorkspace('workspace-1');
    await tester.pumpAndSettle();
    expect(loadedWorkspaces, ['workspace-1']);
    expect(controller.state.status, LegalAcceptanceStatus.required);
  });
}

ProviderScope _scope({
  required LegalAcceptanceController controller,
  required GoRouter router,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(_config),
      appRouterProvider.overrideWithValue(router),
      legalAcceptanceControllerProvider.overrideWith((_) => controller),
    ],
    child: child,
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('Home', key: Key('home_page'))),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('Settings', key: Key('settings_page'))),
        ),
      ),
      GoRoute(
        path: '/privacy',
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('Privacy', key: Key('privacy_page'))),
        ),
      ),
    ],
  );
}

class _GateHarness extends StatefulWidget {
  const _GateHarness({
    required this.router,
    this.initialWorkspaceId = 'workspace-1',
    super.key,
  });

  final GoRouter router;
  final String? initialWorkspaceId;

  @override
  State<_GateHarness> createState() => _GateHarnessState();
}

class _GateHarnessState extends State<_GateHarness> {
  String? _accessToken = 'same-access-token';
  Uri _serverUri = Uri.parse('https://server-one.example/');
  late String? _workspaceId;

  @override
  void initState() {
    super.initState();
    _workspaceId = widget.initialWorkspaceId;
  }

  void setServer(Uri value) => setState(() => _serverUri = value);

  void setWorkspace(String? value) => setState(() => _workspaceId = value);

  void setAccessToken(String? value) => setState(() => _accessToken = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: widget.router,
      builder: (context, child) => LegalAcceptanceGate(
        accessToken: _accessToken,
        serverUri: _serverUri,
        workspaceId: _workspaceId,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

LegalAcceptanceController _controller({
  required LegalAcceptanceAccessPolicy policy,
  required LoadLegalAcceptance load,
  SubmitLegalAcceptance? submit,
}) {
  return LegalAcceptanceController(
    load: load,
    submit:
        submit ??
        ({
          required workspaceId,
          required termsVersion,
          required privacyVersion,
        }) async =>
            Success(_acceptance(complete: true, workspaceId: workspaceId)),
    accessPolicy: policy,
    expectedTermsVersion: '2026-08-07',
    expectedPrivacyVersion: '2026-08-07',
    legalLinksConfigured: true,
  );
}

LegalAcceptance _acceptance({
  required bool complete,
  required String workspaceId,
}) {
  final acceptedAt = complete ? DateTime.utc(2026, 8, 7, 8) : null;
  return LegalAcceptance(
    workspaceId: workspaceId,
    serverComplete: complete,
    terms: LegalDocumentAcceptance(
      version: '2026-08-07',
      accepted: complete,
      acceptedAt: acceptedAt,
    ),
    privacy: LegalDocumentAcceptance(
      version: '2026-08-07',
      accepted: complete,
      acceptedAt: acceptedAt,
    ),
  );
}

final _config = AppConfig(
  flavor: AppFlavor.prod,
  apiBaseUri: Uri.parse('https://server-one.example'),
  wsBaseUri: Uri.parse('wss://server-one.example/ws'),
  termsUrl: 'https://chat.vpsttt.com/terms',
  privacyPolicyUrl: 'https://chat.vpsttt.com/privacy',
  termsVersion: '2026-08-07',
  privacyPolicyVersion: '2026-08-07',
);
