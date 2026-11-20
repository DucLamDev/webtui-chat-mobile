import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/conversations/domain/entities/chat_message.dart';
import 'package:webtui_chat/features/conversations/presentation/controllers/message_sender_directory.dart';

ChatMessage _msg(String id, String? sender, DateTime at, {bool mine = false}) =>
    ChatMessage(
      id: id,
      workspaceId: 'w',
      channelId: 'c',
      kind: 'text',
      body: 'x',
      createdAt: at,
      senderId: sender,
      isMine: mine,
    );

ChannelMember _member(String id, String name) => ChannelMember(
  channelId: 'c',
  userId: id,
  email: '',
  username: '',
  displayName: name,
  status: 'active',
  joinedAt: DateTime.utc(2026),
);

void main() {
  final directory = MessageSenderDirectory.fromMembers([
    _member('a', 'An'),
    _member('b', 'Bình'),
  ]);
  final t0 = DateTime(2026, 11, 14, 10);

  test('tin đầu danh sách của người khác hiện tên', () {
    expect(
      senderNameToShow(
        message: _msg('1', 'a', t0),
        previous: null,
        directory: directory,
        isGroupChat: true,
      ),
      'An',
    );
  });

  test('tin của mình không hiện tên', () {
    expect(
      senderNameToShow(
        message: _msg('1', 'a', t0, mine: true),
        previous: null,
        directory: directory,
        isGroupChat: true,
      ),
      isNull,
    );
  });

  test(
    'cùng người trong 5 phút thì không lặp tên, quá 5 phút thì hiện lại',
    () {
      final first = _msg('1', 'a', t0);
      expect(
        senderNameToShow(
          message: _msg('2', 'a', t0.add(const Duration(minutes: 5))),
          previous: first,
          directory: directory,
          isGroupChat: true,
        ),
        isNull,
      );
      expect(
        senderNameToShow(
          message: _msg('3', 'a', t0.add(const Duration(minutes: 6))),
          previous: first,
          directory: directory,
          isGroupChat: true,
        ),
        'An',
      );
    },
  );

  test('đổi người gửi hoặc sang ngày mới thì hiện tên', () {
    final first = _msg('1', 'a', t0);
    expect(
      senderNameToShow(
        message: _msg('2', 'b', t0.add(const Duration(minutes: 1))),
        previous: first,
        directory: directory,
        isGroupChat: true,
      ),
      'Bình',
    );
    expect(
      startsSenderRun(
        _msg('1', 'a', DateTime(2026, 11, 14, 23, 59)),
        _msg('2', 'a', DateTime(2026, 11, 15, 0, 1)),
      ),
      isTrue,
    );
  });

  test('thiếu tên thì không hiện, không hiện mã người gửi', () {
    expect(
      senderNameToShow(
        message: _msg('1', 'zzz-id', t0),
        previous: null,
        directory: directory,
        isGroupChat: true,
      ),
      isNull,
    );
    expect(
      senderNameToShow(
        message: _msg('1', null, t0),
        previous: null,
        directory: directory,
        isGroupChat: true,
      ),
      isNull,
    );
  });

  test('chat 1-1 không hiện tên người gửi, kể cả tin đầu cụm', () {
    expect(
      senderNameToShow(
        message: _msg('1', 'a', t0),
        previous: null,
        directory: directory,
        isGroupChat: false,
      ),
      isNull,
    );
    expect(
      senderNameToShow(
        message: _msg('2', 'b', t0.add(const Duration(minutes: 1))),
        previous: _msg('1', 'a', t0),
        directory: directory,
        isGroupChat: false,
      ),
      isNull,
    );
  });

  group('endsSenderRun (tin cuối cụm)', () {
    test('không còn tin sau: là tin cuối', () {
      expect(endsSenderRun(_msg('1', 'a', t0), null), isTrue);
    });

    test('tin sau cùng người, cách đúng 5 phút: vẫn cùng cụm', () {
      expect(
        endsSenderRun(
          _msg('1', 'a', t0),
          _msg('2', 'a', t0.add(const Duration(minutes: 5))),
        ),
        isFalse,
      );
    });

    test('tin sau cách quá 5 phút: tin trước là tin cuối cụm', () {
      expect(
        endsSenderRun(
          _msg('1', 'a', t0),
          _msg('2', 'a', t0.add(const Duration(minutes: 5, seconds: 1))),
        ),
        isTrue,
      );
    });

    test('đổi người gửi: tin trước là tin cuối cụm', () {
      expect(
        endsSenderRun(
          _msg('1', 'a', t0),
          _msg('2', 'b', t0.add(const Duration(minutes: 1))),
        ),
        isTrue,
      );
    });

    test('sang ngày mới dù cách nhau vài phút: tin trước là tin cuối', () {
      final late = DateTime(2026, 11, 14, 23, 59);
      expect(
        endsSenderRun(
          _msg('1', 'a', late),
          _msg('2', 'a', late.add(const Duration(minutes: 2))),
        ),
        isTrue,
      );
    });

    test('tin hệ thống / sự kiện xen giữa cắt cụm', () {
      final system = ChatMessage(
        id: 's',
        workspaceId: 'w',
        channelId: 'c',
        kind: 'system',
        body: 'An đã tham gia',
        createdAt: t0.add(const Duration(minutes: 1)),
      );
      expect(endsSenderRun(_msg('1', 'a', t0), system), isTrue);
    });
  });
}
