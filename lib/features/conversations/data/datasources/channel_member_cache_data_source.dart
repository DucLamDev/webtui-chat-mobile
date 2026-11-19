import 'dart:convert';

import '../../../../core/database/app_database.dart';
import '../../../../core/security/instance_scope.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/conversation_local_cache.dart';

/// Lưu danh sách thành viên mỗi nhóm trong bảng key-value trên máy.
///
/// Dùng chung scope `conversation_cache:<workspace>` với danh sách hội thoại
/// (khoá `channel_members:<kênh>`), gắn tiền tố máy chủ
/// ([InstanceScope.localScope]): đăng xuất xoá theo tiền tố máy chủ, "Xoá bộ
/// nhớ đệm" của workspace xoá cả thành viên; hai máy chủ trùng mã workspace /
/// kênh không đọc lẫn của nhau.
final class ChannelMemberCacheDataSource implements ChannelMemberCache {
  ChannelMemberCacheDataSource(this._database, this._instanceScope);

  final AppDatabase _database;
  final InstanceScope _instanceScope;

  /// Ghi tuần tự: "đọc - sửa - ghi" của [upsertMember] không đè lần lưu cả
  /// danh sách chạy cùng lúc.
  Future<void> _pending = Future<void>.value();

  @override
  Future<List<ChannelMember>?> readMembers({
    required String workspaceId,
    required String channelId,
  }) async {
    final location = _location(workspaceId, channelId);
    if (location == null) return null;
    final value = await _database.readKeyValue(
      scope: location.scope,
      key: location.key,
    );
    return _decode(value);
  }

  @override
  Future<void> saveMembers({
    required String workspaceId,
    required String channelId,
    required List<ChannelMember> members,
  }) {
    final location = _location(workspaceId, channelId);
    if (location == null) return Future<void>.value();
    return _serial(() => _write(location, members));
  }

  @override
  Future<void> upsertMember({
    required String workspaceId,
    required String channelId,
    required ChannelMember member,
  }) {
    final location = _location(workspaceId, channelId);
    if (location == null) return Future<void>.value();
    return _serial(() async {
      final current = _decode(
        await _database.readKeyValue(scope: location.scope, key: location.key),
      );
      if (current == null) return;
      final next = [
        for (final item in current)
          if (item.userId != member.userId) item,
        member,
      ];
      await _write(location, next);
    });
  }

  @override
  Future<void> removeMembers({
    required String workspaceId,
    required String channelId,
  }) {
    final location = _location(workspaceId, channelId);
    if (location == null) return Future<void>.value();
    return _serial(
      () => _database.deleteKeyValue(scope: location.scope, key: location.key),
    );
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    // Lỗi của một lần ghi không chặn các lần sau; bên gọi vẫn nhận lỗi.
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write(
    ({String scope, String key}) location,
    List<ChannelMember> members,
  ) {
    return _database.putKeyValue(
      scope: location.scope,
      key: location.key,
      value: jsonEncode({
        'items': members.map(_memberToJson).toList(growable: false),
      }),
    );
  }

  ({String scope, String key})? _location(
    String workspaceId,
    String channelId,
  ) {
    final workspace = workspaceId.trim();
    final channel = channelId.trim();
    if (workspace.isEmpty || channel.isEmpty) return null;
    return (
      scope: _instanceScope.localScope('conversation_cache:$workspace'),
      key: 'channel_members:$channel',
    );
  }
}

List<ChannelMember>? _decode(String? value) {
  if (value == null) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) return null;
    final items = decoded['items'];
    if (items is! List) return null;
    return items
        .whereType<Map<String, Object?>>()
        .map(_memberFromJson)
        .whereType<ChannelMember>()
        .toList(growable: false);
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

Map<String, Object?> _memberToJson(ChannelMember member) {
  return {
    'channel_id': member.channelId,
    'user_id': member.userId,
    'email': member.email,
    'username': member.username,
    'display_name': member.displayName,
    'status': member.status,
    'joined_at': member.joinedAt.toUtc().toIso8601String(),
    'avatar_url': member.avatarUrl,
    'gender': member.gender,
    'last_read_message_id': member.lastReadMessageId,
    'last_read_at': member.lastReadAt?.toUtc().toIso8601String(),
  };
}

ChannelMember? _memberFromJson(Map<String, Object?> json) {
  final userId = json['user_id'];
  final joinedAt = DateTime.tryParse(json['joined_at']?.toString() ?? '');
  if (userId is! String || userId.isEmpty || joinedAt == null) return null;
  String text(String key) => json[key]?.toString() ?? '';
  String? optional(String key) {
    final value = json[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  return ChannelMember(
    channelId: text('channel_id'),
    userId: userId,
    email: text('email'),
    username: text('username'),
    displayName: text('display_name'),
    status: text('status'),
    joinedAt: joinedAt,
    avatarUrl: optional('avatar_url'),
    gender: optional('gender'),
    lastReadMessageId: optional('last_read_message_id'),
    lastReadAt: DateTime.tryParse(json['last_read_at']?.toString() ?? ''),
  );
}
