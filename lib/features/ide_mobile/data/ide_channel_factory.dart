import 'dart:io';

import '../../auth/domain/repositories/auth_token_repository.dart';
import '../../conversations/data/repositories/web_socket_conversation_realtime_repository.dart'
    show connectWebSocketWithoutRedirects;
import '../domain/ide_device_credentials.dart';
import 'ide_channel.dart';
import 'ide_device_key_store.dart';

/// Kết quả làm mới token chat khi nối IDE bị 401.
enum IdeTokenRefresh {
  /// Đã có token mới: nối lại một lần.
  refreshed,

  /// Máy chủ từ chối (phiên hết hạn / đã đổi phiên): dừng, báo hết phiên.
  rejected,

  /// Lỗi tạm (mất mạng, hết giờ chờ): coi như lỗi mạng, nối lại có giãn cách.
  failed,
}

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
    this.refreshAccessToken,
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

  /// Làm mới token chat của đúng phiên [AuthTokenMutationGuard] đang nối.
  /// Chỉ gọi tối đa MỘT lần mỗi lượt [open] khi máy chủ trả 401.
  final Future<IdeTokenRefresh> Function(AuthTokenMutationGuard guard)?
  refreshAccessToken;
  final Duration handshakeTimeout;
  final Duration pingEvery;
  final Duration deadAfter;

  Uri get uri => wsBaseUri.replace(path: '/api/v1/ide/ws', query: '');

  /// Lý do ném [IdeHandshakeException]: `not_paired`, `no_session`,
  /// `wrong_user`, `session_expired` (HTTP 401 cả sau khi làm mới token),
  /// `forbidden` (HTTP 403), còn lại từ IDE.
  Future<IdeChannel> open() async {
    final creds = await _loadCredentials();
    if (creds == null || creds.serverScope != serverScopeId) {
      throw const IdeHandshakeException('not_paired');
    }
    final guard = await _tokens.captureMutationGuard();
    if (guard == null || guard.instanceScopeId != serverScopeId) {
      throw const IdeHandshakeException('no_session');
    }
    IdeSocket? opened;
    var refreshed = false;
    while (opened == null) {
      final token = (await _tokens.readAccessTokenIfCurrent(guard))?.trim();
      if (token == null || token.isEmpty) {
        throw const IdeHandshakeException('no_session');
      }
      if (!await _tokens.isMutationGuardCurrent(guard)) {
        throw const IdeHandshakeException('no_session');
      }
      try {
        opened = await _openSocket(uri, {
          'Authorization': 'Bearer $token',
          'X-IDE-Device': creds.deviceId,
        });
      } on WebSocketException catch (error) {
        // HTTP 401 trước khi nâng cấp: token hết hạn / bị thu hồi → làm mới
        // token một lần rồi thử lại; vẫn 401 (hoặc máy chủ từ chối làm mới)
        // thì dừng, báo phiên hết hạn (không nối lại mãi). Làm mới hỏng vì
        // mạng thì ném lại lỗi mạng để nối lại có giãn cách.
        // 403: phiên không thuộc domain này / bị tắt quyền IDE, làm mới token
        // hay gắn lại máy đều vô ích. 503 (IDE_DISABLED / IDE_OFFLINE): nối
        // lại có giãn cách.
        final status = error.httpStatusCode;
        if (status == 401) {
          final refresh = refreshAccessToken;
          if (!refreshed && refresh != null) {
            refreshed = true;
            // REST vừa làm mới xong trong lúc nối: thử lại bằng token mới đang
            // lưu, không đổi refresh token thêm lượt nữa.
            final latest = (await _tokens.readAccessTokenIfCurrent(
              guard,
            ))?.trim();
            if (latest != null && latest.isNotEmpty && latest != token) {
              continue;
            }
            final outcome = await _tryRefresh(refresh, guard);
            if (outcome == IdeTokenRefresh.refreshed) continue;
            // Mất mạng lúc làm mới: không phải hết phiên, để nối lại sau.
            if (outcome == IdeTokenRefresh.failed) rethrow;
          }
          throw IdeHandshakeException(
            'session_expired',
            deviceId: creds.deviceId,
          );
        }
        if (status == 403) {
          throw IdeHandshakeException('forbidden', deviceId: creds.deviceId);
        }
        if (status == 503) {
          throw IdeHandshakeException('ide_offline', deviceId: creds.deviceId);
        }
        rethrow;
      }
    }
    final socket = opened;
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

  static Future<IdeTokenRefresh> _tryRefresh(
    Future<IdeTokenRefresh> Function(AuthTokenMutationGuard guard) refresh,
    AuthTokenMutationGuard guard,
  ) async {
    try {
      return await refresh(guard);
    } on Object {
      return IdeTokenRefresh.failed;
    }
  }
}
