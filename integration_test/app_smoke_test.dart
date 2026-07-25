import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webtui_chat/app/app.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens the mobile app login entrypoint', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(
              flavor: AppFlavor.dev,
              apiBaseUri: Uri.parse('http://localhost:8080'),
              wsBaseUri: Uri.parse('ws://localhost:8080/ws'),
            ),
          ),
        ],
        child: const WebTuiChatApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ChÃ o má»«ng trá»Ÿ láº¡i'), findsOneWidget);
    expect(find.text('ÄÄƒng nháº­p'), findsOneWidget);
  });
}
