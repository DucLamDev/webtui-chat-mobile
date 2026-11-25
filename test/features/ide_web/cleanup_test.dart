import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/result/result.dart';
import 'package:webtui_chat/core/security/instance_scope.dart';
import 'package:webtui_chat/core/security/secure_key_value_store.dart';
import 'package:webtui_chat/features/auth/application/use_cases/delete_account_use_case.dart';
import 'package:webtui_chat/features/auth/data/repositories/local_session_state_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/account_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/app_lock_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/auth_token_repository.dart';
import 'package:webtui_chat/features/auth/domain/repositories/session_state_repository.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_account_use_cases.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_device_keys.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_session_cleaner.dart';
import 'package:webtui_chat/features/ide_web/application/ide_web_use_cases.dart';
import 'package:webtui_chat/features/ide_web/data/ide_web_stores.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_device_key.dart';
import 'package:webtui_chat/features/ide_web/domain/ide_web_ports.dart';

import 'support/fakes.dart';

/// TC4: mọi lối kết thúc phiên dọn VPSTTT IDE.
void main() {
  late FakeDataCleaner data;
  late MemoryMarkerStore markers;
  late IdeWebSessionCleaner cleaner;
  setUp(() {
    data = FakeDataCleaner();
    markers = MemoryMarkerStore();
    cleaner = IdeWebSessionCleaner(
      data: data,
      markers: markers,
      timeout: const Duration(milliseconds: 50),
    );
  });

  test('chưa từng mở IDE: không chạm WebView', () async {
    await cleaner.clearAll();
    expect(data.calls, 0);
  });

  test('đóng màn trước rồi mới xoá', () async {
    await cleaner.prepareFor(testOwner);
    final order = <String>[];
    cleaner.registerOpenView(() async => order.add('đóng ${data.calls}'));
    await cleaner.clearAll();
    expect(order, ['đóng 0']);
    expect(data.calls, 1);
    expect(markers.value, isNull);
  });

  test('xoá hỏng: ghi cờ, lần mở sau phải xoá xong mới mở', () async {
    await cleaner.prepareFor(testOwner);
    data.error = StateError('native');
    await cleaner.clearAll();
    expect(markers.value!.needsClear, isTrue);
    expect(await cleaner.prepareFor(testOwner), isFalse);
    data.error = null;
    expect(await cleaner.prepareFor(testOwner), isTrue);
    expect(markers.value!.isUsedBy(testOwner), isTrue);
  });

  test('cùng người mở lại giữ dữ liệu, người khác phải xoá trước', () async {
    await cleaner.prepareFor(testOwner);
    await cleaner.prepareFor(testOwner);
    expect(data.calls, 0);
    expect(await cleaner.prepareFor(otherOwner), isTrue);
    expect(data.calls, 1);
  });

  test('màn treo / lỗi khi đóng vẫn xoá dữ liệu', () async {
    await cleaner.prepareFor(testOwner);
    cleaner
      ..registerOpenView(() => Completer<void>().future)
      ..registerOpenView(() async => throw StateError('x'));
    await cleaner.clearAll();
    expect(data.calls, 1);
  });

  test('dấu bền đọc lại đúng, giá trị lạ coi như phải xoá', () async {
    final secure = MemorySecureStore();
    final store = SecureIdeWebDataMarkerStore(secure);
    await store.write(IdeWebDataMarker.usedBy(testOwner.digest));
    expect((await store.read())!.isUsedBy(testOwner), isTrue);
    expect('${secure.values}', isNot(contains('user-1')));
    await store.write(const IdeWebDataMarker.needsClear());
    expect((await store.read())!.needsClear, isTrue);
    secure.values[SecureStoreKey.ideWebViewData] = 'la';
    expect((await store.read())!.needsClear, isTrue);
    await secure.clearSession();
    expect(await store.read(), isNotNull);
  });

  test('người khác đăng nhập: xoá khoá và dữ liệu; cùng người: giữ', () async {
    final chip = FakeKeyChip();
    final keys = IdeWebDeviceKeys(chip: chip, store: MemoryKeyStore());
    await keys.create(
      owner: testOwner,
      purpose: IdeWebKeyPurpose.possession,
      origin: testOrigin,
      challenge: testChallenge,
      stillWanted: () => true,
    );
    await cleaner.prepareFor(testOwner);
    var user = 'user-1';
    final drop = DropOtherIdeWebOwnerUseCase(
      sessions: IdeWebSessionReader(
        tokens: FakeTokenRepository(),
        currentUserId: () async => user,
      ),
      keys: keys,
      cleaner: cleaner,
    );
    await drop.execute();
    expect(chip.keys, hasLength(1));
    expect(data.calls, 0);
    user = 'user-2';
    await drop.execute();
    expect(chip.keys, isEmpty);
    expect(data.calls, 1);
  });

  test(
    'xoá tài khoản: xoá khoá thiết bị, lỗi xoá khoá không cản dọn phiên',
    () async {
      for (final fail in [false, true]) {
        final tokens = FakeTokenRepository();
        var purged = 0;
        final sessions = _Sessions();
        final result = await DeleteAccountUseCase(
          accountRepository: _Accounts(),
          tokenRepository: tokens,
          sessionStateRepository: sessions,
          appLockRepository: _Lock(),
          purgeDeviceKeys: () async {
            purged++;
            if (fail) throw StateError('chip');
          },
        ).execute(reauthToken: 'r');
        expect(result.isSuccess, isTrue);
        expect(purged, 1);
        expect(sessions.resets, 1);
      }
    },
  );

  group('LocalSessionStateRepository', () {
    final instance = InstanceScope(
      instanceId: '11111111-1111-4111-8111-111111111111',
      serverOrigin: Uri.parse('https://chat.example.com'),
    );
    late AppDatabase database;
    late MemorySecureStore store;
    var cleared = 0;
    setUp(() {
      cleared = 0;
      database = AppDatabase(createInMemoryDriftConnection());
      store = MemorySecureStore()
        ..values.addAll({
          SecureStoreKey.activeInstanceScopeId: instance.storageId,
          SecureStoreKey.activeInstanceGeneration: 'g',
          SecureStoreKey.ideWebPending: 'x',
          SecureStoreKey.ideWebDevice: 'giữ',
        });
    });
    tearDown(() => database.close());
    LocalSessionStateRepository repository({bool fail = false}) =>
        LocalSessionStateRepository(
          secureStore: store,
          database: database,
          loadInstanceScope: () => instance,
          clearNativeInstanceBinding: () async {},
          clearIdeWebData: () async {
            cleared++;
            if (fail) throw StateError('webview');
          },
        );
    final guard = AuthTokenMutationGuard(
      instanceScopeId: instance.storageId,
      generation: 'g',
    );

    test(
      'đổi máy chủ, đăng xuất, thu hồi đều dọn; khoá thiết bị giữ',
      () async {
        await repository().resetForServerSwitch();
        await repository().resetForLogout();
        expect(await repository().resetForLogoutIfCurrent(guard), isTrue);
        expect(cleared, 3);
        expect(store.values[SecureStoreKey.ideWebPending], isNull);
        expect(store.values[SecureStoreKey.ideWebDevice], 'giữ');
      },
    );

    test('lỗi dọn không cản đăng xuất; phiên mới không bị dọn', () async {
      expect(
        await repository(fail: true).resetForLogoutIfCurrent(guard),
        isTrue,
      );
      store.values[SecureStoreKey.activeInstanceGeneration] = 'moi';
      cleared = 0;
      expect(await repository().resetForLogoutIfCurrent(guard), isFalse);
      expect(cleared, 0);
    });
  });
}

final class _Accounts implements AccountRepository {
  @override
  Future<Result<void>> deleteAccount({
    required String confirmation,
    required String reauthToken,
    String? ownershipSuccessorEmail,
  }) async => const Success(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Sessions implements SessionStateRepository {
  int resets = 0;

  @override
  Future<bool> resetForLogoutIfCurrent(AuthTokenMutationGuard guard) async {
    resets++;
    return true;
  }

  @override
  Future<bool> hasAnySavedSession() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Lock implements AppLockRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
