import 'dart:async';

import '../../../core/error/failure.dart';
import '../../../core/result/result.dart';
import '../../../l10n/app_strings.dart';
import '../domain/entities/chat_message.dart';
import '../domain/entities/message_sync.dart';
import '../domain/repositories/conversation_repository.dart';
import '../domain/repositories/local_message_repository.dart';
import '../domain/repositories/message_changes_repository.dart';

enum MessageSyncStatus {
  /// Đã hỏi hết phần thay đổi, tin trên máy khớp máy chủ.
  synced,

  /// Máy chủ chưa có API luồng thay đổi (máy chủ cũ): dùng cách tải trang tin
  /// như trước.
  unsupported,

  /// Lỗi (mất mạng, máy chủ lỗi...): tin trên máy vẫn dùng được.
  failed,
}

/// Kết quả một lượt đồng bộ. [upserted] / [deleted] / [clearedAt] là phần đã
/// áp vào máy (kể cả khi lượt bị lỗi giữa chừng, các trang trước đó vẫn đã
/// lưu), để màn đang mở áp cùng thay đổi mà không phải đọc lại.
final class MessageSyncResult {
  const MessageSyncResult({
    required this.status,
    this.failure,
    this.reset = false,
    this.upserted = const [],
    this.deleted = const [],
    this.clearedAt,
  });

  final MessageSyncStatus status;
  final Failure? failure;

  /// Tin trên máy vừa được dựng lại từ đầu (lần đầu, hoặc quá nhiều thay đổi
  /// phải tải lại): đọc lại tin mới nhất từ máy thay vì áp từng thay đổi.
  final bool reset;

  /// Tin mới / đã sửa vừa ghi vào máy.
  final List<ChatMessage> upserted;

  /// Bia mộ (tin đã xoá / thu hồi) vừa xoá khỏi máy.
  final List<ChatMessage> deleted;

  /// Người dùng đã xoá lịch sử tới mốc này: tin tạo trước / bằng mốc đã bị bỏ.
  final DateTime? clearedAt;

  bool get isSynced => status == MessageSyncStatus.synced;
  bool get isUnsupported => status == MessageSyncStatus.unsupported;
}

/// Một đoạn tin đọc được (từ máy và / hoặc máy chủ), xếp CŨ → MỚI.
final class MessageWindow {
  const MessageWindow({required this.messages, required this.hasMore});

  final List<ChatMessage> messages;

  /// Còn tin cũ hơn (trên máy hoặc trên máy chủ).
  final bool hasMore;
}

/// Đồng bộ tin nhắn trên máy với máy chủ (giai đoạn 2 bộ đệm):
/// - [sync]: lần đầu lấy mốc luồng thay đổi TRƯỚC rồi mới tải trang tin mới
///   nhất (không lỡ thay đổi xảy ra giữa hai lần hỏi); các lần sau chỉ hỏi
///   phần thay đổi từ mốc đã lưu.
/// - [prefetchHistory]: chạy ngầm, lưu dần tin cũ tới khoảng 30 ngày.
/// - [loadOlder]: đọc trên máy trước, hết đoạn đã lưu mới hỏi máy chủ và nối
///   dài đoạn đã lưu.
///
/// Tin trên máy luôn là MỘT đoạn liền mạch từ tin mới nhất về tới
/// `oldestCreatedAt`; tin cũ hơn mốc đó không được ghi (tránh "lỗ" khiến cuộn
/// lên tưởng đã đủ tin).
final class MessageSyncService {
  MessageSyncService({
    required LocalMessageRepository local,
    required MessageChangesRepository changes,
    required ConversationRepository messages,
    DateTime Function()? now,
    this.pageSize = 50,
    this.changesPageLimit = 200,
    this.maxChangePages = 25,
    this.prefetchPageSize = 100,
    this.maxPrefetchPages = 20,
    this.prefetchWindow = const Duration(days: 30),
  }) : _local = local,
       _changes = changes,
       _messages = messages,
       _now = now ?? _utcNow;

  final LocalMessageRepository _local;
  final MessageChangesRepository _changes;
  final ConversationRepository _messages;
  final DateTime Function() _now;

  /// Số tin của trang mới nhất khi đồng bộ lần đầu.
  final int pageSize;

