import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../design_system/components/webtui_dialogs.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/my_note.dart';

/// Nguồn đính kèm khi bấm nút máy ảnh trên thanh công cụ ghi chú.
enum MyNoteAttachSource { camera, photos, files }

/// Chọn nhiều ảnh một lần tối đa bấy nhiêu ảnh.
const myNotePhotoPickLimit = 10;

/// Bảng chọn nguồn: Chụp ảnh / Chọn ảnh / Chọn tệp. Đóng bảng → `null`.
Future<MyNoteAttachSource?> showMyNoteAttachSourceSheet(BuildContext context) {
  return showWebTuiSheet<MyNoteAttachSource>(
    context: context,
    builder: (context) {
      void choose(MyNoteAttachSource source) =>
          Navigator.of(context).pop(source);
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WebTuiSheetHeader(title: tr('Thêm vào ghi chú', 'Add to note')),
            WebTuiSheetActionTile(
              key: const Key('my_note_attach_camera'),
              icon: WebTuiIcons.camera,
              title: tr('Chụp ảnh', 'Take photo'),
              onTap: () => choose(MyNoteAttachSource.camera),
            ),
            WebTuiSheetActionTile(
              key: const Key('my_note_attach_photos'),
              icon: WebTuiIcons.gallery,
              title: tr('Chọn ảnh', 'Choose photos'),
              subtitle: tr(
                'Tối đa $myNotePhotoPickLimit ảnh mỗi lần',
                'Up to $myNotePhotoPickLimit photos at a time',
              ),
              onTap: () => choose(MyNoteAttachSource.photos),
            ),
            WebTuiSheetActionTile(
              key: const Key('my_note_attach_files'),
              icon: WebTuiIcons.file,
              title: tr('Chọn tệp', 'Choose files'),
              subtitle: tr(
                'PDF, Word, Excel, ảnh...',
                'PDF, Word, Excel, photos...',
              ),
              onTap: () => choose(MyNoteAttachSource.files),
            ),
            const SizedBox(height: WebTuiSpacing.md),
          ],
        ),
      );
    },
  );
}

/// Mở camera / thư viện ảnh / bộ chọn tệp. Camera: 1 ảnh; ảnh: nhiều ảnh
/// (tối đa [myNotePhotoPickLimit]); tệp: nhiều tệp. Huỷ → danh sách rỗng.
/// Lỗi (thiếu quyền...) hiện thông báo rồi trả rỗng.
Future<List<MyNoteLocalFile>> pickMyNoteAttachments(
  BuildContext context,
  MyNoteAttachSource source, {
  ImagePicker? imagePicker,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final picker = imagePicker ?? ImagePicker();
    switch (source) {
      case MyNoteAttachSource.camera:
        final image = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 2560,
          maxHeight: 2560,
        );
        if (image == null) return const [];
        return [await _fromXFile(image)];
      case MyNoteAttachSource.photos:
        final images = await picker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 2560,
          maxHeight: 2560,
          limit: myNotePhotoPickLimit,
        );
        final files = <MyNoteLocalFile>[];
        // Một số máy không tôn trọng `limit`: cắt bớt cho chắc.
        for (final image in images.take(myNotePhotoPickLimit)) {
          files.add(await _fromXFile(image));
        }
        return files;
      case MyNoteAttachSource.files:
        final result = await FilePicker.pickFiles(allowMultiple: true);
        return [
          for (final picked in result?.files ?? const <PlatformFile>[])
            if ((picked.path ?? '').trim().isNotEmpty)
              MyNoteLocalFile(
                path: picked.path!,
                name: picked.name,
                mimeType: myNoteMimeTypeForName(picked.name),
                byteSize: picked.size,
              ),
        ];
    }
  } on Object {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          source == MyNoteAttachSource.files
              ? tr(
                  'Không mở được bộ chọn tệp. Vui lòng thử lại.',
                  'Couldn\'t open the file picker. Please try again.',
                )
              : tr(
                  'Không mở được camera / thư viện ảnh. Kiểm tra quyền trong Cài đặt rồi thử lại.',
                  'Couldn\'t open the camera / photo library. Check permissions in Settings and try again.',
                ),
        ),
      ),
    );
    return const [];
  }
}

Future<MyNoteLocalFile> _fromXFile(XFile image) async {
  final name = image.name.trim().isNotEmpty
      ? image.name.trim()
      : 'anh_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final mime = image.mimeType?.trim();
  return MyNoteLocalFile(
    path: image.path,
    name: name,
    mimeType: mime == null || mime.isEmpty ? myNoteMimeTypeForName(name) : mime,
    byteSize: await image.length(),
  );
}
