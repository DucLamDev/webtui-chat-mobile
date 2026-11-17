import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/chat_room_controller.dart';

void main() {
  test('đã biết mình là ai: không đọc token, không tải hồ sơ', () async {
    var tokenReads = 0;
    var profileLoads = 0;
    final id = await resolveChatRoomUserId(
      known: 'user-1',
      fromToken: () async {
        tokenReads++;
        return 'user-1';
      },
      fromProfile: () async {
        profileLoads++;
        return 'user-1';
      },
    );
    expect(id, 'user-1');
    expect(tokenReads, 0);
    expect(profileLoads, 0);
  });

  test('chưa biết: lấy từ token, không gọi /users/me', () async {
    var profileLoads = 0;
    final id = await resolveChatRoomUserId(
      known: null,
      fromToken: () async => ' user-2 ',
      fromProfile: () async {
        profileLoads++;
        return 'other';
      },
    );
    expect(id, 'user-2');
    expect(profileLoads, 0);
  });

  test('token không đọc được / rỗng: mới tải hồ sơ', () async {
    expect(
      await resolveChatRoomUserId(
        known: null,
        fromToken: () async => throw StateError('kho token lỗi'),
        fromProfile: () async => 'from-profile',
      ),
      'from-profile',
    );
    expect(
      await resolveChatRoomUserId(
        known: '',
        fromToken: () async => null,
        fromProfile: () async => 'from-profile',
      ),
      'from-profile',
    );
    expect(
      await resolveChatRoomUserId(
        known: null,
        fromToken: null,
        fromProfile: () async => 'from-profile',
      ),
      'from-profile',
    );
  });
}