  /// Số tin tối đa mỗi trang luồng thay đổi (máy chủ giới hạn 200).
  final int changesPageLimit;

  /// Quá số trang này trong một lượt (lâu không mở, quá nhiều thay đổi): bỏ
  /// tin trên máy của cuộc trò chuyện và đồng bộ lại từ đầu.
  final int maxChangePages;

  /// Tải trước tin cũ: số tin mỗi trang (máy chủ giới hạn 100) và số trang tối
  /// đa mỗi lượt.
  final int prefetchPageSize;
  final int maxPrefetchPages;

  /// Tải trước tới khi tin cũ nhất đã lưu cũ hơn khoảng này.
  final Duration prefetchWindow;

  final Map<String, Future<MessageSyncResult>> _syncs = {};
  final Map<String, Future<void>> _prefetches = {};
  final Map<String, Future<void>> _locks = {};
  final Set<String> _unsupported = {};

  /// Cuộc trò chuyện đã biết máy chủ không hỗ trợ luồng thay đổi (trong phiên
  /// chạy app này).
  bool isUnsupported({required String workspaceId, required String channelId}) {
    return _unsupported.contains(_key(workspaceId, channelId));
  }

  /// [limit] tin mới nhất đã lưu trên máy (đọc ngay khi mở cuộc trò chuyện,
  /// không cần mạng).
  Future<MessageWindow> readLatest({
    required String workspaceId,
    required String channelId,
    int limit = 50,
  }) async {
    try {
      final messages = await _local.readLatest(
        workspaceId: workspaceId,
        channelId: channelId,
        limit: limit,
      );
      final state = await _local.readSyncState(
        workspaceId: workspaceId,
        channelId: channelId,
      );
      return MessageWindow(
        messages: messages,
        hasMore:
            messages.length >= limit || !(state?.reachedBeginning ?? false),
      );
    } on Object {
      return const MessageWindow(messages: [], hasMore: true);
    }
  }

  /// Đồng bộ một cuộc trò chuyện; đang chạy thì trả đúng lượt đang chạy (một
  /// cuộc trò chuyện chỉ một lượt cùng lúc).
  Future<MessageSyncResult> sync({
    required String workspaceId,
    required String channelId,
  }) {
    final key = _key(workspaceId, channelId);
    final running = _syncs[key];
    if (running != null) return running;
    final future = _runSync(workspaceId, channelId).whenComplete(() {
      _syncs.remove(key);
    });
    _syncs[key] = future;
    return future;
  }

