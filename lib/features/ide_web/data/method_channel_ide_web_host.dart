import 'package:flutter/services.dart';

import '../application/ide_web_view.dart';
import '../domain/ide_web_ports.dart';

/// Lớp native quanh WebView thật: `webtui/ide_web_host` + `/events`.
final class MethodChannelIdeWebHost implements IdeWebDataCleaner {
  const MethodChannelIdeWebHost({
    MethodChannel channel = const MethodChannel('webtui/ide_web_host'),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// Một luồng cho cả app. Mỗi lần `receiveBroadcastStream` là một luồng riêng:
  /// màn cũ ngừng nghe muộn (đóng rồi mở lại nhanh) sẽ tắt luôn kênh của màn mới.
  static final Stream<Object?> _events = const EventChannel(
    'webtui/ide_web_host/events',
  ).receiveBroadcastStream();

  Future<bool> attach({
    required int webViewId,
    required String allowedOrigin,
    required bool bridgeEnabled,
  }) async {
    final value = await _channel.invokeMapMethod<String, Object?>('attach', {
      'webViewId': webViewId,
      'allowedOrigin': allowedOrigin,
      'bridgeEnabled': bridgeEnabled,
    });
    return value?['supported'] == true;
  }

  Future<void> detach(int webViewId) =>
      _channel.invokeMethod<void>('detach', {'webViewId': webViewId});

  Future<void> postReply({
    required int webViewId,
    required String replyId,
    required String payload,
  }) => _channel.invokeMethod<void>('postReply', {
    'webViewId': webViewId,
    'replyId': replyId,
    'payload': payload,
  });

  Future<void> emit({required int webViewId, required String payload}) =>
      _channel.invokeMethod<void>('emit', {
        'webViewId': webViewId,
        'payload': payload,
      });

  Future<bool> captureOpen() async {
    final value = await _channel.invokeMapMethod<String, Object?>(
      'captureState',
    );
    return value?['any'] == true || value?['active'] == true;
  }

  Future<void> stopCapture(int webViewId) =>
      _channel.invokeMethod<void>('stopCapture', {'webViewId': webViewId});

  @override
  Future<void> clearAll() => _channel.invokeMethod<void>('clearAllData');

  /// Sự kiện của đúng WebView [webViewId]; sự kiện lạ bị bỏ.
  Stream<IdeWebViewEvent> events(int webViewId) => _events
      .map((event) => parseIdeWebHostEvent(event, webViewId))
      .where((event) => event != null)
      .cast<IdeWebViewEvent>();
}

IdeWebViewEvent? parseIdeWebHostEvent(Object? event, int webViewId) {
  if (event is! Map) return null;
  switch (event['type']) {
    case 'message':
      final id = event['id'];
      final json = event['json'];
      final origin = event['origin'];
      if (event['webViewId'] != webViewId ||
          id is! String ||
          json is! String ||
          origin is! String) {
        return null;
      }
      return IdeWebBridgeMessage(
        replyId: id,
        json: json,
        isMainFrame: event['isMainFrame'] == true,
        origin: origin,
      );
    case 'capture':
      final active = event['active'] == true;
      return IdeWebCaptureChanged(
        active: active,
        any: active || event['any'] == true,
      );
    case 'render_gone':
      return const IdeWebRenderGone();
    default:
      return null;
  }
}
