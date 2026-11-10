import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/logging/redacting_logger.dart';

void main() {
  test('che token lời mời trong path của log HTTP', () {
    final logs = <String>[];
    final logger = RedactingLogger(sink: logs.add);
    logger.debug('Yêu cầu', {
      'path': '/api/v1/invites/sensitive-invite/accept',
    });
    expect(logs.single, contains('/api/v1/invites/<redacted>/accept'));
    expect(logs.single, isNot(contains('sensitive-invite')));
  });

  test('redacts tokens from log messages and URLs', () {
    final logger = RedactingLogger(sink: (_) {});

    final redacted = logger.redact(
      'Authorization: Bearer abc token=secret '
      'https://api.test/messages?access_token=abc&workspace_id=1',
    );

    expect(redacted, isNot(contains('Bearer abc')));
    expect(redacted, isNot(contains(' abc ')));
    expect(redacted, isNot(contains('token=secret')));
    expect(redacted, isNot(contains('access_token=abc')));
    expect(redacted, contains('<redacted>'));
    expect(redacted, contains('workspace_id=1'));
  });
}
