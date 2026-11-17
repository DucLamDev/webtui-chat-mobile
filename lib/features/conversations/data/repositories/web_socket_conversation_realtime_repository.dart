import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../../../core/network/api_response.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../auth/domain/repositories/auth_token_repository.dart';
import '../../domain/entities/call_session.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import '../../domain/entities/rich_message.dart';
import '../../domain/repositories/conversation_repository.dart';

final class WebSocketConversationRealtimeRepository
    implements ConversationRealtimeRepository {
  WebSocketConversationRealtimeRepository({
    required Uri apiBaseUri,
    Uri? wsBaseUri,
    required InstanceScope instanceScope,
    required AuthTokenRepository tokenRepository,
    Future<WebSocket> Function(String url, {Map<String, dynamic>? headers})?
    connectWebSocket,
    Duration idleDisconnectGrace = realtimeIdleDisconnectGrace,
  }) : _idleDisconnectGrace = idleDisconnectGrace,
       _apiBaseUri = apiBaseUri,
       _wsBaseUri = _validatedRealtimeWsBaseUri(
         wsBaseUri ?? defaultConversationRealtimeWsUri(apiBaseUri),
         instanceScope,
       ),
       _instanceScope = instanceScope,
       _tokenRepository = tokenRepository,
       _connectWebSocket = connectWebSocket ?? _defaultConnectWebSocket;

  final Uri _apiBaseUri;
  final Uri _wsBaseUri;
  final Duration _idleDisconnectGrace;
  final InstanceScope _instanceScope;
  final AuthTokenRepository _tokenRepository;
  final Future<WebSocket> Function(String url, {Map<String, dynamic>? headers})
  _connectWebSocket;

  WebSocket? _socket;
  StreamController<ConversationRealtimeEvent>? _controller;
  final Set<String> _joinedRooms = <String>{};

  /// Số luồng đang nghe mỗi phòng (phòng chat, hộp thư ticket). Cả app dùng
  /// chung một kết nối sống suốt phiên, nên màn rời phòng thì chỉ bớt đếm; về 0
  /// mới rời phòng trên máy chủ (không đóng kết nối).
  final Map<String, int> _roomListeners = <String, int>{};

  /// Hết người nghe: chờ chừng này mới đóng kết nối, để lúc chuyển màn (một
  /// màn huỷ nghe trước khi màn sau nghe) không bị ngắt rồi nối lại.
  Timer? _idleDisconnectTimer;

  /// Phòng của các hội thoại trong danh sách chat ([watchChannels]): chỉ để
  /// nhận tin mới (cập nhật số chưa đọc), không phát `reconnected` riêng từng
  /// phòng như [_joinedRooms].
  final Set<String> _watchedRooms = <String>{};
  // Sự kiện của phòng chỉ để theo dõi danh sách ([watchChannels]) đi luồng
  // riêng: luồng người dùng / phòng chat (cuộc gọi đến, đổi thành viên...)
  // không nhận thêm sự kiện của mọi nhóm, và huỷ nghe luồng này không làm
  // ngắt kết nối nền.
  StreamController<ConversationRealtimeEvent>? _watchController;
  String? _activeWorkspaceId;
  bool _disposed = false;
  bool _connecting = false;
  bool _hasConnected = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastPongAt;
  final RecentRealtimeEventIds _seenEventIds = RecentRealtimeEventIds();

  /// Kết nối phụ cho workspace KHÁC workspace đang có người nghe (vd mở phòng
  /// của workspace khác từ thông báo): không đóng kết nối đang dùng (cuộc gọi
  /// đến, danh sách chat) chỉ vì một màn của workspace khác.
  WebSocketConversationRealtimeRepository? _otherWorkspace;

  /// Kho phục vụ [workspaceId]: chính kho này, trừ khi nó đang nối workspace
  /// khác mà vẫn còn người nghe (khi đó dùng kết nối phụ). Không còn ai nghe
  /// thì đổi workspace như trước (đóng kết nối cũ, nối workspace mới).
  WebSocketConversationRealtimeRepository _serving(String workspaceId) {
    final active = _activeWorkspaceId;
    if (active == null ||
        active == workspaceId ||
        _disposed ||
        _controller?.hasListener != true) {
      return this;
    }
    return _otherWorkspace ??= WebSocketConversationRealtimeRepository(
      apiBaseUri: _apiBaseUri,
      wsBaseUri: _wsBaseUri,
      instanceScope: _instanceScope,
      tokenRepository: _tokenRepository,
      connectWebSocket: _connectWebSocket,
      idleDisconnectGrace: _idleDisconnectGrace,
    );
  }

  @override
  Stream<ConversationRealtimeEvent> subscribeToUser({
    required String workspaceId,
  }) {
    final target = _serving(workspaceId);
    if (!identical(target, this)) {
      return target.subscribeToUser(workspaceId: workspaceId);
    }
    return _subscribe(workspaceId: workspaceId, channelId: '');
  }

  @override
  Stream<ConversationRealtimeEvent> subscribeToChannel({
    required String workspaceId,
    required String channelId,
  }) {
    final target = _serving(workspaceId);
    if (!identical(target, this)) {
      return target.subscribeToChannel(
        workspaceId: workspaceId,
        channelId: channelId,
      );
    }
    return _subscribe(workspaceId: workspaceId, channelId: channelId);
  }

  Stream<ConversationRealtimeEvent> _subscribe({
    required String workspaceId,
    required String channelId,
  }) {
    _disposed = false;
    if (_activeWorkspaceId != null && _activeWorkspaceId != workspaceId) {
      _closeCurrentConnection(leaveRooms: true, closeController: true);
    }
    _activeWorkspaceId = workspaceId;
    final controller = _ensureController();
    final normalizedChannelId = channelId.trim();
    unawaited(_ensureConnected(workspaceId: workspaceId));

    final events = controller.stream.where(
      (event) => event.workspaceId == workspaceId,
    );
    if (normalizedChannelId.isEmpty) {
      return events;
    }
    return _holdingRoom(
      events.where((event) => event.channelId == normalizedChannelId),
      _roomFor(workspaceId, normalizedChannelId),
    );
  }

  /// Nghe [events] và giữ [room] trong lúc còn nghe: người nghe đầu tiên vào
  /// phòng, người cuối huỷ thì rời phòng (kết nối vẫn mở cho phần còn lại).
  Stream<ConversationRealtimeEvent> _holdingRoom(
    Stream<ConversationRealtimeEvent> events,
    String room,
  ) {
    return Stream<ConversationRealtimeEvent>.multi((listener) {
      _retainRoom(room);
      final subscription = events.listen(
        listener.addSync,
        onError: listener.addErrorSync,
        onDone: listener.closeSync,
      );
      listener
        ..onPause = subscription.pause
        ..onResume = subscription.resume
        ..onCancel = () {
          _releaseRoom(room);
          return subscription.cancel();
        };
    });
  }

  void _retainRoom(String room) {
    final count = (_roomListeners[room] ?? 0) + 1;
    _roomListeners[room] = count;
    if (count == 1 && _joinedRooms.add(room)) {
      _joinRoomIfOpen(room);
    }
  }

  void _releaseRoom(String room) {
    final count = (_roomListeners[room] ?? 0) - 1;
    if (count > 0) {
      _roomListeners[room] = count;
      return;
    }
    _roomListeners.remove(room);
    if (!_joinedRooms.remove(room)) return;
    // Phòng vẫn nằm trong danh sách chat đang theo dõi: giữ để nhận tin mới.
    if (_watchedRooms.contains(room)) return;
    _sendCommand({'type': 'leave', 'room': room});
  }

  /// Phòng hộp thư ticket khách `workspace:<ws>:order-tickets` (máy chủ tự kiểm
  /// quyền khi join). Chỉ trả `OrderTicketUpdated` và `reconnected` để màn
  /// ticket tự tải lại sau khi rớt mạng.
  Stream<ConversationRealtimeEvent> subscribeToOrderTickets({
    required String workspaceId,
  }) {
    final target = _serving(workspaceId);
    if (!identical(target, this)) {
      return target.subscribeToOrderTickets(workspaceId: workspaceId);
    }
    final events = _subscribe(workspaceId: workspaceId, channelId: '');
    return _holdingRoom(
      events.where(
        (event) =>
            event.type == ConversationRealtimeEventType.orderTicketUpdated ||
            event.type == ConversationRealtimeEventType.reconnected,
      ),
      _orderTicketsRoomFor(workspaceId),
    );
  }

  /// Hộp thư khách: sự kiện `Inbox*` đến qua phòng người dùng (không cần join
  /// thêm phòng). Kèm `reconnected` để màn tự tải lại sau khi rớt mạng.
  Stream<ConversationRealtimeEvent> subscribeToInbox({
    required String workspaceId,
  }) {
    final target = _serving(workspaceId);
    if (!identical(target, this)) {
      return target.subscribeToInbox(workspaceId: workspaceId);
    }
    return _subscribe(workspaceId: workspaceId, channelId: '').where(
      (event) =>
          event.type ==
              ConversationRealtimeEventType.inboxConversationUpdated ||
          event.type == ConversationRealtimeEventType.inboxMessageCreated ||
          event.type == ConversationRealtimeEventType.reconnected,
    );
  }

  @override
  Stream<ConversationRealtimeEvent>? watchChannels({
    required String workspaceId,
    required Iterable<String> channelIds,
  }) {
    // Chỉ áp cho workspace đang nối, không tự nối / đổi workspace (kết nối này
    // còn dùng cho cuộc gọi đến của workspace đang mở).
    final controller = _controller;
    if (_disposed ||
        _activeWorkspaceId != workspaceId ||
        controller == null ||
        controller.isClosed) {
      return null;
    }
    final next = {
      for (final id in channelIds)
        if (id.trim().isNotEmpty) _roomFor(workspaceId, id.trim()),
    };
    for (final room in _watchedRooms.difference(next)) {
      // Phòng cũng đang dùng cho luồng khác trên cùng kết nối thì giữ.
      if (_joinedRooms.contains(room)) continue;
      _sendCommand({'type': 'leave', 'room': room});
    }
    for (final room in next.difference(_watchedRooms)) {
      if (_joinedRooms.contains(room)) continue;
      _joinRoomIfOpen(room);
    }
    _watchedRooms
      ..clear()
      ..addAll(next);
    final watchController = _watchController ??=
        StreamController<ConversationRealtimeEvent>.broadcast();
    return watchController.stream.where(
      (event) => event.workspaceId == workspaceId,
    );
  }

  @override
  Future<void> sendTyping({
    required String workspaceId,
    required String channelId,
    required bool isTyping,
  }) async {
    final other = _otherWorkspace;
    if (_activeWorkspaceId != workspaceId &&
        other != null &&
        other._activeWorkspaceId == workspaceId) {
      return other.sendTyping(
        workspaceId: workspaceId,
        channelId: channelId,
        isTyping: isTyping,
      );
    }
    final room = _roomFor(workspaceId, channelId);
    // Phòng chat đang mở đã được giữ bởi luồng nghe của nó; chưa có thì vào
    // tạm (máy chủ chỉ nhận "đang gõ" từ người ở trong phòng).
    if (!_joinedRooms.contains(room) && !_watchedRooms.contains(room)) {
      _joinRoomIfOpen(room);
    }
    if (!_sendCommand({
      'type': isTyping ? 'TypingStarted' : 'TypingStopped',
      'room': room,
    })) {
      return;
    }
  }

  @override
  Future<void> disconnect() async {
    _disposed = true;
    _closeCurrentConnection(leaveRooms: true, closeController: true);
    final other = _otherWorkspace;
    _otherWorkspace = null;
    await other?.disconnect();
  }

  StreamController<ConversationRealtimeEvent> _ensureController() {
    return _controller ??=
        StreamController<ConversationRealtimeEvent>.broadcast(
          onListen: () {
            _idleDisconnectTimer?.cancel();
            _idleDisconnectTimer = null;
            final workspaceId = _activeWorkspaceId;
            if (workspaceId != null && workspaceId.isNotEmpty) {
              unawaited(_ensureConnected(workspaceId: workspaceId));
            }
          },
          onCancel: () {
            if (_controller?.hasListener != false) return;
            _idleDisconnectTimer?.cancel();
            _idleDisconnectTimer = Timer(_idleDisconnectGrace, () {
              _idleDisconnectTimer = null;
              if (_controller?.hasListener == false) {
                unawaited(disconnect());
              }
            });
          },
        );
  }

  Future<void> _ensureConnected({required String workspaceId}) async {
    if (_disposed || (_controller?.isClosed ?? true)) {
      return;
    }
    final socket = _socket;
    if (socket != null && socket.readyState == WebSocket.open) {
      _joinAllRooms();
      return;
    }
    if (_connecting) {
      return;
    }
    _connecting = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final guard = await _tokenRepository.captureMutationGuard();
    if (_disposed ||
        guard == null ||
        guard.instanceScopeId != _instanceScope.storageId) {
      _connecting = false;
      return;
    }
    final token = (await _tokenRepository.readAccessTokenIfCurrent(
      guard,
    ))?.trim();
    if (token == null || token.isEmpty) {
      _connecting = false;
      return;
    }
    if (_disposed || !await _tokenRepository.isMutationGuardCurrent(guard)) {
      _connecting = false;
      return;
    }
    try {
      final socket = await _connectWebSocket(
        _webSocketUri().toString(),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (_disposed ||
          _activeWorkspaceId != workspaceId ||
          !await _tokenRepository.isMutationGuardCurrent(guard)) {
        await socket.close();
        _connecting = false;
        return;
      }
      _socket = socket;
      _reconnectAttempt = 0;
      _connecting = false;
      final reconnected = _hasConnected;
      _hasConnected = true;
      _joinAllRooms();
      _startHeartbeat(workspaceId);
      socket.listen(
        (data) => _handleSocketData(data, workspaceId),
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
      if (reconnected) {
        _emitReconnected(workspaceId);
      }
    } on Object {
      _connecting = false;
      _scheduleReconnect();
    }
  }

  static Future<WebSocket> _defaultConnectWebSocket(
    String url, {
    Map<String, dynamic>? headers,
  }) {
    return connectWebSocketWithoutRedirects(url, headers: headers);
  }

  /// Báo cho mọi người nghe (cả từng phòng chat lẫn luồng của người dùng).
  void _emitReconnected(String workspaceId) {
    _emitToAllListeners(workspaceId, ConversationRealtimeEventType.reconnected);
  }

  void _emitToAllListeners(
    String workspaceId,
    ConversationRealtimeEventType type,
  ) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    final channelIds = {
      '',
      for (final room in _joinedRooms) ?_channelIdOfRoom(room),
    };
    for (final channelId in channelIds) {
      controller.add(
        ConversationRealtimeEvent(
          type: type,
          workspaceId: workspaceId,
          channelId: channelId,
        ),
      );
    }
  }

  void _handleSocketData(Object? data, String workspaceId) {
    final (socketEventType, socketRoom) = _socketEnvelope(data);
    if (socketEventType == 'pong') {
      _lastPongAt = DateTime.now().toUtc();
      return;
    }
    if (socketEventType == 'ResyncRequired') {
      _handleResyncRequired(workspaceId);
      return;
    }
    final event = ConversationRealtimeEventMapper.fromSocketData(
      data,
      fallbackWorkspaceId: workspaceId,
      fallbackChannelId: '',
    );
    if (event == null || (_controller?.isClosed ?? true)) {
      return;
    }
    // Cùng một sự kiện có thể tới hai lần (gửi lại sau khi nối lại, nhiều
    // node): máy chủ mới gắn `event_id` duy nhất nên bỏ bản trùng.
    if (!_seenEventIds.markSeen(event.eventId)) {
      return;
    }
    if (socketRoom != null && _watchedRooms.contains(socketRoom)) {
      final watchController = _watchController;
      if (watchController != null && !watchController.isClosed) {
        watchController.add(event);
      }
      // Phòng chỉ để theo dõi danh sách: không đưa vào luồng chung.
      if (!_joinedRooms.contains(socketRoom)) return;
    }
    _controller?.add(event);
  }

  /// Máy chủ báo máy này nhận chậm và sắp ngắt: báo người nghe đồng bộ bù, rồi
  /// chủ động đóng để nối lại ngay (sau khi nối lại, người nghe nhận thêm
  /// `reconnected` để tải lại phòng đang mở).
  void _handleResyncRequired(String workspaceId) {
    _emitToAllListeners(
      workspaceId,
      ConversationRealtimeEventType.resyncRequired,
    );
    final socket = _socket;
    if (socket != null) {
      unawaited(socket.close());
    }
  }

  void _scheduleReconnect() {
    final workspaceId = _activeWorkspaceId;
    if (_disposed ||
        (_controller?.isClosed ?? true) ||
        _controller?.hasListener != true ||
        workspaceId == null ||
        workspaceId.isEmpty ||
        _reconnectTimer != null) {
      return;
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _socket = null;
    final delay = Duration(
      seconds: _reconnectAttempt < 5 ? 1 << _reconnectAttempt : 16,
    );
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_disposed && _activeWorkspaceId == workspaceId) {
        unawaited(_ensureConnected(workspaceId: workspaceId));
      }
    });
  }

  void _closeCurrentConnection({
    required bool leaveRooms,
    required bool closeController,
  }) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (closeController) {
      _idleDisconnectTimer?.cancel();
      _idleDisconnectTimer = null;
    }
    final socket = _socket;
    if (leaveRooms && socket != null && socket.readyState == WebSocket.open) {
      for (final room in {..._joinedRooms, ..._watchedRooms}) {
        try {
          socket.add(jsonEncode({'type': 'leave', 'room': room}));
        } on Object {
          break;
        }
      }
    }
    unawaited(socket?.close());
    _socket = null;
    _connecting = false;
    _lastPongAt = null;
    if (closeController) {
      unawaited(_controller?.close());
      _controller = null;
      _joinedRooms.clear();
      _roomListeners.clear();
      _watchedRooms.clear();
      unawaited(_watchController?.close());
      _watchController = null;
      _activeWorkspaceId = null;
      _hasConnected = false;
      _seenEventIds.clear();
    }
  }

  Uri _webSocketUri() {
    return conversationRealtimeWebSocketUri(_wsBaseUri);
  }

  void _joinAllRooms() {
    for (final room in {..._joinedRooms, ..._watchedRooms}) {
      _joinRoomIfOpen(room);
    }
  }

  void _joinRoomIfOpen(String room) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      return;
    }
    _sendCommand({'type': 'join', 'room': room});
  }

  bool _sendCommand(Map<String, Object?> command) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      return false;
    }
    try {
      socket.add(jsonEncode(command));
      return true;
    } on Object {
      _scheduleReconnect();
      return false;
    }
  }

  void _startHeartbeat(String workspaceId) {
    _heartbeatTimer?.cancel();
    _lastPongAt = DateTime.now().toUtc();
    _heartbeatTimer = Timer.periodic(_realtimeHeartbeatInterval, (_) {
      final socket = _socket;
      if (socket == null || socket.readyState != WebSocket.open) {
        return;
      }
      final lastPongAt = _lastPongAt;
      if (lastPongAt != null &&
          DateTime.now().toUtc().difference(lastPongAt) >
              _realtimeHeartbeatTimeout) {
        unawaited(socket.close());
        _scheduleReconnect();
        return;
      }
      _sendCommand({'type': 'ping', 'room': _heartbeatRoom(workspaceId)});
    });
  }
}