  Future<MessageSyncResult> _runSync(
    String workspaceId,
    String channelId,
  ) async {
    final key = _key(workspaceId, channelId);
    final upserted = <String, ChatMessage>{};
    final deleted = <String, ChatMessage>{};
    DateTime? clearedAt;
    var reset = false;

    MessageSyncResult result(MessageSyncStatus status, [Failure? failure]) {
      return MessageSyncResult(
        status: status,
        failure: failure,
        reset: reset,
        upserted: upserted.values.toList(growable: false),
        deleted: deleted.values.toList(growable: false),
        clearedAt: clearedAt,
      );
    }

    // Dựng lại đoạn tin trên máy từ đầu; trả lỗi (null = xong).
    Future<MessageSyncResult?> initialize() async {
      final initialized = await _initialize(workspaceId, channelId);
      switch (initialized) {
        case _InitFailure(:final failure):
          if (failure.kind == FailureKind.notFound) {
            _unsupported.add(key);
            return result(MessageSyncStatus.unsupported, failure);
          }
          return result(MessageSyncStatus.failed, failure);
        case _InitDone(:final page):
          reset = true;
          upserted
            ..clear()
            ..addEntries(
              page.where((m) => !m.isDeleted).map((m) => MapEntry(m.id, m)),
            );
          deleted.clear();
          clearedAt = null;
          return null;
      }
    }

    try {
      var state = await _local.readSyncState(
        workspaceId: workspaceId,
        channelId: channelId,
      );
      if (state?.changeCursor == null) {
        final failed = await initialize();
        if (failed != null) return failed;
        state = await _local.readSyncState(
          workspaceId: workspaceId,
          channelId: channelId,
        );
      }
      var cursor = state?.changeCursor;
      var pages = 0;
      var restarted = false;
      while (cursor != null) {
        if (pages >= maxChangePages) {
          // Quá nhiều thay đổi: tải lại từ đầu thay vì kéo hết luồng. Đã tải
          // lại một lần trong lượt này thì dừng, lần sau đi tiếp từ mốc đã lưu.
          if (restarted) break;
          restarted = true;
          final failed = await _restart(workspaceId, channelId, initialize);
          if (failed != null) return failed;
          cursor = (await _local.readSyncState(
            workspaceId: workspaceId,
            channelId: channelId,
          ))?.changeCursor;
          pages = 0;
          continue;
        }
        final changes = await _changes.listMessageChanges(
          workspaceId: workspaceId,
          channelId: channelId,
          since: cursor,
          limit: changesPageLimit,
        );
        switch (changes) {
          case FailureResult<MessageChangesPage>(:final failure):
            if (failure.kind == FailureKind.notFound) {
              _unsupported.add(key);
              return result(MessageSyncStatus.unsupported, failure);
            }
            // Mốc không còn hợp lệ (máy chủ báo sai mốc): đồng bộ lại từ đầu.
            if (failure.kind == FailureKind.validation && !restarted) {
              restarted = true;
              final failed = await _restart(workspaceId, channelId, initialize);
              if (failed != null) return failed;
              cursor = (await _local.readSyncState(
                workspaceId: workspaceId,
                channelId: channelId,
              ))?.changeCursor;
              pages = 0;
              continue;
            }
            return result(MessageSyncStatus.failed, failure);
          case Success<MessageChangesPage>(value: final page):
            pages++;
            final applied = await _applyChanges(workspaceId, channelId, page);
            for (final message in applied.upserted) {
              deleted.remove(message.id);
              upserted[message.id] = message;
            }
            for (final message in applied.deleted) {
              upserted.remove(message.id);
              deleted[message.id] = message;
            }
            if (page.clearedAt case final at?) {
              final previous = clearedAt;
              clearedAt = previous == null || at.isAfter(previous)
                  ? at
                  : previous;
            }
            cursor = page.nextCursor;
            if (!page.hasMore) {
              return result(MessageSyncStatus.synced);
            }
        }
      }
      return result(MessageSyncStatus.synced);
    } on Object catch (error) {
      return result(MessageSyncStatus.failed, _storageFailure(error));
    }
  }

  Future<MessageSyncResult?> _restart(
    String workspaceId,
    String channelId,
    Future<MessageSyncResult?> Function() initialize,
  ) async {
    await _withLock(
      _key(workspaceId, channelId),
      () => _local.clearChannel(workspaceId: workspaceId, channelId: channelId),
    );
    return initialize();
  }

