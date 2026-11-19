import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/app/router/notification_locations.dart';
import 'package:webtui_chat/core/notifications/scoped_local_notification_service.dart';
import 'package:webtui_chat/features/notifications/domain/entities/mobile_notification.dart';

const _instance = '11111111-2222-4333-8444-555555555555';

String? _loc(String link) => locationForNotificationTarget(
  NotificationTarget.fromUri(link, fallbackWorkspaceId: 'w1'),
);

const _ai = '0123456789abcdef01234567';
const _job = 'j_AbCdEf0123456789';

void main() {
  test('liên kết IDE hợp lệ mở đúng màn', () {
    expect(_loc('webtui://ide/ai/$_ai'), '/ide/ai/$_ai');
    expect(_loc('webtui://ide/jobs/$_job'), '/ide/jobs/$_job');
    expect(_loc('webtui://ide/tasks'), '/ide/tasks');
    expect(_loc('webtui://ide/tasks/0a1b2c3d4e'), '/ide/tasks/0a1b2c3d4e');
    expect(_loc('webtui://ide/mergeq'), '/ide/mergeq');
    expect(_loc('webtui://ide/mergeq?pr=12'), '/ide/mergeq?pr=12');
    expect(
      _loc('webtui://ide/mergeq?pr=12&project=chat%20hub'),
      '/ide/mergeq?project=chat+hub&pr=12',
    );
    expect(
      _loc('webtui://ide/mergeq?pr=7&project=my%3Ablog'),
      '/ide/mergeq?project=my%3Ablog&pr=7',
    );
  });

  test('liên kết hàng chờ gộp sai dạng thì không mở', () {
    expect(_loc('webtui://ide/mergeq?pr=0'), isNull);
    expect(_loc('webtui://ide/mergeq?pr=-1'), isNull);
    expect(_loc('webtui://ide/mergeq?pr=1234567890'), isNull);
    expect(_loc('webtui://ide/mergeq?pr=1&project=a%0Ab'), isNull);
    expect(_loc('webtui://ide/mergeq?project=${'x' * 201}'), isNull);
    expect(_loc('webtui://ide/mergeq/5'), isNull);
  });

  test('mã việc IDE sai dạng thì không mở', () {
    expect(_loc('webtui://ide/tasks/t1'), isNull);
    expect(_loc('webtui://ide/tasks/0A1B2C3D4E'), isNull);
    expect(_loc('webtui://ide/tasks/0a1b2c3d4e5'), isNull);
    expect(_loc('webtui://ide/tasks/0a1b2c3d4e/x'), isNull);
    expect(_loc('webtui://ide/tasks/..%2F0a1b2c3d'), isNull);
  });

  test('đường lạ, mã xấu hoặc thiếu thì không mở gì', () {
    expect(_loc('webtui://ide/unknown/x'), isNull);
    expect(_loc('webtui://ide/ai/new'), isNull);
    expect(_loc('webtui://ide/ai/abc123'), isNull);
    expect(_loc('webtui://ide/ai/${_ai.toUpperCase()}'), isNull);
    expect(_loc('webtui://ide/jobs/j_9f'), isNull);
    expect(_loc('webtui://ide/jobs/${_job}x'), isNull);
    expect(_loc('webtui://ide/ai'), isNull);
    expect(_loc('webtui://ide/ai/'), isNull);
    expect(_loc('webtui://ide/ai/a/b'), isNull);
    expect(_loc('webtui://ide/ai/..%2Fx'), isNull);
    expect(_loc('webtui://ide/jobs/a b'), isNull);
    expect(_loc('webtui://ide'), isNull);
    expect(_loc('https://ide/ai/abc'), isNull);
  });

  test('thông báo đẩy mang deep_link IDE được định tuyến', () {
    final data = <String, Object?>{
      'instance_id': _instance,
      'workspace_id': 'w1',
      'tag': 'ide-ai-abc',
      'deep_link': 'webtui://ide/ai/$_ai',
    };
    final routing = scopedNotificationRoutingData(data);
    expect(routing, isNotNull);
    expect(routing!['event_id'], 'ide-ai-abc');
    expect(routing['deep_link'], 'webtui://ide/ai/$_ai');
  });

  test('deep_link IDE lạ bị bỏ, không tạo thông báo mở không được', () {
    expect(
      scopedNotificationRoutingData({
        'instance_id': _instance,
        'workspace_id': 'w1',
        'tag': 'x',
        'deep_link': 'webtui://ide/bay-ba',
      }),
      isNull,
    );
  });

  test('đang mở đúng /ide/ai/<mã> thì không nhắc lại', () {
    expect(isSameIdeLocation('/ide/ai/abc', '/ide/ai/abc'), isTrue);
    expect(isSameIdeLocation('/ide/ai/abc%20', '/ide/ai/abc%20'), isTrue);
    expect(isSameIdeLocation('/ide/ai/abc', '/ide/ai/xyz'), isFalse);
    expect(isSameIdeLocation('/ide', '/ide/ai/abc'), isFalse);
    expect(isSameIdeLocation('/ide/ai/abc', null), isFalse);
    expect(isSameIdeLocation('/conversations/1', '/conversations/1'), isFalse);
  });
}
