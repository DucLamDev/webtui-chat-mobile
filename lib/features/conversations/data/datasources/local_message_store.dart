import 'dart:convert';

import '../../../../core/database/app_database.dart';
import '../../../../core/security/instance_scope.dart';
import '../../../../core/text/search_text.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_sync.dart';
import '../../domain/repositories/local_message_repository.dart';
import 'conversation_cache_data_source.dart';

/// Kho tin nhắn lưu trên máy (bảng `local_messages` / `local_channel_sync`).
///
/// Mọi dòng nằm trong vùng `instanceScope.localScope('message_store')` của
/// máy chủ đang đăng nhập: đăng xuất xoá theo tiền tố máy chủ là sạch.
/// `payload` dùng chung cách đọc / ghi JSON của bộ đệm trang tin.
final class LocalMessageStore implements LocalMessageRepository {
  LocalMessageStore(this._database, InstanceScope instanceScope)
    : _scope = instanceScope.localScope('message_store');

  final AppDatabase _database;
  final String _scope;

  @override
  Future<List<ChatMessage>> readLatest({
    required String workspaceId,
    required String channelId,
    int limit = 50,
  }) async {
    if (limit <= 0) return const [];
    final rows = await _database.select(
      'SELECT payload FROM $localMessagesTable '
      'WHERE scope = ? AND workspace_id = ? AND channel_id = ? '
      'ORDER BY created_at_us DESC, id DESC LIMIT ?',
      [_scope, workspaceId, channelId, limit],
    );
    return _decodeRows(rows).reversed.toList(growable: false);
  }

  @override
  Future<List<ChatMessage>> readBefore({
    required String workspaceId,
    required String channelId,
    required DateTime beforeCreatedAt,
    required String beforeId,
    int limit = 50,
  }) async {
    if (limit <= 0) return const [];
    final beforeUs = beforeCreatedAt.toUtc().microsecondsSinceEpoch;
    final rows = await _database.select(
      'SELECT payload FROM $localMessagesTable '
      'WHERE scope = ? AND workspace_id = ? AND channel_id = ? '
      'AND (created_at_us < ? OR (created_at_us = ? AND id < ?)) '
      'ORDER BY created_at_us DESC, id DESC LIMIT ?',
      [_scope, workspaceId, channelId, beforeUs, beforeUs, beforeId, limit],
    );
    return _decodeRows(rows).reversed.toList(growable: false);
  }