const _realtimeHeartbeatInterval = Duration(seconds: 25);

/// Hết người nghe bao lâu thì đóng kết nối realtime (xem `_idleDisconnectTimer`).
const realtimeIdleDisconnectGrace = Duration(seconds: 30);
const _realtimeHeartbeatTimeout = Duration(seconds: 70);

Uri defaultConversationRealtimeWsUri(Uri apiBaseUri) {
  final scheme = apiBaseUri.scheme == 'https' ? 'wss' : 'ws';
  return Uri(
    scheme: scheme,
    userInfo: apiBaseUri.userInfo,
    host: apiBaseUri.host,
    port: apiBaseUri.hasPort ? apiBaseUri.port : null,
    path: '/ws',
  );
}

Uri conversationRealtimeWebSocketUri(Uri wsBaseUri) => wsBaseUri;

Uri _validatedRealtimeWsBaseUri(Uri candidate, InstanceScope instanceScope) {
  if ((!candidate.isScheme('ws') && !candidate.isScheme('wss')) ||
      candidate.host.isEmpty ||
      candidate.userInfo.isNotEmpty ||
      candidate.fragment.isNotEmpty) {
    throw const FormatException('WebSocket discovery URL is not safe.');
  }
  final transportOrigin = candidate.replace(
    scheme: candidate.isScheme('wss') ? 'https' : 'http',
    path: '',
    query: '',
    fragment: '',
  );
  if (!serverOriginsMatch(transportOrigin, instanceScope.origin)) {
    throw const FormatException(
      'WebSocket discovery URL must use the active instance origin.',
    );
  }
  return candidate;
}

