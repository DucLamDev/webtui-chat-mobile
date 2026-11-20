import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/ide_errors.dart';
import '../domain/ide_session_state.dart' show ideJsonInt;
import 'ide_connection.dart';

/// Một đoạn chữ chạy dần (`out`) của thao tác.
final class IdeOut {
  const IdeOut(this.req, this.seq, this.text);

  final String req;
  final int seq;
  final String text;
}

/// Yêu cầu xác nhận bằng khoá trong chip (`need_step`).
final class IdeStepRequest {
  const IdeStepRequest({
    required this.stream,
    required this.req,
    required this.challenge,
    required this.summary,
    required this.op,
    required this.args,
  });

  final String stream;
  final String req;
  final String challenge;
  final String summary;
  final String op;
  final Object? args;
}

/// Trả chữ ký (base64 DER) hoặc `null` khi người dùng huỷ. Ném
/// [IdeStepFailed] nếu không ký được.
typedef IdeStepHandler = Future<String?> Function(IdeStepRequest request);

/// Nơi nhận khúc tệp tải về.
abstract interface class IdeFileSink {
  void onMeta(Map<String, Object?> meta);
  Future<void> add(List<int> bytes);
  Future<void> close({required bool ok});
}

final class IdeDownloadResult {
  const IdeDownloadResult({
    required this.name,
    required this.size,
    required this.mime,
    required this.sha256,
  });

  final String name;
  final int size;
  final String mime;
  final String sha256;
}

/// Một yêu cầu đang chạy: xem chữ chạy dần, huỷ, chờ kết quả.
final class IdeCall {
  IdeCall._(this.req, this._result, this._out, this._cancel);

  final String req;
  final Future<Object?> _result;
  final Stream<IdeOut> _out;
  final void Function() _cancel;

  Future<Object?> get result => _result;
  Stream<IdeOut> get out => _out;
  void cancel() => _cancel();
}

class _Pending {
  _Pending(this.req, this.op, this.args);

  final String req;
  final String op;
  final Object? args;
  final completer = Completer<Object?>();
  final out = StreamController<IdeOut>.broadcast();
  Timer? timer;
  Duration timeout = Duration.zero;
  bool awaitingStep = false;

  // tải về
  IdeFileSink? sink;
  Map<String, Object?>? meta;
  _DigestSink? hash;
  ByteConversionSink? hashInput;
  int received = 0;
  Future<void> chain = Future<void>.value();

  // tải lên
  Completer<void>? putReady;
  final Map<int, Completer<void>> acks = {};
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// RPC trên stream `rpc`: `req` là `r_<số tăng>`, mỗi yêu cầu có hạn chờ
/// riêng, huỷ gửi `cancel`, `need_step` giao [IdeStepHandler], lỗi `code` ném
/// lớp [IdeException] có kiểu. Mất kết nối thì mọi yêu cầu đang chờ báo
/// [IdeOffline] và KHÔNG được gửi lại.
final class IdeRpcClient {
  IdeRpcClient(
    this._connection, {
    this.stepHandler,
    this.defaultTimeout = const Duration(seconds: 30),
    this.maxUnackedChunks = 4,
    this.chunkSize = 192 * 1024,
  }) {
    _frameSub = _connection.rpcFrames.listen(_onFrame);
    _lostSub = _connection.rpcLost.listen((_) => _failAll(const IdeOffline()));
  }

  final IdeConnection _connection;
  final IdeStepHandler? stepHandler;
  final Duration defaultTimeout;
  final int maxUnackedChunks;

  /// Byte thô mỗi khúc tải lên (base64 ≤ 256 KB).
  final int chunkSize;

  late final StreamSubscription<Map<String, Object?>> _frameSub;
  late final StreamSubscription<void> _lostSub;
  final _pending = <String, _Pending>{};
  int _counter = 0;

  String _nextReq() => 'r_${++_counter}';

  /// Gọi một thao tác, chờ `result`.
  Future<Object?> call(
    String op,
    Map<String, Object?> args, {
    Duration? timeout,
  }) => start(op, args, timeout: timeout).result;

  /// Như [call] nhưng trả [IdeCall] để xem chữ chạy dần (`out`) và huỷ.
  IdeCall start(String op, Map<String, Object?> args, {Duration? timeout}) =>
      _start(op, args, timeout: timeout);

  IdeCall _start(
    String op,
    Map<String, Object?> args, {
    Duration? timeout,
    void Function(_Pending)? setup,
  }) {
    final req = _nextReq();
    final pending = _Pending(req, op, args)
      ..timeout = timeout ?? defaultTimeout;
    setup?.call(pending);
    // Dự phòng: hoàn thành lỗi mà không ai nghe `result` vẫn không bị coi là
    // lỗi chưa bắt.
    unawaited(pending.completer.future.then((_) {}, onError: (_) {}));
    if (!_connection.sendRpc({
      'type': 'op',
      'req': req,
      'op': op,
      'args': args,
    })) {
      pending.completer.completeError(const IdeOffline());
      pending.out.close();
      return IdeCall._(
        req,
        pending.completer.future,
        pending.out.stream,
        () {},
      );
    }
    _pending[req] = pending;
    _armTimer(pending);
    return IdeCall._(
      req,
      pending.completer.future,
      pending.out.stream,
      () => cancel(req),
    );
  }

