import 'package:flutter/services.dart';

abstract interface class ExternalUrlLauncher {
  Future<bool> open(String url);
}

final class MethodChannelExternalUrlLauncher implements ExternalUrlLauncher {
  const MethodChannelExternalUrlLauncher();

  static const _channel = MethodChannel('webtui/launcher');

  @override
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('openUrl', {
            'url': uri.toString(),
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
