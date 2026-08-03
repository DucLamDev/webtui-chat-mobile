import 'dart:async';

import 'package:flutter/services.dart';

final class NativeDeepLinkService {
  NativeDeepLinkService() {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  static const _channel = MethodChannel('webtui/deeplink');
  final _controller = StreamController<Uri>.broadcast();

  Stream<Uri> get urls => _controller.stream;

  Future<Uri?> getInitialUri() async {
    try {
      final raw = await _channel.invokeMethod<String>('getInitialUrl');
      return _safeUri(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _controller.close();
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method != 'url') {
      return;
    }
    final uri = _safeUri(call.arguments as String?);
    if (uri != null && !_controller.isClosed) {
      _controller.add(uri);
    }
  }
}

Uri? _safeUri(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null || !uri.hasScheme) {
    return null;
  }
  return uri;
}
