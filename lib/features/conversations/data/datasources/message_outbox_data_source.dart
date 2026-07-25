import 'dart:convert';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/message_outbox_item.dart';

final class MessageOutboxDataSource {
  const MessageOutboxDataSource(this._database);

  final AppDatabase _database;

  Future<List<MessageOutboxItem>> list({
    required String workspaceId,
    required String channelId,
  }) async {
    final value = await _database.readKeyValue(
      scope: _scope(workspaceId, channelId),
      key: 'items',
    );
    if (value == null) {
      return const [];
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        return const [];
      }
      final items = decoded['items'];
      if (items is! List) {
        return const [];
      }
      return items
          .whereType<Map<String, Object?>>()
          .map(_itemFromJson)
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> upsert(MessageOutboxItem item) async {
    final items = await list(
      workspaceId: item.workspaceId,
      channelId: item.channelId,
    );
    final next = [...items];
    final index = next.indexWhere((entry) => entry.id == item.id);
    if (index == -1) {
      next.add(item);
    } else {
      next[index] = item;
    }
    await _write(
      workspaceId: item.workspaceId,
      channelId: item.channelId,
      items: next,
    );
  }

  Future<void> delete({
    required String workspaceId,
    required String channelId,
    required String itemId,
  }) async {
    final items = await list(workspaceId: workspaceId, channelId: channelId);
    await _write(
      workspaceId: workspaceId,
      channelId: channelId,
      items: [
        for (final item in items)
          if (item.id != itemId) item,
      ],
    );
  }

  Future<void> clearChannel({
    required String workspaceId,
    required String channelId,
  }) {
    return _database.deleteScope(_scope(workspaceId, channelId));
  }

  Future<void> clearWorkspace({required String workspaceId}) {
    return _database.deleteScopesWithPrefix('message_outbox:$workspaceId:');
  }

  Future<void> _write({
    required String workspaceId,
    required String channelId,
    required List<MessageOutboxItem> items,
  }) {
    return _database.putKeyValue(
      scope: _scope(workspaceId, channelId),
      key: 'items',
      value: jsonEncode({
        'items': items.map(_itemToJson).toList(growable: false),
      }),
    );
  }
}

String _scope(String workspaceId, String channelId) {
  return 'message_outbox:$workspaceId:$channelId';
}

Map<String, Object?> _itemToJson(MessageOutboxItem item) {
  return {
    'id': item.id,
    'workspaceId': item.workspaceId,
    'channelId': item.channelId,
    'clientMessageId': item.clientMessageId,
    'body': item.body,
    'parentId': item.parentId,
    'attachments': item.attachments
        .map(_attachmentToJson)
        .toList(growable: false),
    'status': item.status.name,
    'attemptCount': item.attemptCount,
    'lastError': item.lastError,
    'createdAt': item.createdAt.toUtc().toIso8601String(),
    'updatedAt': item.updatedAt.toUtc().toIso8601String(),
  };
}

MessageOutboxItem _itemFromJson(Map<String, Object?> json) {
  final attachments = json['attachments'];
  return MessageOutboxItem(
    id: _string(json['id']),
    workspaceId: _string(json['workspaceId']),
    channelId: _string(json['channelId']),
    clientMessageId: _string(json['clientMessageId']),
    body: _string(json['body']),
    parentId: _nullableString(json['parentId']),
    attachments: attachments is List
        ? attachments
              .whereType<Map<String, Object?>>()
              .map(_attachmentFromJson)
              .toList(growable: false)
        : const [],
    status: _status(json['status']),
    attemptCount: _int(json['attemptCount']),
    lastError: _nullableString(json['lastError']),
    createdAt:
        _dateTime(json['createdAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    updatedAt:
        _dateTime(json['updatedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

Map<String, Object?> _attachmentToJson(MessageOutboxAttachment attachment) {
  return {
    'fileId': attachment.fileId,
    'name': attachment.name,
    'sortOrder': attachment.sortOrder,
  };
}

MessageOutboxAttachment _attachmentFromJson(Map<String, Object?> json) {
  return MessageOutboxAttachment(
    fileId: _string(json['fileId']),
    name: _string(json['name']),
    sortOrder: _int(json['sortOrder']),
  );
}

MessageOutboxStatus _status(Object? value) {
  final name = value?.toString();
  for (final status in MessageOutboxStatus.values) {
    if (status.name == name) {
      return status;
    }
  }
  return MessageOutboxStatus.queued;
}

String _string(Object? value, {String fallback = ''}) {
  return value is String ? value : fallback;
}

String? _nullableString(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

DateTime? _dateTime(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}