/// Performs the WebSocket upgrade without following HTTP redirects.
///
/// Dart's default WebSocket client follows GET redirects and preserves an
/// Authorization header for subdomains. A self-hosted instance token must
/// never leave the exact discovery origin, so every non-101 response is a
/// terminal handshake failure.
Future<WebSocket> connectWebSocketWithoutRedirects(
  String url, {
  Map<String, dynamic>? headers,
}) async {
  final webSocketUri = Uri.parse(url);
  if (!webSocketUri.isScheme('ws') && !webSocketUri.isScheme('wss')) {
    throw WebSocketException(
      "Unsupported WebSocket URL scheme '${webSocketUri.scheme}'.",
    );
  }
  if (webSocketUri.host.isEmpty ||
      webSocketUri.userInfo.isNotEmpty ||
      webSocketUri.fragment.isNotEmpty) {
    throw const WebSocketException('WebSocket URL is not safe.');
  }

  final requestUri = webSocketUri.replace(
    scheme: webSocketUri.isScheme('wss') ? 'https' : 'http',
  );
  final httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  Socket? upgradedSocket;
  var handshakeCompleted = false;
  try {
    final secureRandom = Random.secure();
    final nonceBytes = List<int>.generate(
      16,
      (_) => secureRandom.nextInt(256),
      growable: false,
    );
    final nonce = base64Encode(nonceBytes);
    final request = await httpClient
        .openUrl('GET', requestUri)
        .timeout(const Duration(seconds: 15));
    request
      ..followRedirects = false
      ..maxRedirects = 0;
    headers?.forEach((name, value) {
      if (_webSocketControlledHeaders.contains(name.toLowerCase())) {
        throw WebSocketException(
          'Caller cannot override the WebSocket $name header.',
        );
      }
      request.headers.add(name, value);
    });
    request.headers
      ..set(HttpHeaders.connectionHeader, 'Upgrade')
      ..set(HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Key', nonce)
      ..set('Sec-WebSocket-Version', '13')
      // Máy chủ dùng x/net/websocket trả 403 "null origin" khi thiếu Origin:
      // không có dòng này app không bao giờ nhận được sự kiện realtime (tín
      // hiệu cuộc gọi kẹt "Đang kết nối"). Origin luôn là chính máy chủ đang
      // kết nối, nơi gọi không đổi được.
      ..set('Origin', requestUri.origin)
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');

    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.switchingProtocols) {
      throw WebSocketException(
        'WebSocket endpoint refused the direct upgrade.',
        response.statusCode,
      );
    }

    final connectionTokens = response.headers
        .value(HttpHeaders.connectionHeader)
        ?.split(',')
        .map((value) => value.trim().toLowerCase());
    final upgrade = response.headers
        .value(HttpHeaders.upgradeHeader)
        ?.trim()
        .toLowerCase();
    final expectedAccept = base64Encode(
      sha1.convert(utf8.encode('$nonce$_webSocketHandshakeGuid')).bytes,
    );
    final actualAccept = response.headers.value('Sec-WebSocket-Accept')?.trim();
    if (connectionTokens?.contains('upgrade') != true ||
        upgrade != 'websocket' ||
        actualAccept != expectedAccept) {
      final invalidSocket = await response.detachSocket();
      invalidSocket.destroy();
      throw const WebSocketException(
        'WebSocket endpoint returned an invalid upgrade response.',
      );
    }

    upgradedSocket = await response.detachSocket();
    final socket = WebSocket.fromUpgradedSocket(
      upgradedSocket,
      serverSide: false,
    );
    upgradedSocket = null;
    handshakeCompleted = true;
    return socket;
  } finally {
    if (upgradedSocket != null) {
      upgradedSocket.destroy();
    }
    httpClient.close(force: !handshakeCompleted);
  }
}