  void _armTimer(_Pending p) {
    p.timer?.cancel();
    p.timer = Timer(p.timeout, () {
      if (_pending.containsKey(p.req)) {
        _connection.sendRpc({'type': 'cancel', 'req': p.req});
        _finish(p, error: IdeTimeout('Quá hạn chờ ${p.op}.'));
      }
    });
  }

  /// Huỷ một yêu cầu: gửi `cancel`, báo [IdeCancelled].
  void cancel(String req) {
    final p = _pending[req];
    if (p == null) return;
    _connection.sendRpc({'type': 'cancel', 'req': req});
    _finish(p, error: const IdeCancelled());
  }

  void _finish(_Pending p, {Object? data, IdeException? error}) {
    if (_pending.remove(p.req) == null) return;
    p.timer?.cancel();
    final sink = p.sink;
    if (sink != null) {
      unawaited(sink.close(ok: error == null).catchError((_) {}));
    }
    for (final c in p.acks.values) {
      if (!c.isCompleted) c.completeError(error ?? const IdeCancelled());
    }
    p.acks.clear();
    if (p.putReady != null && !p.putReady!.isCompleted) {
      p.putReady!.completeError(error ?? const IdeCancelled());
    }
    if (!p.completer.isCompleted) {
      if (error != null) {
        p.completer.completeError(error);
      } else {
        p.completer.complete(data);
      }
    }
    unawaited(p.out.close());
  }

  void _failAll(IdeException error) {
    for (final p in _pending.values.toList()) {
      _finish(p, error: error);
    }
  }

  void _onFrame(Map<String, Object?> frame) {
    final req = frame['req'];
    if (req is! String) return;
    final p = _pending[req];
    if (p == null) return;
    switch (frame['type']) {
      case 'result':
        if (frame['ok'] == true) {
          _finish(p, data: frame['data']);
        } else {
          final err = frame['error'];
          final map = err is Map ? err : const {};
          _finish(
            p,
            error: IdeException.fromCode(
              map['code'] is String ? map['code'] as String : null,
              map['message'] is String ? map['message'] as String : null,
              hint: map['hint'] is String ? map['hint'] as String : null,
            ),
          );
        }
      case 'out':
        final seq = frame['seq'];
        final text = frame['text'];
        if (text is String && !p.out.isClosed) {
          p.out.add(IdeOut(req, ideJsonInt(seq) ?? 0, text));
        }
        // Có chữ chạy dần: thao tác còn sống, gia hạn.
        _armTimer(p);
      case 'need_step':
        unawaited(_onNeedStep(p, frame));
      case 'file_meta':
        p.meta = Map<String, Object?>.from(frame);
        p.sink?.onMeta(p.meta!);
      case 'file_chunk':
        _onChunk(p, frame);
      case 'file_end':
        _onFileEnd(p, frame);
      case 'put_ready':
        if (p.putReady != null && !p.putReady!.isCompleted) {
          p.putReady!.complete();
        }
      case 'file_ack':
        final seq = ideJsonInt(frame['seq']);
        if (seq != null) p.acks.remove(seq)?.complete();
    }
  }

  Future<void> _onNeedStep(_Pending p, Map<String, Object?> frame) async {
    // IDE gửi lại need_step khi đang hỏi: bỏ qua, không mở thêm hộp xác nhận.
    if (p.awaitingStep) return;
    final handler = stepHandler;
    final challenge = frame['challenge'];
    if (handler == null || challenge is! String) {
      _connection.sendRpc({'type': 'cancel', 'req': p.req});
      _finish(p, error: const IdeStepFailed('Máy này chưa sẵn sàng xác nhận.'));
      return;
    }
    p.awaitingStep = true;
    p.timer?.cancel();
    try {
      final sig = await handler(
        IdeStepRequest(
          stream: _connection.rpcStreamId,
          req: p.req,
          challenge: challenge,
          summary: frame['summary'] is String
              ? frame['summary']! as String
              : '',
          op: p.op,
          args: p.args,
        ),
      );
      if (!_pending.containsKey(p.req)) return;
      if (sig == null) {
        _connection.sendRpc({'type': 'cancel', 'req': p.req});
        _finish(p, error: const IdeCancelled());
        return;
      }
      p.awaitingStep = false;
      _connection.sendRpc({'type': 'step', 'req': p.req, 'sig': sig});
      _armTimer(p);
    } on IdeException catch (error) {
      _connection.sendRpc({'type': 'cancel', 'req': p.req});
      _finish(p, error: error);
    } on Object {
      _connection.sendRpc({'type': 'cancel', 'req': p.req});
      _finish(p, error: const IdeStepFailed());
    }
  }

  // ---- tải về theo khúc ----

