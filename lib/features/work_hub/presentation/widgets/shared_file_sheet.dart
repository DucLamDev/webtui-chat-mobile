import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/shared_file_logic.dart';
import 'shared_file_widgets.dart';

/// Lựa chọn trong bảng thao tác của một tệp.
enum SharedFileSheetChoice { view, open, download, openExternally }

String sharedFileTypeLabel(SharedFile file) {
  return switch (sharedFileFormat(file)) {
    SharedFileFormat.pdf => 'Tài liệu PDF',
    SharedFileFormat.word => 'Tài liệu Word',
    SharedFileFormat.excel => 'Bảng tính Excel',
    SharedFileFormat.powerpoint => 'Bài trình chiếu',
    SharedFileFormat.other => switch (file.kind) {
      SharedFileKind.video => 'Video',
      SharedFileKind.image => 'Ảnh',
      SharedFileKind.audio => 'Ghi âm',
      SharedFileKind.document => 'Tệp',
    },
  };
}

/// Bảng thao tác cho video / PDF / Word / Excel / tệp khác. Video có ảnh bìa
/// lớn; trả lựa chọn hoặc null khi đóng.
Future<SharedFileSheetChoice?> showSharedFileActionSheet(
  BuildContext context, {
  required String workspaceId,
  required SharedFile file,
  required Uri apiBaseUri,
  required SharedFileTapAction action,
}) {
  return showWebTuiSheet<SharedFileSheetChoice>(
    context: context,
    builder: (sheetContext) {
      void pick(SharedFileSheetChoice choice) =>
          Navigator.of(sheetContext).pop(choice);
      final video = action == SharedFileTapAction.videoSheet;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (video)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    key: const Key('file_sheet_cover'),
                    height: 180,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Color(0xFF101318)),
                        LayoutBuilder(
                          builder: (context, box) => SharedFileCover(
                            workspaceId: workspaceId,
                            file: file,
                            apiBaseUri: apiBaseUri,
                            width: box.maxWidth,
                            height: 180,
                          ),
                        ),
                        Center(
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: Color(0x99000000),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              WebTuiIcons.play,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            WebTuiSheetHeader(
              title: shortenFileName(file.name, maxLength: 36),
              subtitle:
                  '${sharedFileTypeLabel(file)} · '
                  '${sharedFileSizeText(file.byteSize)}',
            ),
            if (video || action == SharedFileTapAction.pdfSheet)
              WebTuiSheetActionTile(
                key: const Key('file_action_view'),
                icon: video ? WebTuiIcons.play : WebTuiIcons.view,
                title: 'Xem',
                subtitle: video ? 'Phát ngay, không cần tải hết' : null,
                onTap: () => pick(SharedFileSheetChoice.view),
              )
            else
              WebTuiSheetActionTile(
                key: const Key('file_action_open'),
                icon: WebTuiIcons.externalLink,
                title: 'Mở',
                subtitle: 'Tải rồi mở bằng ứng dụng có sẵn',
                onTap: () => pick(SharedFileSheetChoice.open),
              ),
            WebTuiSheetActionTile(
              key: const Key('file_action_download'),
              icon: WebTuiIcons.download,
              title: 'Tải về',
              onTap: () => pick(SharedFileSheetChoice.download),
            ),
            if (video || action == SharedFileTapAction.pdfSheet)
              WebTuiSheetActionTile(
                key: const Key('file_action_external'),
                icon: WebTuiIcons.externalLink,
                title: 'Mở bằng ứng dụng khác',
                onTap: () => pick(SharedFileSheetChoice.openExternally),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Ảnh bìa lớn (video).
class SharedFileCover extends StatelessWidget {
  const SharedFileCover({
    required this.workspaceId,
    required this.file,
    required this.apiBaseUri,
    required this.width,
    required this.height,
    super.key,
  });

  final String workspaceId;
  final SharedFile file;
  final Uri apiBaseUri;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WebTuiColors.textPrimary,
      child: SharedFileCoverImage(
        workspaceId: workspaceId,
        file: file,
        apiBaseUri: apiBaseUri,
        width: width,
        height: height,
      ),
    );
  }
}