const _webSocketHandshakeGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const _webSocketControlledHeaders = {
  'origin',
  'connection',
  'upgrade',
  'sec-websocket-key',
  'sec-websocket-version',
  'sec-websocket-protocol',
  'sec-websocket-extensions',
};

final class ConversationRealtimeEventMapper {
  const ConversationRealtimeEventMapper._();

  static ConversationRealtimeEvent? fromSocketData(
    Object? data, {
    required String fallbackWorkspaceId,
    required String fallbackChannelId,
  }) {
    final decoded = switch (data) {
      final String value => jsonDecode(value),
      final List<int> value => jsonDecode(utf8.decode(value)),
      final Map value => value,
      _ => null,
    };
    final map = jsonMap(decoded);
    if (map.isEmpty) {
      return null;
    }
    final payload = jsonMap(field(map, const ['payload']));
    final signal = jsonMap(field(payload, const ['signal']));
    final signalPayload = signal.isEmpty ? payload : signal;
    final messageMap = jsonMap(field(payload, const ['message']));
    final message = messageMap.isEmpty
        ? null
        : _messageFromMap(messageMap, fallbackWorkspaceId, fallbackChannelId);
    final roomChannelId = _channelIdFromRoom(
      nullableStringField(map, const ['room']),
    );
    final type = _eventType(stringField(map, const ['type']));
    final callStatus = _callStatusForEvent(type);
    return ConversationRealtimeEvent(
      type: type,
      workspaceId:
          (_isInboxEvent(type)
              ? nullableStringField(payload, const [
                  'workspace_id',
                  'workspaceId',
                ])
              : null) ??
          message?.workspaceId ??
          stringField(payload, const [
            'workspace_id',
            'workspaceId',
          ], fallback: fallbackWorkspaceId),
      channelId:
          message?.channelId ??
          stringField(
            payload,
            const ['channel_id', 'channelId'],
            fallback: roomChannelId.isNotEmpty
                ? roomChannelId
                : fallbackChannelId,
          ),
      message: message,
      messageId:
          message?.id ??
          nullableStringField(messageMap, const ['id']) ??
          nullableStringField(payload, const ['message_id', 'messageId']),
      // `ChannelMemberLeft`: người rời nằm ở `payload.user_id`, ưu tiên hơn
      // người gửi sự kiện ở ngoài.
      userId: type == ConversationRealtimeEventType.channelMemberLeft
          ? nullableStringField(payload, const ['user_id', 'userId']) ??
                nullableStringField(map, const ['user_id', 'userId'])
          : nullableStringField(map, const ['user_id', 'userId']) ??
                nullableStringField(payload, const ['user_id', 'userId']),
      timestamp: nullableDateTimeField(map, const ['timestamp']),
      callId: nullableStringField(payload, const ['call_id', 'callId']),
      callMode: _callMode(nullableStringField(payload, const ['mode'])),
      callStatus: callStatus,
      callInitiatorUserId: nullableStringField(payload, const [
        'initiator_user_id',
        'initiatorUserId',
      ]),
      callTargetUserId: nullableStringField(payload, const [
        'target_user_id',
        'targetUserId',
      ]),
      reason: nullableStringField(payload, const ['reason']),
      callSdp: jsonMap(field(signalPayload, const ['sdp'])),
      callCandidate: jsonMap(field(signalPayload, const ['candidate'])),
      payload: _keepsPayload.contains(type) ? payload : const {},
      eventId: nullableStringField(map, const ['event_id', 'eventId']),
      targetDeviceId:
          nullableStringField(payload, const [
            'target_device_id',
            'targetDeviceId',
          ]) ??
          nullableStringField(signal, const [
            'target_device_id',
            'targetDeviceId',
          ]),
      answeredDeviceId: nullableStringField(payload, const [
        'answered_device_id',
        'answeredDeviceId',
      ]),
      initiatorDeviceId: nullableStringField(payload, const [
        'initiator_device_id',
        'initiatorDeviceId',
      ]),
      delta: type == ConversationRealtimeEventType.messageDelta
          ? _messageDeltaFromPayload(payload)
          : null,
    );
  }
}

