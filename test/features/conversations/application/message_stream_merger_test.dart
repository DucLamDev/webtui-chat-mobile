import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/application/use_cases/message_stream_merger.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/domain/entities/rich_message.dart';

void main() {
  final message = ChatMessage(
    id: 'm',
    workspaceId: 'w',
    channelId: 'c',
    kind: 'bot',
    body: '…',
    createdAt: DateTime(2026),
    metadata: const {'streaming': true, 'stream_seq': 0},
  );
  MessageStreamDelta delta(int seq, String text) =>
      MessageStreamDelta(messageId: 'm', seq: seq, append: text);
  test('Ghép đúng thứ tự, bỏ trùng và chữ giữ chỗ', () {
    final result = mergeMessageStreamDeltas(message, [
      delta(2, ' bạn'),
      delta(1, 'Chào'),
      delta(1, 'sai'),
    ]);
    expect(result.message.body, 'Chào bạn');
    expect(result.message.streamSeq, 2);
    expect(result.hasGap, false);
  });
  test('Giữ đoạn thiếu thứ tự để tải lại', () {
    final result = mergeMessageStreamDeltas(message, [
      delta(3, '!'),
      delta(1, 'Chào'),
    ]);
    expect(result.message.body, 'Chào');
    expect(result.hasGap, true);
    final reloaded = result.message.copyWith(
      body: 'Chào bạn',
      metadata: const {'streaming': true, 'stream_seq': 2},
    );
    expect(
      mergeMessageStreamDeltas(reloaded, result.pending).message.body,
      'Chào bạn!',
    );
  });
  test('Tin đã xong hoặc bị xoá không nhận đoạn muộn', () {
    for (final closed in [
      message.copyWith(metadata: const {'streaming': false}),
      message.copyWith(deletedAt: DateTime(2026)),
    ]) {
      expect(
        mergeMessageStreamDeltas(closed, [delta(1, 'sai')]).changed,
        false,
      );
    }
  });
}
