import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_download_service.dart';

/// Ảnh giải mã tối đa 4096 điểm ảnh mỗi chiều (giữ tỉ lệ): ảnh nhỏ về dung
/// lượng nhưng cực lớn về kích thước (30000×30000) không làm app hết bộ nhớ.
ImageProvider ideBoundedImage(File file) => ResizeImage(
  FileImage(file),
  width: 4096,
  height: 4096,
  policy: ResizeImagePolicy.fit,
);

/// Xem ảnh đã tải toàn màn (phóng to / kéo), có nút lưu.
class IdeImageViewer extends ConsumerWidget {
  const IdeImageViewer({required this.file, super.key});

  final IdeDownloadedFile file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(file.name, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: tr('Đóng', 'Close'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: tr('Lưu ảnh', 'Save image'),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.save_alt_rounded),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final note = await ref
                  .read(ideDownloadServiceProvider)
                  .save(file);
              if (note != null) {
                messenger.showSnackBar(SnackBar(content: Text(note)));
              }
            },
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 6,
        child: Center(
          child: Image(
            image: ideBoundedImage(file.file),
            errorBuilder: (_, _, _) => Text(
              tr('Không mở được ảnh', 'Cannot open image'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