/// Sự kiện cần giữ payload gốc cho nơi xử lý (ticket, bản ghi giọng nói,
/// phiên bị thu hồi, thiết bị chờ duyệt).
const _keepsPayload = {
  ConversationRealtimeEventType.groupCallStarted,
  ConversationRealtimeEventType.groupCallRingStopped,
  ConversationRealtimeEventType.groupCallEnded,
  ConversationRealtimeEventType.orderTicketUpdated,
  ConversationRealtimeEventType.transcriptUpdated,
  ConversationRealtimeEventType.channelReadUpdated,
  ConversationRealtimeEventType.channelUpdated,
  ConversationRealtimeEventType.sessionRevoked,
  ConversationRealtimeEventType.deviceApprovalRequested,
  ConversationRealtimeEventType.inboxConversationUpdated,
  ConversationRealtimeEventType.inboxMessageCreated,
  ConversationRealtimeEventType.meetingUpdated,
};

/// Sự kiện hộp thư khách: `workspace_id` của payload là nguồn đúng (tin trong
/// payload không mang workspace).
bool _isInboxEvent(ConversationRealtimeEventType type) =>
    type == ConversationRealtimeEventType.inboxConversationUpdated ||
    type == ConversationRealtimeEventType.inboxMessageCreated;

/// `MessageDelta` thiếu id / seq không hợp lệ thì bỏ (không ghép được).
MessageStreamDelta? _messageDeltaFromPayload(JsonMap payload) {
  final messageId = nullableStringField(payload, const [
    'message_id',
    'messageId',
  ]);
  final rawSeq = field(payload, const ['seq']);
  final seq =
      rawSeq is num && rawSeq.isFinite && rawSeq == rawSeq.roundToDouble()
      ? rawSeq.toInt()
      : null;
  final append = field(payload, const ['append']);
  if (messageId == null || seq == null || seq < 1 || append is! String) {
    return null;
  }
  return MessageStreamDelta(messageId: messageId, seq: seq, append: append);
}

