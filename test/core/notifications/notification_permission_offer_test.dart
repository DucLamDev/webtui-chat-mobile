import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/database/app_database.dart';
import 'package:webtui_chat/core/notifications/notification_permission_offer.dart';

void main() {
  final now = DateTime.utc(2026, 11, 15, 9);

  group('có nên mời bật thông báo', () {
    test('đã cho phép hoặc bản dựng không có push: không mời', () {
      for (final status in const ['granted', 'provisional', 'unavailable']) {
        expect(
          shouldOfferNotificationPermission(
            permissionStatus: status,
            lastAnswer: null,
            now: now,
          ),
          isFalse,
          reason: status,
        );
      }
    });

    test('chưa hỏi lần nào: mời, kể cả Android 13+ báo denied', () {
      for (final status in const ['unknown', 'denied']) {
        expect(
          shouldOfferNotificationPermission(
            permissionStatus: status,
            lastAnswer: null,
            now: now,
          ),
          isTrue,
          reason: status,
        );
      }
    });

    test('bấm "Để sau": 7 ngày sau mới mời lại', () {
      bool offerAfter(Duration elapsed) => shouldOfferNotificationPermission(
        permissionStatus: 'unknown',
        lastAnswer: NotificationOfferRecord(
          answer: NotificationOfferAnswer.later,
          at: now.subtract(elapsed),
        ),
        now: now,
      );

      expect(offerAfter(const Duration(days: 6, hours: 23)), isFalse);
      expect(offerAfter(notificationOfferRemindAfter), isTrue);
    });

    test('hệ điều hành đã từ chối sau lời mời: không mời nữa', () {
      expect(
        shouldOfferNotificationPermission(
          permissionStatus: 'denied',
          lastAnswer: NotificationOfferRecord(
            answer: NotificationOfferAnswer.denied,
            at: now.subtract(const Duration(days: 365)),
          ),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('một lượt mời', () {
    late List<NotificationOfferRecord> saved;
    late int asked;
    late int requested;

    setUp(() {
      saved = [];
      asked = 0;
      requested = 0;
    });

    Future<NotificationOfferOutcome> run({
      String status = 'unknown',
      NotificationOfferRecord? lastAnswer,
      bool? userAccepts = true,
      String permissionAfterRequest = 'granted',
    }) {
      return runNotificationPermissionOffer(
        readPermissionStatus: () async => status,
        readLastAnswer: () async => lastAnswer,
        saveAnswer: (record) async => saved.add(record),
        askUser: () async {
          asked++;
          return userAccepts;
        },
        requestPermission: () async {
          requested++;
          return permissionAfterRequest;
        },
        now: () => now,
      );
    }

    test('đã cho phép: không hiện hộp mời, không ghi gì', () async {
      expect(await run(status: 'granted'), NotificationOfferOutcome.skipped);
      expect(asked, 0);
      expect(requested, 0);
      expect(saved, isEmpty);
    });

    test('bấm "Để sau": không hỏi hệ điều hành, ghi lại lúc bấm', () async {
      expect(await run(userAccepts: false), NotificationOfferOutcome.later);
      expect(requested, 0);
      expect(saved.single.answer, NotificationOfferAnswer.later);
      expect(saved.single.at, now);
    });

    test('bấm "Cho phép" và được cho phép: đăng ký, không ghi gì', () async {
      expect(await run(), NotificationOfferOutcome.granted);
      expect(asked, 1);
      expect(requested, 1);
      expect(saved, isEmpty);
    });

    test('hệ điều hành từ chối: ghi denied để không mời nữa', () async {
      expect(
        await run(permissionAfterRequest: 'denied'),
        NotificationOfferOutcome.denied,
      );
      expect(saved.single.answer, NotificationOfferAnswer.denied);
    });

    test('không đọc được kết quả: coi như "Để sau"', () async {
      expect(
        await run(permissionAfterRequest: 'unknown'),
        NotificationOfferOutcome.unknown,
      );
      expect(saved.single.answer, NotificationOfferAnswer.later);
    });

    test('màn hình đã đóng nên không hiện được hộp: bỏ qua lượt này', () async {
      expect(await run(userAccepts: null), NotificationOfferOutcome.skipped);
      expect(requested, 0);
      expect(saved, isEmpty);
    });

    test('vừa bấm "Để sau" hôm qua: không hiện hộp', () async {
      final outcome = await run(
        lastAnswer: NotificationOfferRecord(
          answer: NotificationOfferAnswer.later,
          at: now.subtract(const Duration(days: 1)),
        ),
      );
      expect(outcome, NotificationOfferOutcome.skipped);
      expect(asked, 0);
    });
  });

  group('lưu câu trả lời', () {
    test('ghi rồi đọc lại đúng câu trả lời và thời điểm', () async {
      final database = AppDatabase(createInMemoryDriftConnection());
      addTearDown(database.close);
      final store = NotificationOfferStore(database);

      expect(await store.read(), isNull);
      await store.save(
        NotificationOfferRecord(answer: NotificationOfferAnswer.later, at: now),
      );
      final record = await store.read();
      expect(record?.answer, NotificationOfferAnswer.later);
      expect(record?.at.isAtSameMomentAs(now), isTrue);

      await store.save(
        NotificationOfferRecord(
          answer: NotificationOfferAnswer.denied,
          at: now,
        ),
      );
      expect((await store.read())?.answer, NotificationOfferAnswer.denied);
    });

    test('dữ liệu hỏng: coi như chưa trả lời', () async {
      final database = AppDatabase(createInMemoryDriftConnection());
      addTearDown(database.close);
      for (final raw in const ['không phải json', '[]', '{"answer":"x"}']) {
        await database.putKeyValue(
          scope: 'notification_offer',
          key: 'last_answer',
          value: raw,
        );
        expect(await NotificationOfferStore(database).read(), isNull);
      }
    });
  });
}