  @override
  Future<void> upsert({
    required String workspaceId,
    required String channelId,
    required List<ChatMessage> messages,
  }) async {
    if (messages.isEmpty) return;
    // Cả lô trong MỘT giao dịch: nhanh hơn nhiều lần ghi lẻ và không để nửa
    // trang trên máy khi lỗi giữa chừng.
    await _database.transaction((sql) async {
      for (final message in messages) {
        if (message.isDeleted) {
          await sql.execute(
            'DELETE FROM $localMessagesTable '
            'WHERE scope = ? AND workspace_id = ? AND channel_id = ? AND id = ?',
            [_scope, workspaceId, channelId, message.id],
          );
          continue;
        }
        if (!_storable(message)) continue;
        final createdUs = message.createdAt.toUtc().microsecondsSinceEpoch;
        final updatedUs =
            (message.updatedAt ?? message.editedAt ?? message.createdAt)
                .toUtc()
                .microsecondsSinceEpoch;
        await sql.execute(
          'INSERT OR REPLACE INTO $localMessagesTable '
          '(scope, workspace_id, channel_id, id, created_at_us, updated_at_us, '
          'search_text, payload) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            _scope,
            workspaceId,
            channelId,
            message.id,
            createdUs,
            updatedUs,
            _searchTextOf(message),
            jsonEncode(chatMessageToCacheJson(message)),
          ],
        );
      }
    });
  }

  @override
  Future<void> remove({
    required String workspaceId,
    required String channelId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    await _database.transaction((sql) async {
      for (final id in messageIds.toSet()) {
        await sql.execute(
          'DELETE FROM $localMessagesTable '
          'WHERE scope = ? AND workspace_id = ? AND channel_id = ? AND id = ?',
          [_scope, workspaceId, channelId, id],
        );
      }
    });
  }

  @override
  Future<void> removeCreatedUpTo({
    required String workspaceId,
    required String channelId,
    required DateTime clearedAt,
  }) {
    return _database.execute(
      'DELETE FROM $localMessagesTable '
      'WHERE scope = ? AND workspace_id = ? AND channel_id = ? '
      'AND created_at_us <= ?',
      [
        _scope,
        workspaceId,
        channelId,
        clearedAt.toUtc().microsecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<ChannelSyncState?> readSyncState({
    required String workspaceId,
    required String channelId,
  }) async {
    final rows = await _database.select(
      'SELECT change_cursor, oldest_message_id, oldest_created_at_us, '
      'reached_beginning, synced_at_us FROM $localChannelSyncTable '
      'WHERE scope = ? AND workspace_id = ? AND channel_id = ?',
      [_scope, workspaceId, channelId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ChannelSyncState(
      workspaceId: workspaceId,
      channelId: channelId,
      changeCursor: _nonEmpty(row['change_cursor']),
      oldestMessageId: _nonEmpty(row['oldest_message_id']),
      oldestCreatedAt: _microsToDate(row['oldest_created_at_us']),
      reachedBeginning: row['reached_beginning'] == 1,
      syncedAt: _microsToDate(row['synced_at_us']),
    );
  }

  @override
  Future<void> writeSyncState(ChannelSyncState state) {
    return _database.execute(
      'INSERT OR REPLACE INTO $localChannelSyncTable '
      '(scope, workspace_id, channel_id, change_cursor, oldest_message_id, '
      'oldest_created_at_us, reached_beginning, synced_at_us) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _scope,
        state.workspaceId,
        state.channelId,
        state.changeCursor,
        state.oldestMessageId,
        state.oldestCreatedAt?.toUtc().microsecondsSinceEpoch,
        state.reachedBeginning ? 1 : 0,
        state.syncedAt?.toUtc().microsecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<List<ChatMessage>> search({
    required String workspaceId,
    required String channelId,
    required String query,
    int limit = 50,
  }) async {
    final tokens = searchTokens(query);
    if (tokens.isEmpty || limit <= 0) return const [];
    // Mỗi từ một điều kiện LIKE (đủ mọi từ, không cần đúng thứ tự); `%`, `_`
    // người dùng gõ được thoát để không thành ký tự đại diện.
    final conditions = List.filled(
      tokens.length,
      r"search_text LIKE ? ESCAPE '\'",
    ).join(' AND ');
    final rows = await _database.select(
      'SELECT payload FROM $localMessagesTable '
      'WHERE scope = ? AND workspace_id = ? AND channel_id = ? '
      'AND $conditions '
      'ORDER BY created_at_us DESC, id DESC LIMIT ?',
      [
        _scope,
        workspaceId,
        channelId,
        for (final token in tokens) '%${escapeLikePattern(token)}%',
        limit,
      ],
    );
    return _decodeRows(rows);
  }

  @override
  Future<void> clearChannel({
    required String workspaceId,
    required String channelId,
  }) async {
    await _database.transaction((sql) async {
      for (final table in const [localMessagesTable, localChannelSyncTable]) {
        await sql.execute(
          'DELETE FROM $table '
          'WHERE scope = ? AND workspace_id = ? AND channel_id = ?',
          [_scope, workspaceId, channelId],
        );
      }
    });
  }
}

/// Tin bí mật (nội dung chỉ xem khi xác thực lại), tin tạm `local-…` chưa gửi
/// xong và tin đang chạy dần (bản dở) không lưu.
bool _storable(ChatMessage message) {
  return !message.isSecret &&
      !message.id.startsWith('local-') &&
      message.id.isNotEmpty &&
      !message.isStreaming;
}

/// Chữ để tìm: nội dung + tên tệp đính kèm, đã chuẩn hoá.
String _searchTextOf(ChatMessage message) {
  final parts = [
    message.body,
    for (final attachment in message.attachments) attachment.file.name,
  ];
  return normalizeSearchText(parts.join(' '));
}

List<ChatMessage> _decodeRows(List<Map<String, Object?>> rows) {
  final messages = <ChatMessage>[];
  for (final row in rows) {
    final payload = row['payload'];
    if (payload is! String) continue;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, Object?>) {
        messages.add(chatMessageFromCacheJson(decoded));
      }
    } on FormatException {
      // Dòng hỏng: bỏ qua, lần đồng bộ sau ghi đè.
    } on TypeError {
      // Như trên.
    }
  }
  return messages;
}

String? _nonEmpty(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

DateTime? _microsToDate(Object? value) {
  if (value is! int) return null;
  return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
}
