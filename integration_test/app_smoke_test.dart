import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webtui_chat/app/app.dart';
import 'package:webtui_chat/app/flavor/app_config.dart';
import 'package:webtui_chat/app/flavor/app_flavor.dart';
import 'package:webtui_chat/app/providers/foundation_providers.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mở app lần đầu: hiện màn kết nối máy chủ', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Kho bí mật trong bộ nhớ: chạy được không cần plugin / thiết bị thật.
          secureKeyValueStoreProvider.overrideWithValue(_MemorySecureStore()),
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

    // Chưa chọn máy chủ: màn đầu tiên là "Kết nối tới máy chủ".
    expect(find.text('Kết nối tới máy chủ'), findsOneWidget);
    expect(find.text('Địa chỉ máy chủ'), findsOneWidget);
    expect(find.text('Kết nối'), findsOneWidget);
  });
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final _values = <SecureStoreKey, String>{};

  @override
  Future<String?> read(SecureStoreKey key) async => _values[key];

  @override
  Future<void> write(SecureStoreKey key, String value) async =>
      _values[key] = value;

  @override
  Future<void> delete(SecureStoreKey key) async => _values.remove(key);

  @override
  Future<void> clearSession() async => _values.clear();
}
