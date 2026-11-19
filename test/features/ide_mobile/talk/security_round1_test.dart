import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_avatar_encoder.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_image_guard.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_profile_service.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_talk_controller.dart';
import 'package:webtui_chat/features/ide_mobile/application/ide_talk_service.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_errors.dart';
import 'package:webtui_chat/features/ide_mobile/domain/ide_talk_models.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/talk/ide_profile_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/talk/ide_talk_screen.dart';
import 'package:webtui_chat/features/ide_mobile/presentation/screens/tools/ide_tools_common.dart';

import '../support/more_env.dart';
import '../support/rpc_env.dart';
import 'talk_controller_test.dart' show Rig, full, msg, talkId;

int _crc(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}

/// PNG chỉ có IHDR (khai báo cỡ w × h) + IEND: đủ để đọc kích thước, không có
/// điểm ảnh thật.
Uint8List _headerOnlyPng(int w, int h) {
  List<int> chunk(String type, List<int> body) {
    final t = ascii.encode(type);
    final out = BytesBuilder()
      ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
      ..add(t)
      ..add(body)
      ..add(
        (ByteData(4)..setUint32(0, _crc([...t, ...body]))).buffer.asUint8List(),
      );
    return out.toBytes();
  }

  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ...chunk('IHDR', ihdr.buffer.asUint8List()),
    ...chunk('IDAT', zlib.encode([0, 0, 0, 0])),
    ...chunk('IEND', const []),
  ]);
}