/// Nhớ ~500 `event_id` gần nhất để bỏ sự kiện realtime trùng.
final class RecentRealtimeEventIds {
  RecentRealtimeEventIds({this.capacity = 500});

  final int capacity;
  final _ids = <String>{};

  /// `true` nếu sự kiện mới (hoặc không có mã); `false` nếu đã thấy.
  bool markSeen(String? eventId) {
    final id = eventId?.trim() ?? '';
    if (id.isEmpty) return true;
    if (!_ids.add(id)) return false;
    while (_ids.length > capacity) {
      _ids.remove(_ids.first);
    }
    return true;
  }

  void clear() => _ids.clear();
}

ConversationRealtimeEventType _eventType(String value) {
  return switch (value.trim()) {
    'MessageCreated' => ConversationRealtimeEventType.messageCreated,
    'MessageUpdated' => ConversationRealtimeEventType.messageUpdated,
    'MessageDeleted' ||
    'MessageExpired' => ConversationRealtimeEventType.messageDeleted,
    'MessagePinned' => ConversationRealtimeEventType.messagePinned,
    'MessageUnpinned' => ConversationRealtimeEventType.messageUnpinned,
    'ReactionChanged' => ConversationRealtimeEventType.reactionChanged,
    'AttachmentCreated' => ConversationRealtimeEventType.attachmentCreated,
    'MessageDelta' => ConversationRealtimeEventType.messageDelta,
    'TranscriptUpdated' => ConversationRealtimeEventType.transcriptUpdated,
    'TypingStarted' => ConversationRealtimeEventType.typingStarted,
    'TypingStopped' => ConversationRealtimeEventType.typingStopped,
    'ChannelReadUpdated' => ConversationRealtimeEventType.channelReadUpdated,
    'CallInvited' => ConversationRealtimeEventType.callInvited,
    'CallAccepted' => ConversationRealtimeEventType.callAccepted,
    'CallReady' => ConversationRealtimeEventType.callReady,
    'CallOffer' => ConversationRealtimeEventType.callOffer,
    'CallAnswer' => ConversationRealtimeEventType.callAnswer,
    'CallIceCandidate' => ConversationRealtimeEventType.callIceCandidate,
    'CallRejected' => ConversationRealtimeEventType.callRejected,
    'CallCancelled' => ConversationRealtimeEventType.callCancelled,
    'CallEnded' => ConversationRealtimeEventType.callEnded,
    'CallMissed' => ConversationRealtimeEventType.callMissed,
    'CallAnsweredElsewhere' =>
      ConversationRealtimeEventType.callAnsweredElsewhere,
    'GroupCallStarted' => ConversationRealtimeEventType.groupCallStarted,
    'GroupCallRingStopped' =>
      ConversationRealtimeEventType.groupCallRingStopped,
    'GroupCallEnded' => ConversationRealtimeEventType.groupCallEnded,
    'ResyncRequired' => ConversationRealtimeEventType.resyncRequired,
    'ContactRequestCreated' =>
      ConversationRealtimeEventType.contactRequestCreated,
    'ContactRequestUpdated' =>
      ConversationRealtimeEventType.contactRequestUpdated,
    'ContactRequestCancelled' =>
      ConversationRealtimeEventType.contactRequestCancelled,
    'NoticeChannelCreated' =>
      ConversationRealtimeEventType.noticeChannelCreated,
    'ChannelMemberAdded' => ConversationRealtimeEventType.channelMemberAdded,
    'ChannelUpdated' => ConversationRealtimeEventType.channelUpdated,
    'ChannelMemberLeft' => ConversationRealtimeEventType.channelMemberLeft,
    'ChannelArchived' => ConversationRealtimeEventType.channelArchived,
    'OrderTicketUpdated' => ConversationRealtimeEventType.orderTicketUpdated,
    'SessionRevoked' => ConversationRealtimeEventType.sessionRevoked,
    'DeviceApprovalRequested' =>
      ConversationRealtimeEventType.deviceApprovalRequested,
    'InboxConversationUpdated' =>
      ConversationRealtimeEventType.inboxConversationUpdated,
    'InboxMessageCreated' => ConversationRealtimeEventType.inboxMessageCreated,
    'MeetingUpdated' => ConversationRealtimeEventType.meetingUpdated,
    _ => ConversationRealtimeEventType.unknown,
  };
}

