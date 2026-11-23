import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/design_system/components/webtui_avatar.dart';
import 'package:webtui_chat/features/approvals/data/datasources/approval_remote_data_source.dart';
import 'package:webtui_chat/features/approvals/domain/entities/approval.dart';
import 'package:webtui_chat/features/approvals/presentation/screens/approval_detail_screen.dart';
import 'package:webtui_chat/features/approvals/presentation/screens/approval_list_screen.dart';

const _display = <String, Object?>{
  'text': 'Dòng đầu của bài\n\nDòng thứ ba có #hashtag',
  'image_url': 'https://media.example.com/a.jpg',
  'fields': [
    {'label': 'Kênh', 'value': 'Facebook'},
    {'label': 'Tài khoản', 'value': 'Trang thử'},
    {'label': 'Giờ đăng', 'value': 'Ngay khi duyệt'},
  ],
  'link': {'label': 'Mở trang gốc', 'url': 'https://app.example.com/p/1'},
};

ApprovalRequest _approval([Map<String, Object?> extra = const {}]) {
  return approvalFromMap({
    'id': 'a1',
    'status': 'pending',
    'title': 'Duyệt bài · Khuyến mãi',
    'action': 'post.publish',
    'source': 'bot',
    'payload': {'post_id': 'p1'},
    'required_approvals': 1,
    'approvals_count': 0,
    'can_decide': true,
    ...extra,
  });
}

Widget _scope({
  required Widget child,
  required Future<Uint8List?> Function() load,
}) {
  return WebTuiAvatarNetworkScope(
    apiBaseUri: Uri.parse('https://chat.example'),
    cacheKey: 'test',
    loadBytes: (uri, {required maxBytes, required allowPublicRequest}) =>
        load(),
    child: child,
  );
}