  /// Lấy mốc "từ bây giờ" của luồng thay đổi TRƯỚC, rồi tải trang tin mới
  /// nhất và lưu làm đoạn liền mạch đầu tiên.
  Future<_InitResult> _initialize(String workspaceId, String channelId) async {
    final start = await _changes.listMessageChanges(
      workspaceId: workspaceId,
      channelId: channelId,
      limit: changesPageLimit,
    );
    final String cursor;
    switch (start) {
      case FailureResult<MessageChangesPage>(:final failure):
        return _InitFailure(failure);
      case Success<MessageChangesPage>(value: final page):
        cursor = page.nextCursor;
    }
    final latest = await _messages.listMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      limit: pageSize,
    );
    final MessagePage page;
    switch (latest) {
      case FailureResult<MessagePage>(:final failure):
        return _InitFailure(failure);
      case Success<MessagePage>(:final value):
        page = value;
    }
    final oldest = _oldestOf(page.messages);
    await _withLock(_key(workspaceId, channelId), () async {
      await _local.clearChannel(workspaceId: workspaceId, channelId: channelId);
      await _local.upsert(
        workspaceId: workspaceId,
        channelId: channelId,
        messages: page.messages,
      );
      await _local.writeSyncState(
        ChannelSyncState(
          workspaceId: workspaceId,
          channelId: channelId,
          changeCursor: cursor,
          oldestMessageId: oldest?.id,
          oldestCreatedAt: oldest?.createdAt.toUtc(),
          reachedBeginning: !page.hasMore,
          syncedAt: _now(),
        ),
      );
    });
    return _InitDone(page.messages);
  }

  /// Áp một trang thay đổi: bia mộ → xoá; tin khác → ghi nếu nằm trong đoạn
  /// liền mạch; `cleared_at` → bỏ tin cũ; lưu mốc mới. Cả bước trong khoá của
  /// cuộc trò chuyện để không ghi đè trạng thái do tải tin cũ vừa ghi.
  Future<_Applied> _applyChanges(
    String workspaceId,
    String channelId,
    MessageChangesPage page,
  ) {
    return _withLock(_key(workspaceId, channelId), () async {
      final state = await _local.readSyncState(
        workspaceId: workspaceId,
        channelId: channelId,
      );
      if (state == null || state.changeCursor == null) {
        return const _Applied([], []);
      }
      final clearedAt = page.clearedAt?.toUtc();
      final tombstones = [
        for (final message in page.messages)
          if (message.isDeleted) message,
      ];
      final fresh = [
        for (final message in page.messages)
          if (!message.isDeleted &&
              _inSegment(state, message) &&
              (clearedAt == null || message.createdAt.isAfter(clearedAt)))
            message,
      ];
      await _local.remove(
        workspaceId: workspaceId,
        channelId: channelId,
        messageIds: [for (final message in tombstones) message.id],
      );
      await _local.upsert(
        workspaceId: workspaceId,
        channelId: channelId,
        messages: fresh,
      );
      var next = state.copyWith(
        changeCursor: page.nextCursor,
        syncedAt: _now(),
      );
      if (clearedAt != null) {
        await _local.removeCreatedUpTo(
          workspaceId: workspaceId,
          channelId: channelId,
          clearedAt: clearedAt,
        );
        final oldest = state.oldestCreatedAt;
        if (oldest == null || !clearedAt.isBefore(oldest)) {
          // Mọi tin cũ hơn mốc xoá lịch sử đã bị bỏ, máy chủ cũng không trả
          // lại: đoạn trên máy đã là toàn bộ cuộc trò chuyện.
          next = next.copyWith(clearOldest: true, reachedBeginning: true);
        }
      }
      await _local.writeSyncState(next);
      return _Applied(fresh, tombstones);
    });
  }

  /// Tải trước (chạy ngầm sau khi mở cuộc trò chuyện) các trang cũ hơn tin cũ
  /// nhất đã lưu, tới khi tin cũ nhất cũ hơn [prefetchWindow] hoặc hết tin.
  /// Lỗi thì dừng; một cuộc trò chuyện chỉ một lượt cùng lúc.
  Future<void> prefetchHistory({
    required String workspaceId,
    required String channelId,
  }) {
    final key = _key(workspaceId, channelId);
    final running = _prefetches[key];
    if (running != null) return running;
    final future = _runPrefetch(workspaceId, channelId).whenComplete(() {
      _prefetches.remove(key);
    });
    _prefetches[key] = future;
    return future;
  }

  Future<void> _runPrefetch(String workspaceId, String channelId) async {
    try {
      final cutoff = _now().subtract(prefetchWindow);
      for (var page = 0; page < maxPrefetchPages; page++) {
        final state = await _local.readSyncState(
          workspaceId: workspaceId,
          channelId: channelId,
        );
        final oldestId = state?.oldestMessageId;
        final oldestAt = state?.oldestCreatedAt;
        if (state == null ||
            state.changeCursor == null ||
            state.reachedBeginning ||
            oldestId == null ||
            oldestAt == null ||
            oldestAt.isBefore(cutoff)) {
          return;
        }
        final result = await _messages.listMessagePage(
          workspaceId: workspaceId,
          channelId: channelId,
          limit: prefetchPageSize,
          beforeId: oldestId,
        );
        final value = result.valueOrNull;
        if (value == null) return;
        final extended = await _extendSegment(
          workspaceId,
          channelId,
          anchorCreatedAt: oldestAt,
          page: value,
        );
        if (!extended) return;
      }
    } on Object {
      // Tải trước chỉ là phụ: lỗi (mạng, ổ) thì để lần mở sau.
    }
  }

  /// Tin cũ hơn tin ([beforeCreatedAt], [beforeId]): đọc trên máy trước; hết
  /// đoạn đã lưu mà chưa tới đầu cuộc trò chuyện thì hỏi máy chủ trang trước
  /// tin cũ nhất, ghi vào máy và nối dài đoạn đã lưu (tin cũ hơn 30 ngày được
  /// lưu dần khi người dùng kéo lên).
  Future<Result<MessageWindow>> loadOlder({
    required String workspaceId,
    required String channelId,
    required DateTime beforeCreatedAt,
    required String beforeId,
    int limit = 50,
  }) async {
    var local = const <ChatMessage>[];
    ChannelSyncState? state;
    try {
      local = await _local.readBefore(
        workspaceId: workspaceId,
        channelId: channelId,
        beforeCreatedAt: beforeCreatedAt,
        beforeId: beforeId,
        limit: limit,
      );
      if (local.length >= limit) {
        return Success(MessageWindow(messages: local, hasMore: true));
      }
      state = await _local.readSyncState(
        workspaceId: workspaceId,
        channelId: channelId,
      );
    } on Object {
      local = const [];
      state = null;
    }
    final ready = state != null && state.changeCursor != null;
    if (ready && state.reachedBeginning) {
      return Success(MessageWindow(messages: local, hasMore: false));
    }
    final anchor = local.isEmpty ? null : local.first;
    final anchorId = anchor?.id ?? beforeId;
    final anchorAt = anchor?.createdAt ?? beforeCreatedAt;
    final remote = await _messages.listMessagePage(
      workspaceId: workspaceId,
      channelId: channelId,
      limit: limit,
      beforeId: anchorId,
    );
    switch (remote) {
      case FailureResult<MessagePage>(:final failure):
        // Đã có ít tin trên máy: hiện trước, lần kéo sau hỏi lại máy chủ.
        if (local.isNotEmpty) {
          return Success(MessageWindow(messages: local, hasMore: true));
        }
        return FailureResult(failure);
      case Success<MessagePage>(value: final page):
        if (ready) {
          try {
            await _extendSegment(
              workspaceId,
              channelId,
              anchorCreatedAt: anchorAt,
              page: page,
            );
          } on Object {
            // Ghi vào máy lỗi: vẫn hiện trang vừa tải.
          }
        }
        final byId = <String, ChatMessage>{
          for (final message in page.messages) message.id: message,
          for (final message in local) message.id: message,
        };
        final merged = byId.values.toList()..sort(_compareChronological);
        return Success(MessageWindow(messages: merged, hasMore: page.hasMore));
    }
  }

  /// Ghi trang tin cũ ngay trước tin mốc (thuộc đoạn đã lưu) và lùi mốc cũ
  /// nhất. Mốc không còn trong đoạn (đoạn vừa bị dựng lại) thì bỏ.
  Future<bool> _extendSegment(
    String workspaceId,
    String channelId, {
    required DateTime anchorCreatedAt,
    required MessagePage page,
  }) {
    return _withLock(_key(workspaceId, channelId), () async {
      final state = await _local.readSyncState(
        workspaceId: workspaceId,
        channelId: channelId,
      );
      final oldestAt = state?.oldestCreatedAt;
      if (state == null ||
          state.changeCursor == null ||
          oldestAt == null ||
          anchorCreatedAt.isBefore(oldestAt)) {
        return false;
      }
      await _local.upsert(
        workspaceId: workspaceId,
        channelId: channelId,
        messages: page.messages,
      );
      final pageOldest = _oldestOf(page.messages);
      var next = state;
      final movesOldest =
          pageOldest != null && pageOldest.createdAt.isBefore(oldestAt);
      if (movesOldest) {
        next = next.copyWith(
          oldestMessageId: pageOldest.id,
          oldestCreatedAt: pageOldest.createdAt.toUtc(),
        );
      }
      if (!page.hasMore && (movesOldest || page.messages.isEmpty)) {
        next = next.copyWith(reachedBeginning: true);
      }
      await _local.writeSyncState(next);
      return true;
    });
  }

  /// Ghi tin nhận qua realtime / vừa gửi / sửa / thả cảm xúc. Chỉ ghi khi đã
  /// đồng bộ (có mốc) và tin nằm trong đoạn liền mạch; tin đã xoá thì xoá.
  Future<void> recordMessages({
    required String workspaceId,
    required String channelId,
    required List<ChatMessage> messages,
  }) async {
    if (messages.isEmpty) return;
    try {
      await _withLock(_key(workspaceId, channelId), () async {
        final state = await _local.readSyncState(
          workspaceId: workspaceId,
          channelId: channelId,
        );
        if (state == null || state.changeCursor == null) return;
        await _local.remove(
          workspaceId: workspaceId,
          channelId: channelId,
          messageIds: [
            for (final message in messages)
              if (message.isDeleted) message.id,
          ],
        );
        await _local.upsert(
          workspaceId: workspaceId,
          channelId: channelId,
          messages: [
            for (final message in messages)
              if (!message.isDeleted && _inSegment(state, message)) message,
          ],
        );
      });
    } on Object {
      // Ghi vào máy lỗi: lần đồng bộ sau bù lại.
    }
  }

  /// Xoá tin khỏi máy (đã xoá / thu hồi thành công, realtime báo xoá).
  Future<void> forgetMessages({
    required String workspaceId,
    required String channelId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    try {
      await _withLock(
        _key(workspaceId, channelId),
        () => _local.remove(
          workspaceId: workspaceId,
          channelId: channelId,
          messageIds: messageIds,
        ),
      );
    } on Object {
      // Như trên.
    }
  }

  /// Tìm trong tin đã lưu trên máy của cuộc trò chuyện (mới nhất trước).
  Future<List<ChatMessage>> searchLocal({
    required String workspaceId,
    required String channelId,
    required String query,
    int limit = 50,
  }) async {
    try {
      return await _local.search(
        workspaceId: workspaceId,
        channelId: channelId,
        query: query,
        limit: limit,
      );
    } on Object {
      return const [];
    }
  }

  /// Chạy [action] lần lượt theo từng cuộc trò chuyện (đọc - sửa - ghi trạng
  /// thái đồng bộ không giẫm lên nhau).
  Future<T> _withLock<T>(String key, Future<T> Function() action) {
    final previous = _locks[key] ?? Future<void>.value();
    final done = Completer<void>();
    final current = done.future;
    _locks[key] = current;
    return previous.then((_) => action()).whenComplete(() {
      done.complete();
      if (identical(_locks[key], current)) _locks.remove(key);
    });
  }
}

