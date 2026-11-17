import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_list_prefs.dart';
import 'package:webtui_chat/features/conversations/domain/entities/conversation_summary.dart';

void main() {
  final at = DateTime.utc(2026, 11, 17, 9);

  test('ghim trên máy ghi đè ghim của máy chủ, cả hai chiều', () {
    final plain = _item('a');
    final serverPinned = _item('b', favorite: true);
    var prefs = ConversationListPrefs.empty.withPinned('a', true);
    expect(prefs.apply(plain).favorite, isTrue);

    prefs = prefs.withPinned('b', false);
    expect(prefs.apply(serverPinned).favorite, isFalse);

    // Ghim lại sau khi bỏ: không còn nằm trong danh sách bỏ ghim.
    prefs = prefs.withPinned('b', true);
    expect(prefs.unpinned, isNot(contains('b')));
    expect(prefs.apply(serverPinned).favorite, isTrue);
  });

  test('đánh dấu chưa đọc: hiện số 1 khi đã đọc hết, giữ số thật nếu có', () {
    final prefs = ConversationListPrefs.empty
        .withMarkedUnread('a', true)
        .withMarkedUnread('b', true);
    expect(prefs.apply(_item('a')).unreadCount, 1);
    expect(prefs.apply(_item('b', unread: 5)).unreadCount, 5);
    expect(prefs.withMarkedUnread('a', false).apply(_item('a')).unreadCount, 0);
  });

  test('ẩn: tới khi có tin mới hơn lúc ẩn thì tự hiện lại', () {
    final item = _item('a', lastMessageAt: at);
    final prefs = ConversationListPrefs.empty.withHidden('a', at);
    expect(prefs.isHidden(item), isTrue);
    expect(
      prefs.isHidden(
        _item('a', lastMessageAt: at.add(const Duration(seconds: 1))),
      ),
      isFalse,
    );
    expect(prefs.withHidden('a', null).isHidden(item), isFalse);
    expect(prefs.isHidden(_item('khac')), isFalse);
  });

  test('ẩn thì bỏ đánh dấu chưa đọc; gỡ khỏi danh sách bỏ cả ghim', () {
    final hidden = ConversationListPrefs.empty
        .withMarkedUnread('a', true)
        .withHidden('a', at);
    expect(hidden.markedUnread, isEmpty);

    final removed = ConversationListPrefs.empty
        .withPinned('a', true)
        .withMarkedUnread('a', true)
        .removed('a', at);
    final item = _item('a', favorite: true, lastMessageAt: at);
    expect(removed.isHidden(item), isTrue);
    expect(removed.apply(item).favorite, isFalse);
    expect(removed.markedUnread, isEmpty);
  });

  test('lưu rồi đọc lại giữ nguyên; dữ liệu hỏng thì về rỗng', () {
    final prefs = ConversationListPrefs.empty
        .withPinned('a', true)
        .withPinned('b', false)
        .withMarkedUnread('c', true)
        .withHidden('d', at);
    final back = ConversationListPrefs.decode(prefs.encode());
    expect(back.pinned, {'a'});
    expect(back.unpinned, {'b'});
    expect(back.markedUnread, {'c'});
    expect(back.hiddenAt, {'d': at});

    for (final raw in [null, '', '{', '[]', '{"pinned": 3, "hidden": []}']) {
      expect(ConversationListPrefs.decode(raw).isEmpty, isTrue, reason: raw);
    }
    final mixed = ConversationListPrefs.decode(
      '{"pinned": ["x", 1, " ", " y "], "hidden": {"z": "khong-phai-ngay"}}',
    );
    expect(mixed.pinned, {'x', 'y'});
    expect(mixed.hiddenAt, isEmpty);
  });
}

ConversationSummary _item(
  String id, {
  bool favorite = false,
  int unread = 0,
  DateTime? lastMessageAt,
}) {
  return ConversationSummary(
    id: id,
    workspaceId: 'ws',
    channelId: id,
    kind: ConversationKind.direct,
    title: id,
    preview: '',
    updatedAt: DateTime.utc(2026, 11, 1),
    channelVisibility: ChannelVisibility.direct,
    favorite: favorite,
    unreadCount: unread,
    lastMessageAt: lastMessageAt,
  );
}
