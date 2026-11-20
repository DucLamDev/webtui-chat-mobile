import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_download_service.dart';
import 'ide_files_ui.dart';

/// Tải [path] về tệp tạm, có hộp tiến độ + nút huỷ. Trả `null` khi huỷ hoặc
/// lỗi (đã báo bằng thanh thông báo).
Future<IdeDownloadedFile?> ideDownloadWithProgress(
  BuildContext context,
  WidgetRef ref,
  String path, {
  String? name,
}) async {
  final service = ref.read(ideDownloadServiceProvider);
  final dl = service.start(path, name: name);
  var open = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(download: dl),
    ).whenComplete(() => open = false),
  );
  try {
    final f = await dl.done;
    return f;
  } on IdeDownloadCancelled {
    return null;
  } on IdeDownloadTooLarge {
    if (context.mounted) {
      ideSnack(context, tr('Tệp quá lớn để tải.', 'The file is too large.'));
    }
    return null;
  } on Object catch (e) {
    if (context.mounted) ideSnack(context, ideFilesErrorText(e));
    return null;
  } finally {
    if (open && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

/// Tải về rồi lưu vào Tải về / chia sẻ; báo kết quả.
Future<void> ideDownloadAndSave(
  BuildContext context,
  WidgetRef ref,
  String path, {
  String? name,
}) async {
  final f = await ideDownloadWithProgress(context, ref, path, name: name);
  if (f == null || !context.mounted) return;
  final service = ref.read(ideDownloadServiceProvider);
  try {
    final note = await service.save(
      f,
      confirmOpen: () => showWebTuiConfirmDialog(
        context,
        title: tr('Mở tệp bằng ứng dụng khác?', 'Open with another app?'),
        message: tr(
          'Máy Android này chưa lưu thẳng vào Tải về được. Chỉ mở tệp bạn tin tưởng.',
          'This Android cannot save to Downloads directly. Only open files you trust.',
        ),
        confirmLabel: tr('Mở', 'Open'),
      ),
    );
    if (context.mounted && note != null) ideSnack(context, note);
  } on Object {
    if (context.mounted) {
      ideSnack(context, tr('Không lưu được tệp', 'Could not save the file'));
    }
  } finally {
    await service.discard(f);
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.download});

  final IdeDownload download;

  @override
  Widget build(BuildContext context) {
    return WebTuiDialog(
      title: tr('Đang tải về', 'Downloading'),
      icon: Icons.download_rounded,
      content: StreamBuilder<double?>(
        stream: download.progress.stream,
        initialData: download.progress.value,
        builder: (_, snap) => LinearProgressIndicator(value: snap.data),
      ),
      actions: [
        WebTuiDialogAction(
          key: const Key('ide_download_cancel'),
          label: tr('Huỷ', 'Cancel'),
          onPressed: () {
            download.cancel();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