CallMode? _callMode(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'audio' => CallMode.audio,
    'video' => CallMode.video,
    _ => null,
  };
}

CallStatus? _callStatusForEvent(ConversationRealtimeEventType type) {
  return switch (type) {
    ConversationRealtimeEventType.callInvited => CallStatus.ringing,
    ConversationRealtimeEventType.callAccepted ||
    ConversationRealtimeEventType.callAnsweredElsewhere => CallStatus.accepted,
    ConversationRealtimeEventType.callRejected => CallStatus.rejected,
    ConversationRealtimeEventType.callCancelled => CallStatus.cancelled,
    ConversationRealtimeEventType.callEnded => CallStatus.ended,
    ConversationRealtimeEventType.callMissed => CallStatus.missed,
    _ => null,
  };
}

ChatMessage _messageFromMap(JsonMap map, String workspaceId, String channelId) {
  final messageId = stringField(map, const ['id']);
  final resolvedWorkspaceId = stringField(map, const [
    'workspace_id',
    'workspaceId',
  ], fallback: workspaceId);
  return ChatMessage(
    id: messageId,
    workspaceId: resolvedWorkspaceId,
    channelId: stringField(map, const [
      'channel_id',
      'channelId',
    ], fallback: channelId),
    kind: stringField(map, const ['kind'], fallback: 'text'),
    isSecret: map['secret'] == true,
    expiresAt: nullableDateTimeField(map, const ['expires_at']),
    body: map['secret'] == true ? '' : stringField(map, const ['body']),
    createdAt: dateTimeField(map, const ['created_at', 'sent_at', 'createdAt']),
    senderId: nullableStringField(map, const [
      'sender_id',
      'author_id',
      'senderId',
      'authorId',
    ]),
    parentId: nullableStringField(map, const ['parent_id', 'parentId']),
    threadRootId: nullableStringField(map, const [
      'thread_root_id',
      'threadRootId',
    ]),
    editedAt: nullableDateTimeField(map, const ['edited_at', 'editedAt']),
    deletedAt: nullableDateTimeField(map, const ['deleted_at', 'deletedAt']),
    updatedAt: nullableDateTimeField(map, const ['updated_at', 'updatedAt']),
    mentions: field(map, const ['mentions']) is List
        ? (field(map, const ['mentions']) as List)
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList(growable: false)
        : const [],
    reactions: jsonMapList(
      field(map, const ['reactions']),
    ).map(_reactionFromMap).toList(growable: false),
    metadata: Map<String, Object?>.from(
      jsonMap(field(map, const ['metadata'])),
    ),
    attachments: _messageAttachmentsFromMap(
      map,
      workspaceId: resolvedWorkspaceId,
      messageId: messageId,
    ),
  );
}

