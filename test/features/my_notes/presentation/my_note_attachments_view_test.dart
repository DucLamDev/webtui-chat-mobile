import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/features/my_notes/domain/entities/my_note.dart';
import 'package:webtui_chat/features/my_notes/presentation/widgets/my_note_attachment_picker.dart';
import 'package:webtui_chat/features/my_notes/presentation/widgets/my_note_attachments_view.dart';

void main() {
  MyNoteAttachment item(String id, String name, String mime, {int size = 1}) {
    return MyNoteAttachment(
      fileId: id,
      originalName: name,
      mimeType: mime,
      byteSize: size,
      createdAt: DateTime.utc(2026, 11, 16),
    );
  }

  final photoA = item('img-a', 'a.jpg', 'image/jpeg');
  final photoB = item('img-b', 'b.png', 'image/png');
  final pdf = item('doc-1', 'Báo cáo.pdf', 'application/pdf', size: 2048);

  Widget host(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 360, child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('không có gì để hiện thì không chiếm chỗ', (tester) async {
    await tester.pumpWidget(
      host(const MyNoteAttachmentsView(workspaceId: 'ws-1', attachments: [])),
    );
    expect(find.byKey(const Key('my_note_attachments_view')), findsNothing);
  });

  testWidgets('ảnh xếp lưới 2 cột, tệp thường là dòng tệp', (tester) async {
    await tester.pumpWidget(
      host(
        MyNoteAttachmentsView(
          workspaceId: 'ws-1',
          attachments: [photoA, pdf, photoB],
        ),
      ),
    );

    final cellA = find.byKey(const ValueKey('my_note_attachment_image_img-a'));
    final cellB = find.byKey(const ValueKey('my_note_attachment_image_img-b'));
    expect(cellA, findsOneWidget);
    expect(cellB, findsOneWidget);
    final sizeA = tester.getSize(cellA);
    expect(sizeA.width, closeTo((360 - 6) / 2, 0.01));
    expect(sizeA.height, sizeA.width);
    expect(tester.getTopLeft(cellA).dy, tester.getTopLeft(cellB).dy);
    expect(
      find.byKey(const ValueKey('my_note_attachment_file_doc-1')),
      findsOneWidget,
    );
    expect(find.text('Báo cáo.pdf'), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsOneWidget);
  });

  testWidgets('một ảnh thì hiện rộng cả hàng', (tester) async {
    await tester.pumpWidget(
      host(MyNoteAttachmentsView(workspaceId: 'ws-1', attachments: [photoA])),
    );
    final size = tester.getSize(
      find.byKey(const ValueKey('my_note_attachment_image_img-a')),
    );
    expect(size.width, 360);
    expect(size.height, 270);
  });

  testWidgets('uploadingCount hiện ô chờ có vòng tiến độ', (tester) async {
    await tester.pumpWidget(
      host(
        MyNoteAttachmentsView(
          workspaceId: 'ws-1',
          attachments: [photoA],
          uploadingCount: 2,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('my_note_attachment_uploading_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('my_note_attachment_uploading_1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('my_note_attachment_uploading_1')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  });

  testWidgets('bấm ảnh mở màn xem; Gỡ gọi onRemove sau khi xác nhận', (
    tester,
  ) async {
    final removed = <String>[];
    await tester.pumpWidget(
      host(
        MyNoteAttachmentsView(
          workspaceId: 'ws-1',
          attachments: [photoA, photoB],
          onRemove: (attachment) => removed.add(attachment.fileId),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('my_note_attachment_image_img-b')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MyNoteImageViewerScreen), findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsWidgets);

    // Huỷ ở hộp xác nhận thì không gỡ.
    await tester.tap(find.byKey(const Key('my_note_image_viewer_remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webtui_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(removed, isEmpty);

    await tester.tap(find.byKey(const Key('my_note_image_viewer_remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
    await tester.pumpAndSettle();
    expect(removed, ['img-b']);
    expect(find.byType(MyNoteImageViewerScreen), findsNothing);
  });

  testWidgets('nút Đóng thoát màn xem ảnh', (tester) async {
    await tester.pumpWidget(
      host(MyNoteAttachmentsView(workspaceId: 'ws-1', attachments: [photoA])),
    );
    await tester.tap(
      find.byKey(const ValueKey('my_note_attachment_image_img-a')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my_note_image_viewer_close')));
    await tester.pumpAndSettle();
    expect(find.byType(MyNoteImageViewerScreen), findsNothing);
  });

  testWidgets('nhấn giữ dòng tệp hỏi rồi gỡ', (tester) async {
    final removed = <String>[];
    await tester.pumpWidget(
      host(
        MyNoteAttachmentsView(
          workspaceId: 'ws-1',
          attachments: [pdf],
          onRemove: (attachment) => removed.add(attachment.fileId),
        ),
      ),
    );
    await tester.longPress(
      find.byKey(const ValueKey('my_note_attachment_file_doc-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('webtui_dialog_confirm')));
    await tester.pumpAndSettle();
    expect(removed, ['doc-1']);
  });

  testWidgets('readOnly: không có nút Gỡ, nhấn giữ không hỏi', (tester) async {
    await tester.pumpWidget(
      host(
        MyNoteAttachmentsView(
          workspaceId: 'ws-1',
          attachments: [photoA],
          readOnly: true,
          onRemove: (_) => fail('không được gỡ khi chỉ đọc'),
        ),
      ),
    );
    final cell = find.byKey(const ValueKey('my_note_attachment_image_img-a'));
    // Không có menu gỡ: nhấn giữ chỉ như bấm thường (mở màn xem).
    await tester.longPress(cell);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webtui_dialog_confirm')), findsNothing);
    expect(find.byType(MyNoteImageViewerScreen), findsOneWidget);
    expect(find.byKey(const Key('my_note_image_viewer_remove')), findsNothing);
    expect(find.text('Gỡ khỏi ghi chú'), findsNothing);
  });

  testWidgets('bảng chọn nguồn trả đúng nguồn đã bấm', (tester) async {
    MyNoteAttachSource? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                chosen = await showMyNoteAttachSourceSheet(context);
              },
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.text('Chụp ảnh'), findsOneWidget);
    expect(find.text('Chọn ảnh'), findsOneWidget);
    expect(find.text('Chọn tệp'), findsOneWidget);

    await tester.tap(find.byKey(const Key('my_note_attach_photos')));
    await tester.pumpAndSettle();
    expect(chosen, MyNoteAttachSource.photos);
  });
}