Future<Uint8List> _png(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = Colors.green,
  );
  final img = await rec.endRecording().toImage(w, h);
  final d = await img.toByteData(format: ui.ImageByteFormat.png);
  return d!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ảnh: chặn bom giải nén', () {
    test('đọc được kích thước, ảnh hỏng thì null', () async {
      final size = await ideReadImageSize(await _png(30, 20));
      expect((size!.width, size.height), (30, 20));
      expect(await ideReadImageSize(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('cạnh > 8000 px: IdeAvatarTooLarge, không giải mã', () async {
      await expectLater(
        const DartUiAvatarEncoder().encode(_headerOnlyPng(9000, 10)),
        throwsA(isA<IdeAvatarTooLarge>()),
      );
    });

    test('> 40 MP dù mỗi cạnh ≤ 8000: IdeAvatarTooLarge', () async {
      await expectLater(
        const DartUiAvatarEncoder().encode(_headerOnlyPng(7000, 7000)),
        throwsA(isA<IdeAvatarTooLarge>()),
      );
    });

    test('ảnh lớn hợp lệ vẫn ra PNG 256 × 256', () async {
      final out = await const DartUiAvatarEncoder().encode(
        await _png(1600, 1200),
      );
      final bd = ByteData.sublistView(out);
      expect((bd.getUint32(16), bd.getUint32(20)), (256, 256));
    });

    test('ảnh đại diện từ IDE cạnh > 1024 thì không hiện', () async {
      final big = base64Encode(_headerOnlyPng(2000, 2000));
      final ok = base64Encode(await _png(64, 64));
      for (final (img, shown) in [(big, false), (ok, true)]) {
        final env = IdeRpcEnv(
          (op, a) => {'image': img, 'version': '1'},
          ops: ['profile.avatar_get'],
        );
        await env.up();
        final r = await IdeProfileService(env.rpc).avatarGet();
        expect(r != null, shown);
        await env.dispose();
      }
    });
  });

  group('đường dẫn từ IDE', () {
    test('ideTalkPathSafe', () {
      expect(ideTalkPathSafe('/home/a/b.txt'), isTrue);
      expect(ideTalkPathSafe('rel/a'), isFalse);
      expect(ideTalkPathSafe('/home/../etc/passwd'), isFalse);
      expect(ideTalkPathSafe('/home/a\nb'), isFalse);
      expect(ideTalkPathSafe('/home/a\u0000b'), isFalse);
    });

    Future<IdeTalkService> svc(Object? res) async {
      final env = IdeRpcEnv(
        (op, a) => res,
        ops: ['talk.upload_slot', 'talk.file'],
      );
      await env.up();
      addTearDown(env.dispose);
      return IdeTalkService(env.rpc);
    }

    Future<Object?> upload(String path) async {
      final s = await svc({'ref': 'r1', 'path': path});
      try {
        return await s.uploadAttachment(
          image: false,
          name: 'a.txt',
          mime: 'text/plain',
          size: 1,
          read: () => const Stream<List<int>>.empty(),
        );
      } on Object catch (e) {
        return e;
      }
    }

    test(
      'upload_slot: path ngoài .cache/vpsttt-ide/<người dùng>/(anh|tep)/ bị từ chối',
      () async {
        for (final p in [
          '/etc/cron.d/x',
          '/home/u/.cache/vpsttt-ide/u-an/tep/../../../x',
          '/home/u/.cache/vpsttt-ide/u-an/khac/x',
          '/home/u/.cache/vpsttt-ide/u-an/tep/a/b',
          '/home/u/.cache/vpsttt-ide/u-an/tep/a\nb',
          '/home/u/.cache/vpsttt-ide/../tep/x',
          '/home/u/.cache/vpsttt-ide/tep/x',
          'home/u/.cache/vpsttt-ide/u-an/tep/x',
        ]) {
          expect(await upload(p), isA<IdeError>(), reason: p);
        }
      },
    );

    test('ô tải lên đúng thư mục riêng của người dùng thì nhận', () {
      expect(
        ideTalkSlotPathOk('/home/dev/.cache/vpsttt-ide/u-an_1/anh/a.png'),
        isTrue,
      );
      expect(
        ideTalkSlotPathOk('/home/dev/.cache/vpsttt-ide/u-an/tep/Bao cao.pdf'),
        isTrue,
      );
      expect(
        ideTalkSlotPathOk('/home/dev/.cache/vpsttt-ide/anh/a.png'),
        isFalse,
      );
    });

    test('talk.file: path có .. bị từ chối', () async {
      final s = await svc({'path': '/home/u/../../etc/passwd', 'size': 1});
      await expectLater(s.file('a' * 32, 'a.txt'), throwsA(isA<IdeNotFound>()));
    });
  });

  group('mô hình cuộc chat', () {
    test('khung full: tin trùng id giữ tin sau', () {
      final f = IdeTalkFrame.parse(
        full([
          msg('1', 'user', 'a'),
          msg('2', 'assistant', 'b'),
          msg('1', 'user', 'a2'),
        ]),
      );
      final m = (f! as IdeTalkFull).conversation.messages;
      expect([for (final x in m) x.id], ['2', '1']);
      expect(m.last.text, 'a2');
    });

    test('delta mang talkId', () {
      final f = IdeTalkFrame.parse({
        'delta': true,
        'id': 'x',
        'message': msg('1', 'user', 'a'),
      });
      expect((f! as IdeTalkDelta).talkId, 'x');
    });
  });

  group('controller talk', () {
    Map<String, Object?> delta(String id, String mid) => {
      'type': 'talk_delta',
      'delta': true,
      'id': id,
      'message': msg(mid, 'assistant', 'x'),
    };

    test('delta của cuộc khác bị bỏ qua (không mở lại stream)', () async {
      final rig = Rig(idle: const Duration(hours: 1));
      rig.controller.start();
      await rig.wait();
      final s = rig.talkSockets.single;
      s.emit(full([msg('1', 'user', 'a'), msg('2', 'assistant', 'b')]));
      await rig.wait();
      s.emit(delta('b' * 32, '9'));
      await rig.wait();
      expect(rig.talkSockets.length, 1);
      expect(rig.controller.state.conversation!.messages.last.text, 'b');
      await rig.dispose();
    });

    test('delta mã tin lạ liên tục: giãn dần rồi failed', () async {
      final rig = Rig(
        idle: const Duration(hours: 1),
        deltaBase: const Duration(milliseconds: 10),
      );
      rig.controller.start();
      await rig.wait();
      int opens() => [
        for (final sk in rig.talkSockets)
          ...sk.sent.where((f) => f['type'] == 'talk'),
      ].length;
      var seen = 0;
      for (var i = 0; i < 120; i++) {
        final n = opens();
        final sk = rig.talkSockets.last;
        if (n > seen) {
          seen = n;
          sk.emit(full([msg('1', 'user', 'a')]));
        }
        sk.emit(delta(talkId, 'zz'));
        if (rig.controller.state.link == IdeTalkLink.failed) break;
        await rig.wait(25);
      }
      expect(
        rig.controller.state.link,
        IdeTalkLink.failed,
        reason: 'opens=${opens()}',
      );
      expect(opens(), lessThanOrEqualTo(6));
      await rig.dispose();
    });

    test('dispose trong lúc gửi: không ném lỗi khi đọc state', () async {
      final rig = Rig(idle: const Duration(hours: 1));
      rig.svc.hold = true;
      final f = rig.controller.send('chào');
      rig.controller.dispose();
      rig.svc.gate.complete();
      await f;
      await rig.connection.dispose();
    });

    test('kiểm cỡ mọi tệp trước khi tải cái đầu tiên', () async {
      final rig = Rig(idle: const Duration(hours: 1));
      IdeTalkAttachment a(bool image, int size) => IdeTalkAttachment(
        image: image,
        name: 'a',
        mime: 'x/y',
        size: size,
        read: () => Stream.value(Uint8List(1)),
      );
      await expectLater(
        rig.controller.send(
          'x',
          attachments: [a(true, 10), a(false, 60 * 1024 * 1024)],
        ),
        throwsA(isA<IdeTooLarge>()),
      );
      expect(rig.svc.uploads, 0);
      await rig.dispose();
    });
  });

  group('chữ lạ', () {
    test('ideTalkCleanText bỏ Cf / điều khiển', () {
      expect(ideTalkCleanText('a\u202Eb\u0007c'), 'ab c');
      expect(ideTalkCleanText('a\u202Eb\nc\td', keepLayout: true), 'ab\nc\td');
    });
  });

  testWidgets('chép bí mật: báo 60 giây, hết hạn xoá đúng giá trị đó', (
    t,
  ) async {
    String? clip;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return {'text': clip};
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await ideToolsCopySecret(ctx, 'mat-khau-bi-mat');
    await t.pump();
    expect(find.textContaining('tự xoá sau 60 giây'), findsOneWidget);
    expect(clip, 'mat-khau-bi-mat');
    await t.pump(const Duration(seconds: 61));
    expect(clip, '');

    // Người dùng đã chép thứ khác thì không đè.
    await ideToolsCopySecret(ctx, 'bi-mat-2');
    clip = 'thu-khac';
    await t.pump(const Duration(seconds: 61));
    expect(clip, 'thu-khac');
  });

  testWidgets('hồ sơ không có avatar_get: nút đổi ảnh không bị khoá', (
    t,
  ) async {
    final env = await pumpMore(
      t,
      const IdeProfileScreen(),
      (op, a) => op == 'profile.show'
          ? {'user': 'lam', 'full': 'Lâm', 'has_avatar': true}
          : const IdeFakeError('not_found'),
      ops: {'profile.show', 'profile.avatar_set'},
    );
    await settle(t);
    expect(env.calls, isNot(contains('profile.avatar_get')));
    final btn = t.widget<TextButton>(find.byKey(const Key('avatar_gallery')));
    expect(btn.onPressed, isNotNull);
  });
}
