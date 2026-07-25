import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/network/self_hosted_server_uri.dart';

void main() {
  test('normalizes a public self-hosted domain to HTTPS', () {
    expect(
      parseSelfHostedServerUri('chat.example.com'),
      Uri.parse('https://chat.example.com'),
    );
  });

  test('allows HTTP only for local development', () {
    expect(
      parseSelfHostedServerUri('http://localhost:8080'),
      Uri.parse('http://localhost:8080'),
    );
    expect(
      () => parseSelfHostedServerUri('http://chat.example.com'),
      throwsFormatException,
    );
  });

  test('rejects credentials, paths, queries, and fragments', () {
    for (final value in [
      'https://user:pass@chat.example.com',
      'https://chat.example.com/team',
      'https://chat.example.com?tenant=a',
      'https://chat.example.com#login',
    ]) {
      expect(() => parseSelfHostedServerUri(value), throwsFormatException);
    }
  });
}