sealed class _InitResult {
  const _InitResult();
}

final class _InitFailure extends _InitResult {
  const _InitFailure(this.failure);

  final Failure failure;
}

final class _InitDone extends _InitResult {
  const _InitDone(this.page);

  final List<ChatMessage> page;
}

final class _Applied {
  const _Applied(this.upserted, this.deleted);

  final List<ChatMessage> upserted;
  final List<ChatMessage> deleted;
}

String _key(String workspaceId, String channelId) => '$workspaceId\n$channelId';

DateTime _utcNow() => DateTime.now().toUtc();

/// Tin nằm trong đoạn liền mạch đã lưu (không cũ hơn tin cũ nhất đã lưu).
/// Chưa có mốc cũ nhất (cuộc trò chuyện trống / đã tới đầu) thì mọi tin đều
/// thuộc đoạn.
bool _inSegment(ChannelSyncState state, ChatMessage message) {
  final oldest = state.oldestCreatedAt;
  return oldest == null || !message.createdAt.isBefore(oldest);
}

ChatMessage? _oldestOf(List<ChatMessage> messages) {
  ChatMessage? oldest;
  for (final message in messages) {
    if (oldest == null || _compareChronological(message, oldest) < 0) {
      oldest = message;
    }
  }
  return oldest;
}

int _compareChronological(ChatMessage left, ChatMessage right) {
  final byTime = left.createdAt.compareTo(right.createdAt);
  return byTime != 0 ? byTime : left.id.compareTo(right.id);
}

Failure _storageFailure(Object error) {
  return Failure(
    kind: FailureKind.storage,
    message: tr(
      'Không đọc / ghi được tin nhắn lưu trên máy.',
      "Couldn't read or write messages saved on this device.",
    ),
    code: 'LOCAL_MESSAGE_STORE',
    cause: error,
  );
}
