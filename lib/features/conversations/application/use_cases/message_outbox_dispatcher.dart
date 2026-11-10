import 'dart:async';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_realtime_event.dart';
import '../../domain/entities/message_outbox_item.dart';
import '../../domain/repositories/message_outbox_repository.dart';

/// Gửi một tin chờ lên máy chủ (vẫn kèm `client_message_id` /
/// `Idempotency-Key` như cũ để gửi lại không tạo tin trùng).
typedef SendOutboxMessage =
    Future<Result<ChatMessage>> Function(MessageOutboxItem item);

/// Gắn một tệp đã tải lên vào tin vừa gửi.
typedef AttachOutboxFile =
    Future<Result<MessageAttachment>> Function(
      MessageOutboxItem item,
      ChatMessage message,
      MessageOutboxAttachment attachment,
    );

/// Tải nốt một tệp của tin chờ (nén video nếu cần). [onProgress] nhận 0..1.
typedef UploadOutboxFile =
    Future<Result<UploadedMessageFile>> Function(
      MessageOutboxItem item,
      MessageOutboxPendingUpload upload,
      void Function(double progress) onProgress,
    );

enum MessageOutboxDispatchPhase {
  /// Tin đang chờ tải nốt tệp đính kèm (xem `progress` của bản cập nhật).
  uploading,

  /// Tin đang được gửi.
  sending,

  /// Tin chưa gửi vì tin tạo trước nó trong cùng hội thoại chưa gửi được.
  queued,

  /// Gửi lỗi; tin vẫn nằm trong hàng chờ.
  failed,

  /// Đã gửi, tin đã ra khỏi hàng chờ.
  sent,
}

/// Trạng thái mới của một tin chờ, để phòng chat đang mở cập nhật giao diện.
final class MessageOutboxDispatchUpdate {
  const MessageOutboxDispatchUpdate({
    required this.item,
    required this.phase,
    this.message,
    this.error,
    this.failureKind,
    this.progress,
  });

  /// Bản tin chờ mới nhất đã lưu (với [MessageOutboxDispatchPhase.sent] là bản
  /// vừa bị xoá khỏi hàng chờ).
  final MessageOutboxItem item;
  final MessageOutboxDispatchPhase phase;

  /// Tin máy chủ trả về (đã gửi, hoặc gửi được nhưng gắn tệp lỗi).
  final ChatMessage? message;
  final String? error;
  final FailureKind? failureKind;

  /// Tiến độ tải tệp 0..1 (chỉ với [MessageOutboxDispatchPhase.uploading]).
  final double? progress;

  bool get isFailed => phase == MessageOutboxDispatchPhase.failed;
}

final class MessageOutboxChannelDrainResult {
  const MessageOutboxChannelDrainResult({
    this.updates = const {},
    this.blockedByTransientFailure = false,
    this.connectivityLost = false,
  });

  /// Kết quả cuối của từng tin đã xử lý trong lượt này, theo `item.id`.
  final Map<String, MessageOutboxDispatchUpdate> updates;

  /// Có tin lỗi tạm thời (mạng, máy chủ bận...) nên các tin sau phải chờ.
  final bool blockedByTransientFailure;

  /// Lỗi mạng / hết giờ / máy chủ đã đổi: không cần thử các hội thoại khác.
  final bool connectivityLost;

  MessageOutboxDispatchUpdate? get firstFailure {
    for (final update in updates.values) {
      if (update.isFailed) return update;
    }
    return null;
  }
}

/// Bộ gửi lại tin chờ cho TOÀN APP (không chỉ phòng đang mở).
///
/// - Kích hoạt khi mở app / về foreground, khi WebSocket nối lại, khi có mạng
///   lại, và khi phòng chat gửi tin mới.
/// - Trong mỗi hội thoại gửi đúng thứ tự tạo; một tin lỗi tạm thời thì các tin
///   sau đợi (không vượt lên trước).
/// - Mọi lượt gửi của cùng một hội thoại chạy nối tiếp và đọc lại hàng chờ
///   trước từng tin, nên hai lần kích hoạt chồng nhau không gửi trùng.
final class MessageOutboxDispatcher {
  MessageOutboxDispatcher({
    required MessageOutboxRepository repository,
    required SendOutboxMessage sendMessage,
    required AttachOutboxFile attachFile,
    UploadOutboxFile? uploadFile,
    bool Function()? canCreateUserContent,
    List<Duration> autoRetryDelays = defaultAutoRetryDelays,
    DateTime Function()? now,
  }) : _repository = repository,
       _sendMessage = sendMessage,
       _attachFile = attachFile,
       _uploadFile = uploadFile,
       _canCreateUserContent = canCreateUserContent ?? _alwaysAllowed,
       _autoRetryDelays = autoRetryDelays,
       _now = now ?? _utcNow;

