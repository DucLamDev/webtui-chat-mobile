import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../../conversations/domain/entities/chat_message.dart';
import '../controllers/my_notes_access_provider.dart';
import '../screens/my_notes_screen.dart';

/// Tin bí mật không được lưu vào My Note (máy chủ cũng chặn bằng
/// `SECRET_MESSAGE_RESTRICTED`). Entity tin chưa có trường riêng cho tin bí
/// mật nên đọc cờ trong metadata.
bool isSecretChatMessage(ChatMessage message) {
  if (message.isSecret) return true;
  bool flag(Object? value) =>
      value == true || value?.toString().trim().toLowerCase() == 'true';
  final metadata = message.metadata;
  return flag(metadata['secret']) ||
      flag(metadata['is_secret']) ||
      flag(metadata['isSecret']);
}

/// Mục "Lưu vào My Note" chỉ hiện khi máy chủ bật tính năng và tin đã gửi xong,
/// chưa bị xoá, không phải tin hệ thống / tin bí mật.
bool canSaveMessageToMyNote({
  required bool myNotesEnabled,
  required ChatMessage message,
}) {
  return myNotesEnabled &&
      !message.isDeleted &&
      !message.isSystem &&
      !message.isLocalOptimistic &&
      !message.id.startsWith('local-') &&
      !isSecretChatMessage(message);
}

/// Bản dùng trong menu nhấn giữ (widget không phải Consumer).
bool canSaveMessageToMyNoteIn(BuildContext context, ChatMessage message) {
  final enabled = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(myNotesEnabledProvider);
  return canSaveMessageToMyNote(myNotesEnabled: enabled, message: message);
}

/// Lưu tin vào My Note rồi báo kèm nút mở ghi chú.
Future<void> saveMessageToMyNote(
  BuildContext context, {
  required String workspaceId,
  required String channelId,
  required ChatMessage message,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final result = await container
      .read(myNotesUseCasesProvider)
      .saveMessage
      .execute(
        workspaceId: workspaceId,
        channelId: channelId.trim().isEmpty ? message.channelId : channelId,
        messageId: message.id,
      );
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  switch (result) {
    case Success(value: final saved):
      final location = myNoteLocation(
        workspaceId: workspaceId,
        noteId: saved.note.id,
      );
      final router = GoRouter.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              saved.created
                  ? 'Đã lưu vào My Note.'
                  : 'Tin nhắn này đã có trong My Note.',
            ),
            action: SnackBarAction(
              label: 'Mở ghi chú',
              onPressed: () => unawaited(router.push(location)),
            ),
          ),
        );
    case FailureResult(failure: final failure):
      final message = switch (failure.code) {
        'SECRET_MESSAGE_RESTRICTED' =>
          'Tin nhắn bí mật không lưu vào My Note được.',
        'CHANNEL_ACCESS_DENIED' =>
          'Bạn không còn ở trong cuộc trò chuyện này nên chưa lưu được tin.',
        'MESSAGE_NOT_FOUND' => 'Tin nhắn không còn tồn tại.',
        _ => myNotesErrorText(failure),
      };
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
  }
}
