import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/logging/redacting_logger.dart';

void main() {
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
