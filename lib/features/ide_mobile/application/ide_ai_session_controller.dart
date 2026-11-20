import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/security/secure_key_value_store.dart';
import '../data/ide_channel.dart';
import '../data/ide_connection.dart';
import '../data/ide_rpc_client.dart';
import '../domain/ide_errors.dart';
import '../domain/ide_session_state.dart';

/// Phiên AI cần mở: phiên có sẵn ([sessionKey]) hoặc phiên mới.
final class IdeAiOpenTarget {
  const IdeAiOpenTarget.existing(String this.sessionKey)
    : kind = '',
      root = '',
      worktree = '';

  const IdeAiOpenTarget.create({
    required this.kind,
    required this.root,
    this.worktree = '',
  }) : sessionKey = null;

  final String? sessionKey;
  final String kind;
  final String root;
  final String worktree;

  Map<String, Object?> get openFrame => sessionKey != null
      ? {'type': 'open', 'session_key': sessionKey}
      : {
          'type': 'open',
          'kind': kind,
          'root': root,
          if (worktree.isNotEmpty) 'worktree': worktree,
        };

  @override
  bool operator ==(Object other) =>
      other is IdeAiOpenTarget &&
      other.sessionKey == sessionKey &&
      other.kind == kind &&
      other.root == root &&
      other.worktree == worktree;

  @override
  int get hashCode => Object.hash(sessionKey, kind, root, worktree);
}

enum IdeAiLink {
  connecting,
  live,

  /// Rớt mạng / IDE: đang nối lại cùng `session_key`.
  reconnecting,

  /// Dừng hẳn (`closedReason`): không nối lại.
  closed,
}

/// Lỗi IDE báo (`error`), dùng [seq] để giao diện chỉ hiện một lần.
final class IdeAiProblem {
  const IdeAiProblem(this.seq, this.message, {this.id, this.viewOnly = false});

  final int seq;
  final String message;
  final String? id;
  final bool viewOnly;
}

/// Ảnh chụp trạng thái giao diện cần (đã gộp 60 ms).
final class IdeAiSnapshot {
  const IdeAiSnapshot({
    required this.view,
    this.hasState = false,
    this.revision = 0,
    this.sessionKey = '',
    this.link = IdeAiLink.connecting,
    this.closedReason,
    this.role = const IdeRole(),
    this.hasRoleFrame = false,
    this.clients = 0,
    this.notice,
    this.noticeSeq = 0,
    this.problem,
    this.queued = const {},
  });

  factory IdeAiSnapshot.initial() =>
      IdeAiSnapshot(view: IdeSessionView(const {}));

  final IdeSessionView view;
  final int revision;
  final String sessionKey;
  final IdeAiLink link;
  final String? closedReason;
  final IdeRole role;
  final bool hasRoleFrame;
  final int clients;
  final String? notice;
  final int noticeSeq;
  final IdeAiProblem? problem;

  /// Mã tin IDE đã nhận và xếp hàng chờ.
  final Set<String> queued;

  /// Đã nhận state đầu tiên.
  final bool hasState;

  /// Chưa có state đầu tiên thì cho phép gõ; khi biết chỉ xem thì khoá ô gõ.
  bool get canControl => !hasRoleFrame || role.control;
}