Future<void> _pump(
  WidgetTester tester,
  ApprovalRequest approval, {
  Future<bool> Function(Uri uri)? onOpenLink,
  Future<Uint8List?> Function()? load,
}) {
  // Màn cao để cả khối nội dung lẫn phiếu đã bỏ đều được dựng.
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: _scope(
          load: load ?? () async => null,
          child: ApprovalDetailView(
            approval: approval,
            onOpenLink: onOpenLink ?? (_) async => true,
            onDecide: (_, _) async {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('đọc khối display', () {
    test('không có display thì như cũ', () {
      final approval = _approval();
      expect(approval.content, isNull);
      expect(approval.externalKey, isNull);
      expect(approval.cancelReason, isNull);
      expect(_approval({'display': null}).content, isNull);
      expect(_approval({'display': 'chuỗi lạ'}).content, isNull);
      expect(_approval({'display': <String, Object?>{}}).content, isNull);
    });

    test('đọc đủ chữ, ảnh, ô, liên kết và khoá ngoài', () {
      final approval = _approval({
        'display': _display,
        'external_key': 'post:p1:c1',
      });
      final content = approval.content!;
      expect(content.text, 'Dòng đầu của bài\n\nDòng thứ ba có #hashtag');
      expect(content.firstLine, 'Dòng đầu của bài');
      expect(content.imageUrl, 'https://media.example.com/a.jpg');
      expect(content.fields.map((f) => f.label), [
        'Kênh',
        'Tài khoản',
        'Giờ đăng',
      ]);
      expect(content.fields.first.value, 'Facebook');
      expect(content.link!.label, 'Mở trang gốc');
      expect(content.link!.uri, Uri.parse('https://app.example.com/p/1'));
      expect(approval.externalKey, 'post:p1:c1');
    });

    test('bỏ ảnh / liên kết không phải https và ô thiếu giá trị', () {
      final content = _approval({
        'display': {
          'text': 'Bài',
          'image_url': 'http://media.example.com/a.jpg',
          'fields': [
            {'label': 'Kênh', 'value': ''},
            {'label': '', 'value': 'x'},
            {'label': 'Số', 'value': 12},
            {'label': 'Tài khoản', 'value': 'Trang'},
          ],
          'link': {'label': 'Mở', 'url': 'javascript:alert(1)'},
        },
      }).content!;
      expect(content.imageUrl, isNull);
      expect(content.link, isNull);
      expect(content.fields, hasLength(1));
      expect(content.fields.single.label, 'Tài khoản');
    });

    test('giới hạn số ô và độ dài chữ', () {
      final content = approvalContentFromJson({
        'text': 'a' * (approvalContentMaxTextLength + 50),
        'fields': [
          for (var i = 0; i < 12; i++) {'label': 'Ô $i', 'value': 'v$i'},
        ],
      })!;
      expect(content.text.length, approvalContentMaxTextLength);
      expect(content.fields, hasLength(approvalContentMaxFields));
    });

    test('decisions có email + ghi chú; máy chủ cũ vẫn đọc được', () {
      final approval = _approval({
        'decisions': [
          {
            'user_id': 'u1',
            'user_email': 'nguoi.duyet@example.com',
            'decision': 'reject',
            'note': 'Sai giá',
            'decided_at': '2026-11-23T02:00:00Z',
          },
          {
            'user_id': 'u2',
            'decision': 'approve',
            'comment': 'ok',
            'created_at': '2026-11-23T03:00:00Z',
          },
        ],
      });
      final first = approval.decisions.first;
      expect(first.voterLabel, 'nguoi.duyet@example.com');
      expect(first.comment, 'Sai giá');
      expect(first.decision, ApprovalDecisionKind.reject);
      expect(first.createdAt, isNotNull);
      final second = approval.decisions.last;
      expect(second.voterLabel, 'u2');
      expect(second.comment, 'ok');
      expect(second.createdAt, isNotNull);
    });

    test('huỷ kèm lý do hiện trong nhãn trạng thái', () {
      final cancelled = _approval({
        'status': 'cancelled',
        'cancel_reason': 'Đã xử lý ở nơi khác',
      });
      expect(cancelled.cancelReason, 'Đã xử lý ở nơi khác');
      expect(cancelled.display.label, 'Đã huỷ');
      expect(cancelled.display.detail, 'Đã xử lý ở nơi khác');
      final fromResult = _approval({
        'status': 'cancelled',
        'result': {'cancel_reason': 'Lý do trong kết quả'},
      });
      expect(fromResult.display.detail, 'Lý do trong kết quả');
      expect(_approval({'status': 'cancelled'}).display.detail, isNull);
    });
  });

  group('màn chi tiết có khối nội dung', () {
    testWidgets('hiện chữ, ảnh, các ô, nút liên kết và ẩn dữ liệu dạng mã', (
      tester,
    ) async {
      Uri? opened;
      await _pump(
        tester,
        _approval({'display': _display}),
        onOpenLink: (uri) async {
          opened = uri;
          return true;
        },
      );
      await tester.pump();
      final text = tester.widget<SelectableText>(
        find.byKey(const Key('approval_content_text')),
      );
      expect(text.data, 'Dòng đầu của bài\n\nDòng thứ ba có #hashtag');
      expect(find.byKey(const Key('approval_content_image')), findsOneWidget);
      expect(find.text('Kênh'), findsOneWidget);
      expect(find.text('Facebook'), findsOneWidget);
      expect(find.text('Ngay khi duyệt'), findsOneWidget);
      expect(find.text('Nội dung'), findsNothing);
      expect(find.textContaining('post_id'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('approval_content_link')),
      );
      await tester.tap(find.byKey(const Key('approval_content_link')));
      await tester.pump();
      expect(opened, Uri.parse('https://app.example.com/p/1'));
    });

    testWidgets('không mở được liên kết thì báo', (tester) async {
      await _pump(
        tester,
        _approval({'display': _display}),
        onOpenLink: (_) async => false,
      );
      await tester.ensureVisible(
        find.byKey(const Key('approval_content_link')),
      );
      await tester.tap(find.byKey(const Key('approval_content_link')));
      await tester.pump();
      expect(find.text('Không mở được liên kết.'), findsOneWidget);
    });

    testWidgets('liên kết không phải https không có nút', (tester) async {
      await _pump(
        tester,
        _approval({
          'display': {
            'text': 'Bài',
            'link': {'label': 'Mở', 'url': 'http://app.example.com/p/1'},
          },
        }),
      );
      expect(find.byKey(const Key('approval_content_link')), findsNothing);
      expect(find.text('Mở'), findsNothing);
    });

    testWidgets('ảnh đang tải có ô chờ, tải lỗi hiện ô lỗi', (tester) async {
      final gate = Completer<Uint8List?>();
      await _pump(
        tester,
        _approval({'display': _display}),
        load: () => gate.future,
      );
      expect(
        find.byKey(const Key('approval_content_image_loading')),
        findsOneWidget,
      );
      gate.complete(null);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('approval_content_image_loading')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('approval_content_image_error')),
        findsOneWidget,
      );
      expect(find.text('Không tải được ảnh'), findsOneWidget);
    });

    testWidgets('bấm ảnh mở màn xem lớn, nút đóng quay lại', (tester) async {
      await _pump(tester, _approval({'display': _display}));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approval_content_image')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('approval_image_viewer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('approval_image_viewer_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('approval_image_viewer')), findsNothing);
    });

    testWidgets('không có display: vẫn hiện dữ liệu như cũ', (tester) async {
      await _pump(tester, _approval());
      expect(find.byKey(const Key('approval_content')), findsNothing);
      expect(find.text('Nội dung'), findsOneWidget);
      expect(find.textContaining('post_id'), findsOneWidget);
    });

    testWidgets('đã huỷ hiện lý do, không còn nút duyệt', (tester) async {
      await _pump(
        tester,
        _approval({
          'status': 'cancelled',
          'cancel_reason': 'Đã xử lý ở nơi khác',
          'display': _display,
        }),
      );
      expect(find.text('Đã huỷ: Đã xử lý ở nơi khác'), findsOneWidget);
      expect(find.byKey(const Key('approval_approve')), findsNothing);
    });

    testWidgets('đã đăng / đăng lỗi giữ nhãn kết quả', (tester) async {
      await _pump(
        tester,
        _approval({
          'status': 'failed',
          'result': {'error': 'Tài khoản hết hạn'},
          'display': _display,
        }),
      );
      expect(find.text('Thực hiện lỗi: Tài khoản hết hạn'), findsOneWidget);
      await _pump(
        tester,
        _approval({'status': 'executed', 'display': _display}),
      );
      expect(find.text('Đã thực hiện'), findsOneWidget);
    });

    testWidgets('phiếu đã bỏ hiện email người duyệt', (tester) async {
      await _pump(
        tester,
        _approval({
          'status': 'rejected',
          'display': _display,
          'decisions': [
            {
              'user_id': 'u1',
              'user_email': 'nguoi.duyet@example.com',
              'decision': 'reject',
              'note': 'Sai giá',
            },
          ],
        }),
      );
      await tester.ensureVisible(
        find.textContaining('nguoi.duyet@example.com'),
      );
      expect(
        find.textContaining('nguoi.duyet@example.com · Sai giá'),
        findsOneWidget,
      );
    });

    testWidgets('chữ to (1,6) không tràn', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: _scope(
              load: () async => null,
              child: ApprovalDetailView(
                approval: _approval({'display': _display}),
                onOpenLink: (_) async => true,
                onDecide: (_, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('nhãn kết quả', () {
    test('executed / failed có result_label thì dùng nhãn đó', () {
      final executed = _approval({
        'status': 'executed',
        'result_label': 'Đã đăng',
        'result': {'executor': 'none'},
      });
      expect(executed.resultLabel, 'Đã đăng');
      expect(executed.display.label, 'Đã đăng');
      expect(executed.display.tone, ApprovalStatusTone.success);
      final failed = _approval({
        'status': 'failed',
        'result_label': ' Đăng lỗi ',
        'result': {'error': 'Tài khoản hết hạn'},
      }).display;
      expect(failed.label, 'Đăng lỗi');
      expect(failed.detail, 'Tài khoản hết hạn');
      expect(failed.tone, ApprovalStatusTone.error);
    });

    test('không có / rỗng / trạng thái khác thì giữ nhãn cũ', () {
      expect(_approval({'status': 'executed'}).display.label, 'Đã thực hiện');
      expect(
        _approval({'status': 'executed', 'result_label': ''}).display.label,
        'Đã thực hiện',
      );
      expect(
        _approval({'status': 'failed', 'result_label': null}).display.label,
        'Thực hiện lỗi',
      );
      expect(
        _approval({
          'status': 'pending',
          'result_label': 'Đã đăng',
        }).display.label,
        'Đang chờ',
      );
      expect(
        _approval({
          'status': 'executed',
          'result_label': 'a' * 60,
        }).resultLabel!.length,
        40,
      );
    });

    testWidgets('chi tiết và danh sách hiện nhãn kết quả', (tester) async {
      await _pump(
        tester,
        _approval({
          'status': 'failed',
          'result_label': 'Đăng lỗi',
          'result': {'error': 'Tài khoản hết hạn'},
          'display': _display,
        }),
      );
      expect(find.text('Đăng lỗi: Tài khoản hết hạn'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalListTile(
              approval: _approval({
                'status': 'executed',
                'result_label': 'Đã đăng',
              }),
            ),
          ),
        ),
      );
      expect(find.text('Đã đăng'), findsOneWidget);
    });
  });

  group('dòng danh sách', () {
    testWidgets('có display: hiện dòng đầu của chữ', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalListTile(approval: _approval({'display': _display})),
          ),
        ),
      );
      final preview = tester.widget<Text>(
        find.byKey(const Key('approval_item_preview_a1')),
      );
      expect(preview.data, 'Dòng đầu của bài');
      expect(preview.maxLines, 1);
    });

    testWidgets('không có display: không có dòng tóm tắt', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ApprovalListTile(approval: _approval())),
        ),
      );
      expect(find.byKey(const Key('approval_item_preview_a1')), findsNothing);
      expect(find.text('Duyệt bài · Khuyến mãi'), findsOneWidget);
    });
  });
}
