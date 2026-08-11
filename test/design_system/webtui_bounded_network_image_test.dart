import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_avatar.dart';

void main() {
  testWidgets('brand image uses the bounded public loader', (tester) async {
    Uri? requestedUri;
    int? requestedMaxBytes;
    bool? requestedPublic;

    await tester.pumpWidget(
      MaterialApp(
        home: WebTuiAvatarNetworkScope(
          apiBaseUri: Uri.parse('https://chat.example'),
          cacheKey: 'scope-a',
          loadBytes:
              (uri, {required maxBytes, required allowPublicRequest}) async {
                requestedUri = uri;
                requestedMaxBytes = maxBytes;
                requestedPublic = allowPublicRequest;
                return Uint8List(0);
              },
          child: const WebTuiBoundedNetworkImage(
            imageUrl: '/branding/logo.png',
            width: 48,
            height: 48,
            allowPublicRequest: true,
            fallback: Text('fallback'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(requestedUri, Uri.parse('https://chat.example/branding/logo.png'));
    expect(requestedMaxBytes, webTuiMaxBrandImageBytes);
    expect(requestedPublic, isTrue);
    expect(find.text('fallback'), findsOneWidget);
  });

  testWidgets('avatar uses the lower authenticated image cap', (tester) async {
    int? requestedMaxBytes;
    bool? requestedPublic;

    await tester.pumpWidget(
      MaterialApp(
        home: WebTuiAvatarNetworkScope(
          apiBaseUri: Uri.parse('https://chat.example'),
          cacheKey: 'scope-a',
          loadBytes:
              (uri, {required maxBytes, required allowPublicRequest}) async {
                requestedMaxBytes = maxBytes;
                requestedPublic = allowPublicRequest;
                return null;
              },
          child: const WebTuiAvatar(
            label: 'Alice',
            imageUrl: '/avatars/alice.png',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(requestedMaxBytes, webTuiMaxAvatarImageBytes);
    expect(requestedPublic, isFalse);
  });

  testWidgets('credentialed or non-HTTPS image URL fails before loading', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: WebTuiAvatarNetworkScope(
          apiBaseUri: Uri.parse('https://chat.example'),
          loadBytes:
              (uri, {required maxBytes, required allowPublicRequest}) async {
                calls++;
                return null;
              },
          child: const WebTuiBoundedNetworkImage(
            imageUrl: 'https://user:secret@evil.example/logo.png',
            width: 48,
            height: 48,
            allowPublicRequest: true,
            fallback: Text('blocked'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(calls, 0);
    expect(find.text('blocked'), findsOneWidget);
  });
}
