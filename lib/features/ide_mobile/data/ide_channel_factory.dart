import 'dart:io';

import '../../auth/domain/repositories/auth_token_repository.dart';
import '../../conversations/data/repositories/web_socket_conversation_realtime_repository.dart'
    show connectWebSocketWithoutRedirects;
import '../domain/ide_device_credentials.dart';
import 'ide_channel.dart';
import 'ide_device_key_store.dart';

typedef IdeSocketOpener =
    Future<IdeSocket> Function(Uri uri, Map<String, String> headers);

Future<IdeSocket> _defaultOpenSocket(
  Uri uri,
  Map<String, String> headers,
) async {
  final WebSocket socket = await connectWebSocketWithoutRedirects(
    uri.toString(),
    headers: headers,
  );
  return WebSocketIdeSocket(socket);
}

/// Dựng một stream IDE: địa chỉ `…/api/v1/ide/ws` từ địa chỉ WS máy chủ đang
/// dùng, token chat qua header (không bao giờ trên URL), header `X-IDE-Device`,
/// không theo redirect, và bỏ kết nối nếu tài khoản / máy chủ đổi giữa chừng.
final class IdeChannelFactory {
  IdeChannelFactory({
    required this.wsBaseUri,
    required this.serverScopeId,
    required AuthTokenRepository tokens,
    required Future<IdeDeviceCredentials?> Function() loadCredentials,
    IdeSocketOpener? openSocket,
    this.handshakeTimeout = const Duration(seconds: 15),
    this.pingEvery = const Duration(seconds: 12),
    this.deadAfter = const Duration(seconds: 35),
  }) : _tokens = tokens,
       _loadCredentials = loadCredentials,
       _openSocket = openSocket ?? _defaultOpenSocket;

  final Uri wsBaseUri;
  final String serverScopeId;
  final AuthTokenRepository _tokens;
  final Future<IdeDeviceCredentials?> Function() _loadCredentials;
  final IdeSocketOpener _openSocket;
  final Duration handshakeTimeout;
  final Duration pingEvery;
  final Duration deadAfter;

  Uri get uri => wsBaseUri.replace(path: '/api/v1/ide/ws', query: '');

  /// Lý do ném [IdeHandshakeException]: `not_paired`, `no_session`,
  /// `wrong_user`, `unauthorized` (HTTP 401 / 403: không nối lại ngay), còn lại
  /// từ IDE.
  Future<IdeChannel> open() async {
    final creds = await _loadCredentials();
    if (creds == null || creds.serverScope != serverScopeId) {
      throw const IdeHandshakeException('not_paired');
    }
    final guard = await _tokens.captureMutationGuard();
    if (guard == null || guard.instanceScopeId != serverScopeId) {
      throw const IdeHandshakeException('no_session');
    }
    final token = (await _tokens.readAccessTokenIfCurrent(guard))?.trim();
    if (token == null || token.isEmpty) {
      throw const IdeHandshakeException('no_session');
    }
    if (!await _tokens.isMutationGuardCurrent(guard)) {
      throw const IdeHandshakeException('no_session');
    }
    final IdeSocket socket;
    try {
      socket = await _openSocket(uri, {
        'Authorization': 'Bearer $token',
        'X-IDE-Device': creds.deviceId,
      });
    } on WebSocketException catch (error) {
      // HTTP 401 / 403 trước khi nâng cấp: token hỏng hoặc sai vùng, nối lại
      // cũng vô ích. 503 (IDE_DISABLED / IDE_OFFLINE): nối lại có giãn cách.
      final status = error.httpStatusCode;
      if (status == 401 || status == 403) {
        throw IdeHandshakeException('unauthorized', deviceId: creds.deviceId);
      }
      if (status == 503) {
        throw IdeHandshakeException('ide_offline', deviceId: creds.deviceId);
      }
      rethrow;
    }
    if (!await _tokens.isMutationGuardCurrent(guard)) {
      await socket.close();
      throw const IdeHandshakeException('no_session');
    }
    final IdeChannel channel;
    try {
      channel = await IdeChannel.connect(
        socket: socket,
        handshakeTimeout: handshakeTimeout,
        pingEvery: pingEvery,
        deadAfter: deadAfter,
        signAuth: (nonce, stream, chatUser) {
          if (chatUser != creds.chatUserId) {
            throw const IdeHandshakeException('wrong_user');
          }
          return IdeDeviceKeyStore.signAuth(
            seed: creds.seed,
            nonce: nonce,
            stream: stream,
            chatUser: chatUser,
          );
        },
      );
    } on IdeHandshakeException catch (error) {
      throw IdeHandshakeException(error.reason, deviceId: creds.deviceId);
    }
    return channel..deviceId = creds.deviceId;
  }
}
