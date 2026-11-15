import 'dart:convert';

import '../database/app_database.dart';

/// Mời bật thông báo sau khi vào app.
///
/// App chỉ lấy mã nhận thông báo đẩy (FCM, VoIP) khi hệ điều hành đã cho phép
/// thông báo. Nếu người dùng chưa từng vào Cài đặt bấm "Cho phép", máy chủ
/// không có cách nào đánh thức app khi app đang tắt, nên cuộc gọi đến không đổ
/// chuông. Hộp mời này nhắc người dùng bật. Hộp hỏi quyền của hệ điều hành vẫn
/// chỉ hiện khi người dùng bấm "Cho phép".

/// Bấm "Để sau" thì sau khoảng này mới mời lại.
const notificationOfferRemindAfter = Duration(days: 7);

/// Câu trả lời gần nhất của người dùng cho lời mời bật thông báo.
enum NotificationOfferAnswer {
  /// Bấm "Để sau", bấm ra ngoài hoặc nút Back.
  later,

  /// Bấm "Cho phép" nhưng hệ điều hành báo bị từ chối: không mời nữa,
  /// người dùng tự bật trong cài đặt điện thoại.
  denied,
}

final class NotificationOfferRecord {
  const NotificationOfferRecord({required this.answer, required this.at});

  final NotificationOfferAnswer answer;
  final DateTime at;
}

/// Kết quả một lượt mời, để màn hình báo lại cho người dùng.
enum NotificationOfferOutcome {
  /// Không mời (đã cho phép, bản dựng không có push, vừa bấm "Để sau"...).
  skipped,
  later,
  granted,
  denied,

  /// Đã hỏi nhưng không đọc được kết quả (lỗi Firebase...).
  unknown,
}

/// Có nên mời không. [permissionStatus] là trạng thái từ
/// `PushNotificationService.permissionStatusForOffer` (`granted`,
/// `provisional`, `denied`, `unknown`, `unavailable`).
///
/// Android 13 trở lên báo `denied` cả khi chưa từng hỏi, nên `denied` vẫn được
/// mời một lần; chỉ thôi mời khi chính lời mời này đã nhận `denied`.
bool shouldOfferNotificationPermission({
  required String permissionStatus,
  required NotificationOfferRecord? lastAnswer,
  required DateTime now,
}) {
  switch (permissionStatus) {
    case 'granted' || 'provisional' || 'unavailable':
      return false;
  }
  final last = lastAnswer;
  if (last == null) return true;
  return switch (last.answer) {
    NotificationOfferAnswer.denied => false,
    NotificationOfferAnswer.later =>
      now.difference(last.at) >= notificationOfferRemindAfter,
  };
}

/// Chạy một lượt mời.
///
/// [askUser] hiện hộp mời: `true` là bấm "Cho phép", `false` là "Để sau"
/// (hoặc đóng hộp), `null` là không hiện được (màn hình đã đóng): bỏ qua lượt
/// này, không ghi gì. [requestPermission] mới bật hộp hỏi quyền của hệ điều
/// hành và đăng ký lại thiết bị với máy chủ.
Future<NotificationOfferOutcome> runNotificationPermissionOffer({
  required Future<String> Function() readPermissionStatus,
  required Future<NotificationOfferRecord?> Function() readLastAnswer,
  required Future<void> Function(NotificationOfferRecord record) saveAnswer,
  required Future<bool?> Function() askUser,
  required Future<String> Function() requestPermission,
  required DateTime Function() now,
}) async {
  final status = await readPermissionStatus();
  if (status == 'granted' ||
      status == 'provisional' ||
      status == 'unavailable') {
    return NotificationOfferOutcome.skipped;
  }
  final last = await readLastAnswer();
  if (!shouldOfferNotificationPermission(
    permissionStatus: status,
    lastAnswer: last,
    now: now(),
  )) {
    return NotificationOfferOutcome.skipped;
  }
  final accepted = await askUser();
  if (accepted == null) return NotificationOfferOutcome.skipped;
  if (!accepted) {
    await saveAnswer(
      NotificationOfferRecord(answer: NotificationOfferAnswer.later, at: now()),
    );
    return NotificationOfferOutcome.later;
  }
  final permission = await requestPermission();
  switch (permission) {
    case 'granted' || 'provisional':
      return NotificationOfferOutcome.granted;
    case 'denied':
      await saveAnswer(
        NotificationOfferRecord(
          answer: NotificationOfferAnswer.denied,
          at: now(),
        ),
      );
      return NotificationOfferOutcome.denied;
    default:
      await saveAnswer(
        NotificationOfferRecord(
          answer: NotificationOfferAnswer.later,
          at: now(),
        ),
      );
      return NotificationOfferOutcome.unknown;
  }
}

/// Lưu câu trả lời theo máy (quyền thông báo là của máy, không theo tài khoản).
final class NotificationOfferStore {
  const NotificationOfferStore(this._database);

  static const _scope = 'notification_offer';
  static const _key = 'last_answer';

  final AppDatabase _database;

  Future<NotificationOfferRecord?> read() async {
    final raw = await _database.readKeyValue(scope: _scope, key: _key);
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final answerName = decoded['answer'];
    final at = DateTime.tryParse(decoded['at']?.toString() ?? '');
    final answer = NotificationOfferAnswer.values
        .where((value) => value.name == answerName)
        .firstOrNull;
    if (answer == null || at == null) return null;
    return NotificationOfferRecord(answer: answer, at: at);
  }

  Future<void> save(NotificationOfferRecord record) {
    return _database.putKeyValue(
      scope: _scope,
      key: _key,
      value: jsonEncode({
        'answer': record.answer.name,
        'at': record.at.toUtc().toIso8601String(),
      }),
    );
  }
}
