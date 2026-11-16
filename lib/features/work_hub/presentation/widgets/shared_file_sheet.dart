import 'package:flutter/material.dart';
import 'package:webtui_chat/l10n/app_strings.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../domain/entities/work_hub.dart';
import '../controllers/shared_file_logic.dart';
import 'shared_file_widgets.dart';

/// Lựa chọn trong bảng thao tác của một tệp.
enum SharedFileSheetChoice { view, open, openExternally }

String sharedFileTypeLabel(SharedFile file) {
  return switch (sharedFileFormat(file)) {
    SharedFileFormat.pdf => tr('Tài liệu PDF', 'PDF document'),
    SharedFileFormat.word => tr('Tài liệu Word', 'Word document'),
    SharedFileFormat.excel => tr('Bảng tính Excel', 'Excel spreadsheet'),
    SharedFileFormat.powerpoint => tr('Bài trình chiếu', 'Presentation'),
    SharedFileFormat.other => switch (file.kind) {
      SharedFileKind.video => 'Video',
      SharedFileKind.image => tr('Ảnh', 'Photo'),
      SharedFileKind.audio => tr('Ghi âm', 'Voice message'),
      SharedFileKind.document => tr('Tệp', 'File'),
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
                title: tr('Xem', 'View'),
                subtitle: video
                    ? tr(
                        'Phát ngay, không cần tải hết',
                        'Plays right away, no need to download it all',
                      )
                    : null,
                onTap: () => pick(SharedFileSheetChoice.view),
              )
            else
              WebTuiSheetActionTile(
                key: const Key('file_action_open'),
                icon: WebTuiIcons.externalLink,
                title: file.kind == SharedFileKind.audio
                    ? tr('Mở bằng ứng dụng khác', 'Open in another app')
                    : tr('Mở', 'Open'),
                // Ghi âm chỉ vào bảng này khi máy không phát trực tiếp được
                // (WebM / Ogg trên iPhone).
                subtitle: file.kind == SharedFileKind.audio
                    ? tr(
                        'Máy này không phát trực tiếp được ghi âm định dạng này; mở bằng ứng dụng khác hoặc lưu về máy',
                        'This device can\'t play this voice message format directly; open it in another app or save it to your device',
                      )
                    : tr(
                        'Mở bằng ứng dụng có sẵn; từ đó lưu hoặc chia sẻ',
                        'Open in an installed app, then save or share from there',
                      ),
                onTap: () => pick(SharedFileSheetChoice.open),
              ),
            if (video || action == SharedFileTapAction.pdfSheet)
              WebTuiSheetActionTile(
                key: const Key('file_action_external'),
                icon: WebTuiIcons.externalLink,
                title: tr('Mở bằng ứng dụng khác', 'Open in another app'),
                subtitle: tr(
                  'Lưu vào máy, chia sẻ hoặc mở bằng ứng dụng khác',
                  'Save to device, share or open in another app',
                ),
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