  /// Tải tệp: gọi [op] (vd. `files.get`), nhận khúc vào [sink], báo nhận từng
  /// khúc, kiểm sha256 ở `file_end`. Giữ kết nối khi app ra nền.
  Future<IdeDownloadResult> download(
    String op,
    Map<String, Object?> args, {
    required IdeFileSink sink,
    Duration? timeout,
  }) async {
    _connection.beginTransfer();
    try {
      final digestSink = _DigestSink();
      final call = _start(
        op,
        args,
        timeout: timeout ?? const Duration(minutes: 5),
        setup: (p) {
          p.sink = sink;
          p.hash = digestSink;
          p.hashInput = sha256.startChunkedConversion(digestSink);
        },
      );
      final value = await call.result;
      return value as IdeDownloadResult;
    } finally {
      _connection.endTransfer();
    }
  }

  void _onChunk(_Pending p, Map<String, Object?> frame) {
    final sink = p.sink;
    final data = frame['data'];
    final seq = ideJsonInt(frame['seq']);
    if (sink == null || data is! String || seq == null) return;
    final List<int> bytes;
    try {
      bytes = base64Decode(data);
    } on FormatException {
      _connection.sendRpc({'type': 'cancel', 'req': p.req});
      _finish(p, error: const IdeError('bad_request', 'Khúc tệp hỏng.'));
      return;
    }
    // Ghi tuần tự: mỗi khúc chờ khúc trước xong rồi mới báo nhận.
    p.chain = p.chain
        .then((_) async {
          if (!_pending.containsKey(p.req)) return;
          p.hashInput?.add(bytes);
          p.received += bytes.length;
          await sink.add(bytes);
          _connection.sendRpc({'type': 'file_ack', 'req': p.req, 'seq': seq});
          _armTimer(p);
        })
        .catchError((Object _) {
          _connection.sendRpc({'type': 'cancel', 'req': p.req});
          _finish(p, error: const IdeError('io', 'Không ghi được tệp.'));
        });
  }

  void _onFileEnd(_Pending p, Map<String, Object?> frame) {
    p.chain = p.chain.then((_) {
      if (!_pending.containsKey(p.req)) return;
      p.hashInput?.close();
      final actual = p.hash?.value?.toString() ?? '';
      final expected = '${frame['sha256'] ?? ''}'.toLowerCase();
      final meta = p.meta ?? const {};
      final size = meta['size'];
      if (expected.isEmpty || actual != expected) {
        _finish(
          p,
          error: const IdeError('hash_mismatch', 'Tệp tải về bị lỗi.'),
        );
        return;
      }
      if (size is num && ideJsonInt(size) != p.received) {
        _finish(p, error: const IdeError('size_mismatch', 'Tệp tải về thiếu.'));
        return;
      }
      final sink = p.sink;
      p.sink = null;
      sink?.close(ok: true);
      _finish(
        p,
        data: IdeDownloadResult(
          name: '${meta['name'] ?? ''}',
          size: p.received,
          mime: '${meta['mime'] ?? ''}',
          sha256: actual,
        ),
      );
    });
  }

  // ---- tải lên theo khúc ----

  /// Tải lên: gọi [op] (vd. `files.put`) rồi chờ `put_ready`, gửi `file_chunk`
  /// (tối đa [maxUnackedChunks] khúc chưa được báo nhận), trả `result`.
  Future<Object?> upload(
    String op,
    Map<String, Object?> args,
    Stream<List<int>> bytes, {
    Duration? timeout,
  }) async {
    _connection.beginTransfer();
    try {
      late _Pending pending;
      final call = _start(
        op,
        args,
        timeout: timeout ?? const Duration(minutes: 5),
        setup: (p) {
          pending = p;
          p.putReady = Completer<void>();
        },
      );
      final resultFuture = call.result;
      try {
        await Future.any([pending.putReady!.future, resultFuture]);
        var seq = 0;
        final digestSink = _DigestSink();
        final hashInput = sha256.startChunkedConversion(digestSink);
        await for (final block in bytes) {
          hashInput.add(block);
          for (var i = 0; i < block.length; i += chunkSize) {
            final end = i + chunkSize < block.length
                ? i + chunkSize
                : block.length;
            while (pending.acks.length >= maxUnackedChunks) {
              await Future.any(pending.acks.values.map((c) => c.future));
            }
            if (!_pending.containsKey(pending.req)) break;
            final ack = Completer<void>();
            ack.future.then((_) {}, onError: (_) {});
            pending.acks[seq] = ack;
            _connection.sendRpc({
              'type': 'file_chunk',
              'req': pending.req,
              'seq': seq,
              'data': base64Encode(block.sublist(i, end)),
            });
            seq++;
            _armTimer(pending);
          }
        }
        hashInput.close();
        // sha256 hex nằm trong `file_end` sau khúc cuối (hợp đồng bổ sung).
        if (_pending.containsKey(pending.req)) {
          _connection.sendRpc({
            'type': 'file_end',
            'req': pending.req,
            'sha256': digestSink.value?.toString() ?? '',
          });
        }
        return await resultFuture;
      } on Object {
        cancel(pending.req);
        rethrow;
      }
    } finally {
      _connection.endTransfer();
    }
  }

  Future<void> dispose() async {
    _failAll(const IdeOffline());
    await _frameSub.cancel();
    await _lostSub.cancel();
  }
}
