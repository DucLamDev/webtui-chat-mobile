import 'package:flutter/services.dart';

import '../domain/ide_web_ports.dart';

/// Trình duyệt hệ thống qua kênh `webtui/ide_web_auth`.
final class MethodChannelIdeWebBrowser implements IdeWebBrowser {
  const MethodChannelIdeWebBrowser({
    MethodChannel channel = const MethodChannel('webtui/ide_web_auth'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<IdeWebBrowserResult> authenticate(
    Uri url, {
    required String scheme,
  }) async {
    if (url.scheme != 'https') return const IdeWebBrowserFailed();
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'authenticate',
        {'url': url.toString(), 'callbackScheme': scheme},
      );
      switch (value?['mode']) {
        case 'deeplink':
          return const IdeWebBrowserOpened();
        case 'cancelled':
          return const IdeWebBrowserCancelled();
        case 'result':
          final raw = value?['url'];
          final uri = raw is String ? Uri.tryParse(raw) : null;
          return uri == null
              ? const IdeWebBrowserFailed()
              : IdeWebBrowserCallback(uri);
        default:
          return const IdeWebBrowserFailed();
      }
    } on MissingPluginException {
      return const IdeWebBrowserFailed();
    } on PlatformException {
      return const IdeWebBrowserFailed();
    }
  }
}
