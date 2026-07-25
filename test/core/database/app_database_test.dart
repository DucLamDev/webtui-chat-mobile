import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';

void main() {
  test('stores key value metadata in Drift foundation database', () async {
    final database = AppDatabase(createInMemoryDriftConnection());
    addTearDown(database.close);

    await database.putKeyValue(
      scope: 'workspace:w1',
      key: 'cursor',
      value: 'cursor-1',
    );

    expect(
      await database.readKeyValue(scope: 'workspace:w1', key: 'cursor'),
      'cursor-1',
    );
  });
}