/// Mở một stream `ai`, giữ state (state + patch), gửi lệnh và nối lại khi
/// rớt mạng (hợp đồng mục 4). Gộp thông báo đổi state 60 ms.
class IdeAiSessionController extends StateNotifier<IdeAiSnapshot> {
  IdeAiSessionController({
    required IdeConnection connection,
    required IdeAiOpenTarget target,
    required Future<String> Function() clientId,
    required IdeStepHandler stepHandler,
    this.coalesce = const Duration(milliseconds: 60),
    this.pingEvery = const Duration(seconds: 20),
    this.requestTimeout = const Duration(seconds: 20),
    this.backoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
    ],
    Uuid uuid = const Uuid(),
  }) : _connection = connection,
       _target = target,
       _clientId = clientId,
       _stepHandler = stepHandler,
       _uuid = uuid,
       _sessionKey = target.sessionKey ?? '',
       super(IdeAiSnapshot.initial());

  final IdeConnection _connection;
  final IdeAiOpenTarget _target;
  final Future<String> Function() _clientId;
  final IdeStepHandler _stepHandler;
  final Duration coalesce;
  final Duration pingEvery;
  final Duration requestTimeout;
  final List<Duration> backoff;
  final Uuid _uuid;

  final _session = IdeSessionState();
  IdeChannel? _channel;
  StreamSubscription<Map<String, Object?>>? _sub;
  Timer? _emitTimer;
  Timer? _pingTimer;
  Timer? _retryTimer;
  bool _started = false;
  bool _disposed = false;
  bool _everLive = false;
  bool _resubscribing = false;
  int _attempt = 0;
  int _generation = 0;
  int _seq = 0;
  String _sessionKey;

  IdeRole? _roleFrame;
  int _clients = 0;
  IdeAiLink _link = IdeAiLink.connecting;
  String? _closedReason;
  String? _notice;
  int _noticeSeq = 0;
  IdeAiProblem? _problem;
  final _queued = <String>{};

  /// Khung đã gửi có thể bị IDE giữ chờ xác nhận bằng vân tay.
  final _held = <Map<String, Object?>>[];
  final _waiters = <String, Completer<Map<String, Object?>>>{};

  /// Loại khung gửi lên cần xác nhận khi `irreversible` (lưu lại để ký).
  static const _guardedTypes = {'answer', 'approve_plan'};

  /// Mọi loại khung app được phép gửi (bảng mục 4). Không có `action`.
  static const sendableTypes = {
    'hello',
    'subscribe',
    'claim',
    'send',
    'answer',
    'approve_plan',
    'deepen_plan',
    'interrupt',
    'restart',
    'reset',
    'compact',
    'unqueue',
    'send_now',
    'queue_run',
    'configure',
    'models',
    'change_account',
    'history',
    'load',
    'rewind',
    'redo',
    'search',
    'task_log',
    'stop_task',
    'step',
    'ping',
  };

  String get sessionKey => _sessionKey;
  IdeChannel? get channel => _channel;
  IdeSessionView get view => _session.view;

  /// Mở stream. Gọi một lần.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(_open());
  }

  Future<void> _open() async {
    if (_disposed || _link == IdeAiLink.closed) return;
    final generation = ++_generation;
    _setLink(_everLive ? IdeAiLink.reconnecting : IdeAiLink.connecting);
    _connection.start();
    final first = _sessionKey.isNotEmpty
        ? {'type': 'open', 'session_key': _sessionKey}
        : _target.openFrame;
    final IdeChannel channel;
    try {
      channel = await _connection.openStream(IdeStreamKind.ai, first);
    } on IdeHandshakeException catch (error) {
      if (_disposed || generation != _generation) return;
      if (error.fatal) {
        _closeFor(error.reason);
      } else {
        _scheduleRetry();
      }
      return;
    } on IdeBusy catch (error) {
      if (_disposed || generation != _generation) return;
      _setProblem(
        error.message.isEmpty ? 'Đã mở quá nhiều phiên.' : error.message,
      );
      _closeFor('limit');
      return;
    } on Object {
      if (_disposed || generation != _generation) return;
      _scheduleRetry();
      return;
    }
    if (_disposed || generation != _generation) {
      await channel.close();
      return;
    }
    _channel = channel;
    _resubscribing = false;
    _sub = channel.frames.listen(_onFrame);
    unawaited(channel.done.then((close) => _onClosed(channel, close)));
    final clientId = await _clientId();
    if (_disposed || !identical(_channel, channel)) return;
    _sendRaw({'type': 'hello', 'clientId': clientId});
    _sendRaw({'type': 'subscribe', 'patch': 1});
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingEvery, (_) => _sendRaw({'type': 'ping'}));
  }

  void _onClosed(IdeChannel channel, IdeChannelClose close) {
    if (!identical(_channel, channel)) return;
    _channel = null;
    _pingTimer?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    _failWaiters('Mất kết nối với IDE.');
    if (_disposed || close.reason == 'local') return;
    if (close.refused || close.reason == 'session_revoked') {
      _closeFor(close.reason);
      return;
    }
    _scheduleRetry();
  }

  void _closeFor(String reason) {
    _retryTimer?.cancel();
    _closedReason = reason;
    _setLink(IdeAiLink.closed);
  }

  void _scheduleRetry() {
    if (_disposed || _link == IdeAiLink.closed) return;
    _setLink(IdeAiLink.reconnecting);
    final delay =
        backoff[_attempt < backoff.length ? _attempt : backoff.length - 1];
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(_open()));
  }

  /// Nối lại ngay (nút Thử lại).
  void retryNow() {
    if (_disposed || _link != IdeAiLink.reconnecting) return;
    _retryTimer?.cancel();
    _attempt = 0;
    unawaited(_open());
  }

  void _setLink(IdeAiLink link) {
    _link = link;
    if (link == IdeAiLink.live) {
      _everLive = true;
      _attempt = 0;
    }
    _emit();
  }

  // --- nhận khung ---------------------------------------------------------

  void _onFrame(Map<String, Object?> frame) {
    switch (frame['type']) {
      case 'state':
        final raw = frame['state'];
        if (raw is Map) {
          _session.applyState(Map<String, Object?>.from(raw));
          final key = _readKey(frame) ?? _readKey(raw);
          if (key != null) _sessionKey = key;
          _resubscribing = false;
          if (_link != IdeAiLink.live) _setLink(IdeAiLink.live);
          _emit();
        }
      case 'patch':
        final result = _session.applyPatch(frame);
        if (result == IdePatchResult.needsResubscribe) {
          if (!_resubscribing) {
            _resubscribing = true;
            _sendRaw({'type': 'subscribe', 'patch': 1});
          }
        } else {
          _emit();
        }
      case 'role':
        _roleFrame = IdeRole(
          control: frame['control'] == true,
          free: frame['free'] == true,
          controllerKind: frame['controllerKind'] is String
              ? frame['controllerKind']! as String
              : '',
        );
        _emit();
      case 'clients':
        _clients = ideJsonInt(frame['count']) ?? 0;
        _emit();
      case 'accepted':
        final id = frame['id'];
        if (id is String && frame['queued'] == true) _queued.add(id);
        _emit();
      case 'notice':
        final message = frame['message'];
        if (message is String && message.isNotEmpty) {
          _notice = message;
          _noticeSeq++;
          _emit();
        }
      case 'error':
        _onError(frame);
      case 'history':
        _complete('history', frame);
      case 'search':
        _complete('search:${frame['id']}', frame);
      case 'rewind':
        _complete('rewind:${frame['id']}', frame);
      case 'redo':
        _complete('redo:${frame['id']}', frame);
      case 'task_log':
        _complete('task_log:${frame['id']}', frame);
      case 'need_step':
        unawaited(_onNeedStep(frame));
    }
  }

  static String? _readKey(Map<Object?, Object?> map) {
    for (final name in const ['sessionKey', 'session_key']) {
      final value = map[name];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  void _onError(Map<String, Object?> frame) {
    final message = frame['message'] is String
        ? frame['message']! as String
        : 'IDE báo lỗi.';
    final id = frame['id'] is String ? frame['id']! as String : null;
    final viewOnly = message.contains('VIEW_ONLY');
    // Lời chờ có mã trùng: báo lỗi cho nơi đang chờ, không hiện hai lần.
    for (final key in _waiters.keys.toList()) {
      if (id != null && key.endsWith(':$id')) {
        _waiters.remove(key)!.completeError(IdeError('ide_error', message));
        return;
      }
    }
    _problem = IdeAiProblem(++_seq, message, id: id, viewOnly: viewOnly);
    _emit();
  }

  /// Hộp vân tay đang mở và hàng chờ: mỗi lần chỉ một hộp, mỗi `req` chỉ hỏi một
  /// lần.
  bool _stepOpen = false;
  final _stepQueue = <Map<String, Object?>>[];

  /// `req` đang hỏi vân tay (chờ trong hàng hoặc đang mở hộp). Ký xong thì khung
  /// giữ bị bỏ nên need_step lặp không khớp khung nào; huỷ / lỗi thì gỡ đánh dấu
  /// này, khung giữ còn để người dùng duyệt lại (khung mới thay khung cũ).
  final _stepActive = <String>{};

  Future<void> _onNeedStep(Map<String, Object?> frame) async {
    final req = frame['req'];
    final challenge = frame['challenge'];
    if (_channel == null || req is! String || challenge is! String) return;
    // Chỉ ký khung người dùng đã bấm: `req` phải khớp đúng một khung đang giữ.
    if (_heldFor(req) == null || _stepActive.contains(req)) return;
    _stepActive.add(req);
    _stepQueue.add(frame);
    if (_stepOpen) return;
    _stepOpen = true;
    try {
      while (_stepQueue.isNotEmpty) {
        final next = _stepQueue.removeAt(0);
        try {
          await _runStep(next);
        } finally {
          _stepActive.remove(next['req']);
        }
      }
    } finally {
      _stepOpen = false;
    }
  }

  Future<void> _runStep(Map<String, Object?> frame) async {
    final channel = _channel;
    final req = frame['req']! as String;
    final challenge = frame['challenge']! as String;
    final held = _heldFor(req);
    if (channel == null || held == null) {
      return;
    }
    final type = '${held['type']}';
    final args = Map<String, Object?>.of(held)..remove('type');
    final own = _ownSummary(type, held);
    final theirs = frame['summary'] is String
        ? (frame['summary']! as String).trim()
        : '';
    try {
      final sig = await _stepHandler(
        IdeStepRequest(
          stream: channel.stream,
          req: req,
          challenge: challenge,
          summary: theirs.isEmpty ? own : '$own\nIDE ghi: $theirs',
          op: 'ai.$type',
          args: args,
        ),
      );
      // Huỷ hộp vân tay: chỉ đóng hộp, thẻ vẫn chờ duyệt (không gửi deny),
      // khung giữ còn để lần bấm duyệt sau (khung mới) thay nó.
      if (sig == null) return;
      if (_sendRaw({'type': 'step', 'req': req, 'sig': sig})) {
        // Đã ký xong: bỏ khung khỏi danh sách giữ (lần duyệt mới = khung mới).
        _held.removeWhere((f) => identical(f, held));
      }
    } on IdeException catch (error) {
      _setProblem(
        error.message.isEmpty
            ? 'Không xác nhận được bằng vân tay.'
            : error.message,
      );
    } on Object {
      _setProblem('Không xác nhận được bằng vân tay.');
    }
  }

  /// Tóm tắt app tự dựng từ khung sắp ký (và thẻ duyệt cùng mã), không lấy từ
  /// chữ IDE gửi.
  String _ownSummary(String type, Map<String, Object?> held) {
    if (type == 'approve_plan') {
      final d = held['decisions'];
      final n = d is List ? d.length : (d is Map ? d.length : 0);
      return n > 0 ? 'Duyệt kế hoạch ($n quyết định)' : 'Duyệt kế hoạch';
    }
    if (type != 'answer') return 'Thao tác: $type';
    final decision = held['decision'] == 'allow' ? 'Cho phép' : 'Từ chối';
    final id = held['id'];
    Map<String, Object?>? card;
    for (final a in _session.view.approvals) {
      if (a['id'] == id) card = a;
    }
    var what = '';
    if (card != null) {
      final params = card['params'] is Map
          ? Map<String, Object?>.from(card['params']! as Map)
          : const <String, Object?>{};
      final input = params['input'] is Map
          ? Map<String, Object?>.from(params['input']! as Map)
          : const <String, Object?>{};
      String text(Object? v) => v is String ? v : '';
      what = [
        text(input['command']),
        text(params['command']),
        text(input['file_path']),
        text(params['path']),
      ].firstWhere((e) => e.isNotEmpty, orElse: () => '');
      if (what.isEmpty && card['changes'] is List) {
        final paths = [
          for (final c in card['changes']! as List)
            if (c is Map && c['path'] is String) c['path']! as String,
        ];
        what = paths.join(', ');
      }
    }
    if (what.length > 300) what = '${what.substring(0, 300)}…';
    return what.isEmpty ? '$decision yêu cầu $id' : '$decision: $what';
  }

  /// Khung đang giữ khớp đúng `req`: `a_<mã thẻ>` ↔ khung `answer` mang mã đó;
  /// `plan` ↔ khung `approve_plan` (Đội AI).
  Map<String, Object?>? _heldFor(String req) {
    final matches = <Map<String, Object?>>[];
    if (req == 'plan') {
      matches.addAll(_held.where((f) => f['type'] == 'approve_plan'));
    } else if (req.startsWith('a_')) {
      final id = req.substring(2);
      matches.addAll(
        _held.where((f) => f['type'] == 'answer' && f['id'] == id),
      );
    }
    return matches.length == 1 ? matches.first : null;
  }

  // --- gửi lệnh -----------------------------------------------------------

  bool _sendRaw(Map<String, Object?> frame) {
    // App luôn gửi `type`, không bao giờ `action`: bỏ khung, không ném lỗi.
    if (frame.containsKey('action')) return false;
    return _channel?.send(frame) ?? false;
  }

  /// Gửi một lệnh bảng mục 4. Luôn đặt `type`, không bao giờ `action`.
  bool command(String type, [Map<String, Object?> fields = const {}]) {
    assert(sendableTypes.contains(type), 'Lệnh lạ: $type');
    if (!sendableTypes.contains(type) || fields.containsKey('action')) {
      return false;
    }
    final frame = <String, Object?>{...fields, 'type': type};
    final ok = _sendRaw(frame);
    // Chỉ giữ khung duyệt đã gửi được; gửi lại cùng thẻ / kế hoạch thì thay
    // khung cũ. Loại khác mà IDE đòi need_step thì không khớp khung nào: bỏ qua.
    if (ok && _guardedTypes.contains(type)) {
      if (type == 'answer') {
        _held.removeWhere(
          (f) => f['type'] == 'answer' && f['id'] == frame['id'],
        );
      } else {
        _held.removeWhere((f) => f['type'] == 'approve_plan');
      }
      _held.add(frame);
      if (_held.length > 8) _held.removeAt(0);
    }
    return ok;
  }

  /// Gửi tin; trả mã `m-<uuid>` hoặc `null` khi chưa nối.
  String? send(
    String text, {
    List<Map<String, Object?>> attachments = const [],
    bool now = false,
  }) {
    final id = 'm-${_uuid.v4()}';
    final ok = command('send', {
      'id': id,
      'text': text,
      'attachments': attachments,
      if (now) 'now': true,
    });
    return ok ? id : null;
  }

  void claim() => command('claim', {'take': true});
  void interrupt() => command('interrupt');
  void answer(
    String id, {
    required bool allow,
    Map<String, String>? answers,
    bool deepen = false,
    Object? decisions,
  }) => command('answer', {
    'id': id,
    'decision': allow ? 'allow' : 'deny',
    'answers': ?answers,
    if (deepen) 'deepen': true,
    'decisions': ?decisions,
  });
  void approvePlan({Object? decisions}) =>
      command('approve_plan', {'decisions': ?decisions});
  void deepenPlan() => command('deepen_plan');
  void unqueue(String id) => command('unqueue', {'id': id});
  void sendNow(String id) => command('send_now', {'id': id});
  void queueRun() => command('queue_run');
  void reset() => command('reset');
  void compact() => command('compact');
  void restart(num? since) => command('restart', {'since': ?since});
  void models() => command('models');
  void changeAccount(String account) =>
      command('change_account', {'account': account});
  void load(String id) => command('load', {'id': id});
  void stopTask(String task) => command('stop_task', {'task': task});
  void configure(Map<String, Object?> settings) =>
      command('configure', {'settings': settings});

  // --- yêu cầu có trả lời --------------------------------------------------

  Future<Map<String, Object?>> _ask(
    String type,
    String key,
    Map<String, Object?> fields,
  ) {
    final completer = Completer<Map<String, Object?>>();
    _waiters[key]?.completeError(const IdeCancelled());
    _waiters[key] = completer;
    if (!command(type, fields)) {
      _waiters.remove(key);
      return Future.error(const IdeOffline('Chưa kết nối với IDE.'));
    }
    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _waiters.remove(key);
        throw const IdeTimeout('IDE không trả lời.');
      },
    );
  }

  void _complete(String key, Map<String, Object?> frame) {
    _waiters.remove(key)?.complete(frame);
  }

  void _failWaiters(String message) {
    for (final c in _waiters.values) {
      if (!c.isCompleted) c.completeError(IdeOffline(message));
    }
    _waiters.clear();
  }

  String _reqId() => 'q-${_uuid.v4().substring(0, 8)}';

  /// `history {entries, current}`.
  Future<Map<String, Object?>> history() => _ask('history', 'history', {});

  Future<Map<String, Object?>> search(
    String query, {
    String scope = 'session',
  }) {
    final id = _reqId();
    return _ask('search', 'search:$id', {
      'query': query,
      'scope': scope,
      'id': id,
    });
  }

  Future<Map<String, Object?>> rewind(String message, {required bool dry}) {
    final id = _reqId();
    return _ask('rewind', 'rewind:$id', {
      'message': message,
      'dry': dry,
      'id': id,
    });
  }

  Future<Map<String, Object?>> redo(String? message, {required bool dry}) {
    final id = _reqId();
    return _ask('redo', 'redo:$id', {
      'message': ?message,
      'dry': dry,
      'id': id,
    });
  }

  Future<Map<String, Object?>> taskLog(String task) {
    final id = _reqId();
    return _ask('task_log', 'task_log:$id', {'task': task, 'id': id});
  }

  // --- phát state ra giao diện ----------------------------------------------

  void _setProblem(String message) {
    _problem = IdeAiProblem(++_seq, message);
    _emit();
  }

  void _emit() {
    if (_disposed || _emitTimer != null) return;
    _emitTimer = Timer(coalesce, () {
      _emitTimer = null;
      if (_disposed) return;
      final view = _session.view;
      state = IdeAiSnapshot(
        view: view,
        hasState: _session.hasState,
        revision: _session.revision ?? 0,
        sessionKey: _sessionKey,
        link: _link,
        closedReason: _closedReason,
        role: _roleFrame ?? view.role,
        hasRoleFrame: _roleFrame != null || _session.raw.containsKey('role'),
        clients: _clients,
        notice: _notice,
        noticeSeq: _noticeSeq,
        problem: _problem,
        queued: Set.of(_queued),
      );
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _emitTimer?.cancel();
    _pingTimer?.cancel();
    _retryTimer?.cancel();
    unawaited(_sub?.cancel());
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.close());
    for (final c in _waiters.values) {
      if (!c.isCompleted) c.completeError(const IdeCancelled());
    }
    _waiters.clear();
    super.dispose();
  }
}

/// `mobile-<uuid v4>` cố định theo máy, lưu bằng kho bí mật của app.
final class IdeClientIdStore {
  IdeClientIdStore(this._store, {Uuid uuid = const Uuid()}) : _uuid = uuid;

  final SecureKeyValueStore _store;
  final Uuid _uuid;
  String? _cached;

  Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    final stored = await _store.read(SecureStoreKey.ideClientId);
    if (stored != null && RegExp(r'^mobile-[0-9a-f-]{36}$').hasMatch(stored)) {
      return _cached = stored;
    }
    final fresh = 'mobile-${_uuid.v4()}';
    await _store.write(SecureStoreKey.ideClientId, fresh);
    return _cached = fresh;
  }
}