  static const defaultAutoRetryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  static const serverChangedError =
      'Server đã thay đổi; tin nhắn chưa được gửi.';

  final MessageOutboxRepository _repository;
  final SendOutboxMessage _sendMessage;
  final AttachOutboxFile _attachFile;
  // ignore: unused_field
  final UploadOutboxFile? _uploadFile;
  final bool Function() _canCreateUserContent;
  final List<Duration> _autoRetryDelays;
  final DateTime Function() _now;

  final _updates = StreamController<MessageOutboxDispatchUpdate>.broadcast();
  final _channelTails = <String, Future<void>>{};
  final _workspaceRuns = <String, Future<void>>{};
  final _workspaceRerunRequested = <String>{};
  final _autoRetryTimers = <String, Timer>{};
  final _autoRetryAttempts = <String, int>{};
  bool _disposed = false;
  bool _autoRetryPaused = false;

  Stream<MessageOutboxDispatchUpdate> get updates => _updates.stream;

  /// Gửi lại mọi tin chờ của workspace. Gọi chồng nhau thì dùng chung lượt
  /// đang chạy, và chạy thêm đúng một lượt sau đó để nhặt tin mới thêm vào.
  Future<void> drainWorkspace(String workspaceId) {
    final normalized = workspaceId.trim();
    if (_disposed || normalized.isEmpty) return Future<void>.value();
    _autoRetryPaused = false;
    final running = _workspaceRuns[normalized];
    if (running != null) {
      _workspaceRerunRequested.add(normalized);
      return running;
    }
    _autoRetryTimers.remove(normalized)?.cancel();
    final run = _runWorkspace(normalized);
    _workspaceRuns[normalized] = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_workspaceRuns[normalized], run)) {
          _workspaceRuns.remove(normalized);
        }
      }),
    );
    return run;
  }

  /// Gửi tin chờ của một hội thoại theo thứ tự tạo (phòng chat vừa gửi tin
  /// mới hoặc người dùng bấm gửi lại).
  Future<MessageOutboxChannelDrainResult> drainChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    final ws = workspaceId.trim();
    final channel = channelId.trim();
    if (_disposed || ws.isEmpty || channel.isEmpty) {
      return const MessageOutboxChannelDrainResult();
    }
    final result = await _drainChannelSerially(ws, channel);
    if (result.blockedByTransientFailure) {
      _scheduleAutoRetry(ws);
    }
    return result;
  }

  /// Sự kiện realtime của luồng người dùng: WebSocket nối lại (= có mạng lại)
  /// thì gửi lại tin chờ của cả workspace. Trả `true` nếu đã kích hoạt.
  bool handleRealtimeEvent(ConversationRealtimeEvent event) {
    if (event.type != ConversationRealtimeEventType.reconnected ||
        event.channelId.trim().isNotEmpty) {
      return false;
    }
    unawaited(drainWorkspace(event.workspaceId));
    return true;
  }

  /// App vào nền: không tự thử lại theo hẹn giờ (lần mở lại app sẽ kích hoạt).
  void pauseAutoRetry() {
    _autoRetryPaused = true;
    for (final timer in _autoRetryTimers.values) {
      timer.cancel();
    }
    _autoRetryTimers.clear();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    pauseAutoRetry();
    unawaited(_updates.close());
  }

  Future<void> _runWorkspace(String workspaceId) async {
    var transientFailure = false;
    do {
      _workspaceRerunRequested.remove(workspaceId);
      if (_disposed || !_canCreateUserContent()) {
        return;
      }
      transientFailure = false;
      final List<MessageOutboxItem> items;
      try {
        items = await _repository.listWorkspace(workspaceId: workspaceId);
      } on Object {
        transientFailure = true;
        break;
      }
      for (final channelId in _channelsInCreationOrder(items)) {
        if (_disposed) return;
        final result = await _drainChannelSerially(workspaceId, channelId);
        if (result.blockedByTransientFailure) {
          transientFailure = true;
        }
        if (result.connectivityLost) {
          break;
        }
      }
    } while (_workspaceRerunRequested.contains(workspaceId) && !_disposed);
    if (transientFailure) {
      _scheduleAutoRetry(workspaceId);
    } else {
      _autoRetryAttempts.remove(workspaceId);
    }
  }

  Future<MessageOutboxChannelDrainResult> _drainChannelSerially(
    String workspaceId,
    String channelId,
  ) {
    final key = '$workspaceId\u0000$channelId';
    final previous = _channelTails[key] ?? Future<void>.value();
    final completer = Completer<MessageOutboxChannelDrainResult>();
    final next = previous.then((_) async {
      try {
        completer.complete(await _drainChannel(workspaceId, channelId));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _channelTails[key] = next;
    unawaited(
      next.whenComplete(() {
        if (identical(_channelTails[key], next)) {
          _channelTails.remove(key);
        }
      }),
    );
    return completer.future;
  }

  Future<MessageOutboxChannelDrainResult> _drainChannel(
    String workspaceId,
    String channelId,
  ) async {
    final updates = <String, MessageOutboxDispatchUpdate>{};
    final handled = <String>{};
    var blocked = false;
    var connectivityLost = false;
    while (!_disposed) {
      if (!_canCreateUserContent()) break;
      final List<MessageOutboxItem> pending;
      try {
        // Đọc lại trước từng tin: tin vừa gửi xong đã bị xoá, tin mới thêm
        // trong lúc chạy cũng được gửi theo đúng thứ tự.
        pending = sortOutboxItemsInCreationOrder(
          await _repository.list(
            workspaceId: workspaceId,
            channelId: channelId,
          ),
        ).where((item) => !handled.contains(item.id)).toList(growable: false);
      } on Object {
        blocked = true;
        break;
      }
      if (pending.isEmpty) break;
      final item = pending.first;
      handled.add(item.id);
      if (blocked) {
        // Giữ thứ tự: tin sau không vượt lên trước tin trước còn lỗi tạm thời.
        if (item.isSending) {
          final queued = item.copyWith(
            status: MessageOutboxStatus.queued,
            updatedAt: _now(),
          );
          await _saveQuietly(queued);
          _emit(
            MessageOutboxDispatchUpdate(
              item: queued,
              phase: MessageOutboxDispatchPhase.queued,
            ),
          );
        }
        continue;
      }
      final update = await _dispatch(item);
      updates[item.id] = update;
      if (update.isFailed && _isTransient(update.failureKind)) {
        blocked = true;
        if (_isConnectivityFailure(update)) {
          connectivityLost = true;
        }
      }
    }
    return MessageOutboxChannelDrainResult(
      updates: updates,
      blockedByTransientFailure: blocked,
      connectivityLost: connectivityLost,
    );
  }

  Future<MessageOutboxDispatchUpdate> _dispatch(MessageOutboxItem item) async {
    final sending = item.copyWith(
      status: MessageOutboxStatus.sending,
      attemptCount: item.attemptCount + 1,
      updatedAt: _now(),
    );
    try {
      await _repository.upsert(sending);
      _emit(
        MessageOutboxDispatchUpdate(
          item: sending,
          phase: MessageOutboxDispatchPhase.sending,
        ),
      );
      if (!await _repository.canDispatch(sending) || _disposed) {
        return _fail(sending, serverChangedError, FailureKind.cancelled);
      }
      final result = await _sendMessage(sending);
      switch (result) {
        case Success<ChatMessage>(value: final message):
          final attached = <MessageAttachment>[];
          final attachments = [...sending.attachments]
            ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
          for (final attachment in attachments) {
            if (_disposed || !await _repository.canDispatch(sending)) {
              return _fail(sending, serverChangedError, FailureKind.cancelled);
            }
            final attachResult = await _attachFile(
              sending,
              message,
              attachment,
            );
            switch (attachResult) {
              case Success<MessageAttachment>(value: final value):
                attached.add(value);
              case FailureResult<MessageAttachment>(failure: final failure):
                return _fail(
                  sending,
                  failure.message,
                  failure.kind,
                  message: message,
                );
            }
          }
          await _repository.delete(
            workspaceId: sending.workspaceId,
            channelId: sending.channelId,
            itemId: sending.id,
          );
          final update = MessageOutboxDispatchUpdate(
            item: sending,
            phase: MessageOutboxDispatchPhase.sent,
            message: attached.isEmpty
                ? message
                : message.copyWith(attachments: attached),
          );
          _emit(update);
          return update;
        case FailureResult<ChatMessage>(failure: final failure):
          return _fail(sending, failure.message, failure.kind);
      }
    } on Object {
      return _fail(
        sending,
        'Không thể gửi tin nhắn lúc này.',
        FailureKind.unknown,
      );
    }
  }

  Future<MessageOutboxDispatchUpdate> _fail(
    MessageOutboxItem sending,
    String error,
    FailureKind kind, {
    ChatMessage? message,
  }) async {
    final failed = sending.copyWith(
      status: MessageOutboxStatus.failed,
      lastError: error,
      updatedAt: _now(),
    );
    await _saveQuietly(failed);
    final update = MessageOutboxDispatchUpdate(
      item: failed,
      phase: MessageOutboxDispatchPhase.failed,
      message: message,
      error: error,
      failureKind: kind,
    );
    _emit(update);
    return update;
  }

  Future<void> _saveQuietly(MessageOutboxItem item) async {
    try {
      await _repository.upsert(item);
    } on Object {
      // Trạng thái trên đĩa sẽ được sửa ở lượt gửi sau.
    }
  }

  void _emit(MessageOutboxDispatchUpdate update) {
    if (!_updates.isClosed) {
      _updates.add(update);
    }
  }

  void _scheduleAutoRetry(String workspaceId) {
    if (_disposed || _autoRetryPaused || _autoRetryDelays.isEmpty) return;
    if (_autoRetryTimers.containsKey(workspaceId)) return;
    final attempt = _autoRetryAttempts[workspaceId] ?? 0;
    final delay =
        _autoRetryDelays[attempt.clamp(0, _autoRetryDelays.length - 1)];
    _autoRetryAttempts[workspaceId] = attempt + 1;
    _autoRetryTimers[workspaceId] = Timer(delay, () {
      _autoRetryTimers.remove(workspaceId);
      unawaited(drainWorkspace(workspaceId));
    });
  }
}

/// Thứ tự tạo tin: `createdAt`, trùng thì giữ thứ tự đã lưu (thứ tự thêm vào).
List<MessageOutboxItem> sortOutboxItemsInCreationOrder(
  List<MessageOutboxItem> items,
) {
  final indexed = [
    for (var index = 0; index < items.length; index += 1) (index, items[index]),
  ];
  indexed.sort((left, right) {
    final byTime = left.$2.createdAt.compareTo(right.$2.createdAt);
    return byTime != 0 ? byTime : left.$1.compareTo(right.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

Iterable<String> _channelsInCreationOrder(List<MessageOutboxItem> items) {
  final channels = <String>{};
  for (final item in sortOutboxItemsInCreationOrder(items)) {
    final channelId = item.channelId.trim();
    if (channelId.isNotEmpty) channels.add(channelId);
  }
  return channels;
}

bool _isTransient(FailureKind? kind) {
  return switch (kind) {
    FailureKind.validation ||
    FailureKind.forbidden ||
    FailureKind.notFound ||
    FailureKind.conflict ||
    FailureKind.decoding => false,
    _ => true,
  };
}

bool _isConnectivityFailure(MessageOutboxDispatchUpdate update) {
  return update.failureKind == FailureKind.network ||
      update.failureKind == FailureKind.timeout ||
      update.error == MessageOutboxDispatcher.serverChangedError;
}

bool _alwaysAllowed() => true;

DateTime _utcNow() => DateTime.now().toUtc();
