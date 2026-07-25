import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/app.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';

void main() {
  testWidgets('renders WebTui login entrypoint', (tester) async {
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

    expect(find.text('Chào mừng trở lại'), findsOneWidget);
    expect(find.text('Email hoặc username'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
  });
}