List<MessageAttachment> _messageAttachmentsFromMap(
  JsonMap map, {
  required String workspaceId,
  required String messageId,
}) {
  return jsonMapList(field(map, const ['attachments', 'message_attachments']))
      .map(
        (attachmentMap) => _messageAttachmentFromMap(
          attachmentMap,
          workspaceId: workspaceId,
          messageId: messageId,
        ),
      )
      .toList(growable: false);
}

MessageAttachment _messageAttachmentFromMap(
  JsonMap map, {
  required String workspaceId,
  required String messageId,
}) {
  final fileMap = jsonMap(field(map, const ['file']));
  final file = _uploadedMessageFileFromMap(
    fileMap.isEmpty ? map : fileMap,
    fallbackWorkspaceId: workspaceId,
  );
  final resolvedMessageId = stringField(map, const [
    'message_id',
    'messageId',
  ], fallback: messageId);
  final fileId = stringField(map, const [
    'file_id',
    'fileId',
  ], fallback: file.id);
  return MessageAttachment(
    id: stringField(map, const [
      'id',
      'attachment_id',
      'attachmentId',
    ], fallback: '$resolvedMessageId:$fileId'),
    workspaceId: stringField(map, const [
      'workspace_id',
      'workspaceId',
    ], fallback: workspaceId),
    messageId: resolvedMessageId,
    fileId: fileId,
    file: file,
    sortOrder: intField(map, const ['sort_order', 'sortOrder']),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
  );
}

UploadedMessageFile _uploadedMessageFileFromMap(
  JsonMap map, {
  required String fallbackWorkspaceId,
}) {
  final id = stringField(map, const ['id', 'file_id', 'fileId']);
  final workspaceId = stringField(map, const [
    'workspace_id',
    'workspaceId',
  ], fallback: fallbackWorkspaceId);
  return UploadedMessageFile(
    id: id,
    name: stringField(map, const [
      'name',
      'file_name',
      'original_name',
      'originalName',
    ], fallback: 'file'),
    mimeType: stringField(map, const [
      'mime_type',
      'mimeType',
    ], fallback: 'application/octet-stream'),
    byteSize: intField(map, const ['byte_size', 'byteSize', 'size']),
    downloadPath: stringField(map, const [
      'download_url',
      'downloadUrl',
      'url',
    ], fallback: _downloadPathFallback(workspaceId, id)),
    status: stringField(map, const ['status'], fallback: 'ready'),
    createdAt: dateTimeField(map, const ['created_at', 'createdAt']),
    thumbnailUrl: nullableStringField(map, const [
      'thumbnail_url',
      'thumbnailUrl',
    ]),
    width: positiveIntField(map, const ['width']),
    height: positiveIntField(map, const ['height']),
    durationMs: positiveIntField(map, const ['duration_ms', 'durationMs']),
  );
}

String _downloadPathFallback(String workspaceId, String fileId) {
  if (workspaceId.isEmpty || fileId.isEmpty) {
    return '';
  }
  return '/api/v1/workspaces/${_e(workspaceId)}/files/${_e(fileId)}/download';
}

String _e(String value) => Uri.encodeComponent(value);

MessageReactionSummary _reactionFromMap(JsonMap map) {
  return MessageReactionSummary(
    emoji: stringField(map, const ['emoji']),
    count: intField(map, const ['count']),
    reactedByMe: boolField(map, const ['reacted_by_me', 'reactedByMe']),
  );
}

String? _channelIdOfRoom(String room) {
  const marker = ':channel:';
  final index = room.indexOf(marker);
  if (index < 0) return null;
  final channelId = room.substring(index + marker.length);
  return channelId.isEmpty ? null : channelId;
}

String _roomFor(String workspaceId, String channelId) {
  if (channelId.trim().isEmpty) {
    return 'workspace:$workspaceId:user-events';
  }
  return 'workspace:$workspaceId:channel:$channelId';
}

String _orderTicketsRoomFor(String workspaceId) {
  return 'workspace:${workspaceId.trim()}:order-tickets';
}

String _heartbeatRoom(String workspaceId) {
  final normalized = workspaceId.trim();
  return normalized.isEmpty
      ? 'workspace:heartbeat'
      : 'workspace:$normalized:heartbeat';
}

String _channelIdFromRoom(String? room) {
  final parts = room?.trim().split(':') ?? const <String>[];
  if (parts.length == 4 && parts[0] == 'workspace' && parts[2] == 'channel') {
    return parts[3].trim();
  }
  return '';
}

/// Loại sự kiện và phòng phát (máy chủ gắn `room` vào mỗi sự kiện gửi theo
/// phòng; sự kiện riêng của kết nối như `pong` không có).
(String, String?) _socketEnvelope(Object? data) {
  try {
    final decoded = switch (data) {
      final String value => jsonDecode(value),
      final List<int> value => jsonDecode(utf8.decode(value)),
      final Map value => value,
      _ => null,
    };
    final map = jsonMap(decoded);
    final room = nullableStringField(map, const ['room'])?.trim();
    return (
      stringField(map, const ['type']),
      room == null || room.isEmpty ? null : room,
    );
  } on Object {
    return ('', null);
  }
}
