import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/notifications/fcm_token_reader.dart';

void main() {
  group('readFcmTokenWhenReady', () {
    test('Android đọc mã FCM ngay, không chờ mã Apple', () async {
      var apnsReads = 0;
      final token = await readFcmTokenWhenReady(
        waitForApnsToken: false,
        readApnsToken: () async {
          apnsReads += 1;
          return null;
        },
        readFcmToken: () async => ' fcm-1 ',
      );
      expect(token, 'fcm-1');
      expect(apnsReads, 0);
    });

    test('iPhone xin mã Apple, chờ có mã rồi mới đọc mã FCM', () async {
      final calls = <String>[];
      var apnsReads = 0;
      final waits = <Duration>[];
      final token = await readFcmTokenWhenReady(
        waitForApnsToken: true,
        prepareApns: () async => calls.add('prepare'),
        readApnsToken: () async {
          apnsReads += 1;
          calls.add('apns');
          return apnsReads < 3 ? null : 'apns-token';
        },
        readFcmToken: () async {
          calls.add('fcm');
          return 'fcm-ios';
        },
        interval: const Duration(milliseconds: 250),
        sleep: (delay) async => waits.add(delay),
      );
      expect(token, 'fcm-ios');
      expect(calls, ['prepare', 'apns', 'apns', 'apns', 'fcm']);
      expect(waits, List.filled(2, const Duration(milliseconds: 250)));
    });

    test(
      'iPhone chưa có mã Apple sau đủ số lần thì trả null, không gọi FCM',
      () async {
        var fcmReads = 0;
        var apnsReads = 0;
        final token = await readFcmTokenWhenReady(
          waitForApnsToken: true,
          readApnsToken: () async {
            apnsReads += 1;
            return '  ';
          },
          readFcmToken: () async {
            fcmReads += 1;
            return 'fcm';
          },
          attempts: 4,
          sleep: (_) async {},
        );
        expect(token, isNull);
        expect(apnsReads, 4);
        expect(fcmReads, 0);
      },
    );

    test('lỗi khi xin hoặc đọc mã không làm hỏng việc đăng ký', () async {
      var apnsReads = 0;
      final token = await readFcmTokenWhenReady(
        waitForApnsToken: true,
        prepareApns: () async => throw StateError('no plugin'),
        readApnsToken: () async {
          apnsReads += 1;
          if (apnsReads == 1) throw StateError('apns-token-not-set');
          return 'apns';
        },
        readFcmToken: () async => throw StateError('fcm down'),
        sleep: (_) async {},
      );
      expect(token, isNull);
      expect(apnsReads, 2);
    });

    test('mã FCM rỗng coi như chưa có', () async {
      final token = await readFcmTokenWhenReady(
        waitForApnsToken: false,
        readApnsToken: () async => null,
        readFcmToken: () async => '   ',
      );
      expect(token, isNull);
    });
  });

  test('chỉ bỏ thông báo trên máy khi iPhone đã tự hiện phần hiển thị', () {
    expect(systemShowsRemoteAlert(isIOS: true, hasNotification: true), isTrue);
    expect(
      systemShowsRemoteAlert(isIOS: true, hasNotification: false),
      isFalse,
    );
    expect(
      systemShowsRemoteAlert(isIOS: false, hasNotification: true),
      isFalse,
    );
  });

  test('có nhịp thử lại tăng dần cho iPhone chưa có mã FCM', () {
    expect(fcmTokenRetryDelays, isNotEmpty);
    for (var i = 1; i < fcmTokenRetryDelays.length; i++) {
      expect(fcmTokenRetryDelays[i], greaterThan(fcmTokenRetryDelays[i - 1]));
    }
  });
}
