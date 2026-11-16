import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/meeting_calendar/domain/entities/calendar_meeting.dart';

void main() {
  Uri server() => Uri.parse('https://chat.vpsttt.com/api');

  test('link khách tương đối ghép với gốc máy chủ, link đầy đủ giữ nguyên', () {
    expect(
      absoluteGuestUrl('/join?token=abc', server),
      'https://chat.vpsttt.com/join?token=abc',
    );
    expect(
      absoluteGuestUrl('https://chat.vpsttt.com/join?token=abc', server),
      'https://chat.vpsttt.com/join?token=abc',
    );
    // Đường bắt đầu bằng // là sang tên miền khác: không ghép.
    expect(absoluteGuestUrl('//evil.example/x', server), '//evil.example/x');
    expect(absoluteGuestUrl('  ', server), '');
  });

  test('link đầy đủ / rỗng: không cần hỏi địa chỉ máy chủ', () {
    Uri boom() => throw StateError('không được gọi');
    expect(absoluteGuestUrl('', boom), '');
    expect(
      absoluteGuestUrl('https://a.example/j', boom),
      'https://a.example/j',
    );
  });
}
