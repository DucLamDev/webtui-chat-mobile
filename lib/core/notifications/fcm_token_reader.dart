/// Các nhịp đăng ký lại khi iPhone có quyền thông báo mà chưa có mã FCM.
const fcmTokenRetryDelays = <Duration>[
  Duration(seconds: 10),
  Duration(seconds: 30),
  Duration(minutes: 2),
];

/// Tin đẩy đã có phần hiển thị (`aps.alert`) thì iPhone tự hiện, app không hiện
/// thêm thông báo trên máy nữa để khỏi bị hai thông báo cho cùng một tin.
bool systemShowsRemoteAlert({
  required bool isIOS,
  required bool hasNotification,
}) {
  return isIOS && hasNotification;
}

/// Đọc mã FCM của máy.
///
/// Trên iPhone, Firebase chỉ cấp mã FCM sau khi đã có mã APNs của Apple; gọi
/// `getToken()` sớm hơn sẽ lỗi `apns-token-not-set`. Vì vậy khi
/// [waitForApnsToken] bật, hàm này nhờ [prepareApns] xin mã Apple rồi chờ
/// [readApnsToken] trả mã (tối đa [attempts] lần, cách nhau [interval]) trước
/// khi đọc mã FCM. Mọi lỗi đều trả `null` để người gọi thử lại sau.
Future<String?> readFcmTokenWhenReady({
  required bool waitForApnsToken,
  required Future<String?> Function() readApnsToken,
  required Future<String?> Function() readFcmToken,
  Future<void> Function()? prepareApns,
  int attempts = 10,
  Duration interval = const Duration(milliseconds: 500),
  Future<void> Function(Duration delay)? sleep,
}) async {
  if (waitForApnsToken) {
    try {
      await prepareApns?.call();
    } on Object {
      // Vẫn thử đọc mã: bản dựng có thể đã xin mã Apple từ phía iOS.
    }
    final wait = sleep ?? (delay) => Future<void>.delayed(delay);
    var ready = false;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (_hasText(await _readSafely(readApnsToken))) {
        ready = true;
        break;
      }
      if (attempt < attempts - 1) {
        await wait(interval);
      }
    }
    if (!ready) return null;
  }
  final token = (await _readSafely(readFcmToken))?.trim();
  return _hasText(token) ? token : null;
}

Future<String?> _readSafely(Future<String?> Function() read) async {
  try {
    return await read();
  } on Object {
    return null;
  }
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
