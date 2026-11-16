import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../design_system/components/webtui_components.dart';
import '../../../../design_system/icons/webtui_icons.dart';
import '../../../../design_system/tokens/webtui_colors.dart';
import '../../../../design_system/tokens/webtui_radii.dart';
import '../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../design_system/tokens/webtui_typography.dart';
import '../../../../l10n/app_strings.dart';
import '../../domain/entities/collaboration_document_version.dart';
import '../../domain/entities/collaboration_room.dart';
import '../../domain/entities/whiteboard_document.dart';
import '../controllers/collaboration_history_controller.dart';
import 'collaboration_whiteboard.dart' show WhiteboardPainter;

/// Mở lịch sử phiên bản ghi chú (`kind` = `notes`) hoặc bảng trắng
/// (`whiteboard`). Trả tài liệu sau khi khôi phục thành công (`null` nếu đóng).
/// [currentVersion] là version tài liệu client đang có (để máy chủ kiểm xung đột).
Future<CollaborationDocument?> showCollaborationHistorySheet(
  BuildContext context, {
  required String workspaceId,
  required String channelId,
  required String kind,
  required int currentVersion,
}) {
  return showModalBottomSheet<CollaborationDocument>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: WebTuiColors.surface,
    builder: (_) => CollaborationHistorySheet(
      scope: CollaborationHistoryScope(
        workspaceId: workspaceId,
        channelId: channelId,
        kind: kind,
      ),
      currentVersion: currentVersion,
    ),
  );
}

class CollaborationHistorySheet extends ConsumerWidget {
  const CollaborationHistorySheet({
    required this.scope,
    required this.currentVersion,
    super.key,
  });

  final CollaborationHistoryScope scope;
  final int currentVersion;

  bool get _isWhiteboard => scope.kind == 'whiteboard';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = collaborationHistoryControllerProvider(scope);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final previewing = state.selected != null || state.loadingVersion != null;
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTuiSpacing.xs,
                0,
                WebTuiSpacing.sm,
                WebTuiSpacing.xs,
              ),
              child: Row(
                children: [
                  if (previewing)
                    IconButton(
                      tooltip: tr('Về danh sách', 'Back to list'),
                      onPressed: controller.closePreview,
                      icon: const Icon(WebTuiIcons.back),
                    )
                  else
                    const SizedBox(width: WebTuiSpacing.md),
                  Expanded(
                    child: Text(
                      _isWhiteboard
                          ? tr('Lịch sử bảng trắng', 'Whiteboard history')
                          : tr('Lịch sử ghi chú', 'Notes history'),
                      style: WebTuiTypography.titleMedium.copyWith(
                        color: WebTuiColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Đóng', 'Close'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(WebTuiIcons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: WebTuiColors.border),
            Expanded(
              child: previewing
                  ? _Preview(
                      state: state,
                      isWhiteboard: _isWhiteboard,
                      currentVersion: currentVersion,
                      onRestore: () => _restore(context, ref),
                    )
                  : _VersionList(
                      state: state,
                      currentVersion: currentVersion,
                      onRetry: () => unawaited(controller.load()),
                      onSelect: (version) =>
                          unawaited(controller.select(version)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final provider = collaborationHistoryControllerProvider(scope);
    final selected = ref.read(provider).selected;
    if (selected == null) return;
    final confirmed = await showWebTuiConfirmDialog(
      context,
      title: tr(
        'Khôi phục bản v${selected.version}?',
        'Restore version v${selected.version}?',
      ),
      message: _isWhiteboard
          ? tr(
              'Bảng trắng sẽ trở về nội dung của bản này. Bản hiện tại vẫn '
                  'còn trong lịch sử.',
              'The whiteboard will go back to this version. The current '
                  'version stays in the history.',
            )
          : tr(
              'Ghi chú sẽ trở về nội dung của bản này. Bản hiện tại vẫn còn '
                  'trong lịch sử.',
              'The notes will go back to this version. The current version '
                  'stays in the history.',
            ),
      confirmLabel: tr('Khôi phục', 'Restore'),
      icon: WebTuiIcons.refresh,
    );
    if (!confirmed || !context.mounted) return;
    final restored = await ref
        .read(provider.notifier)
        .restoreSelected(expectedVersion: currentVersion);
    if (restored != null && context.mounted) {
      Navigator.of(context).pop(restored);
    }
  }
}

class _VersionList extends StatelessWidget {
  const _VersionList({
    required this.state,
    required this.currentVersion,
    required this.onRetry,
    required this.onSelect,
  });

  final CollaborationHistoryState state;
  final int currentVersion;
  final VoidCallback onRetry;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.versions.isEmpty) {
      return WebTuiLoadingState(
        message: tr('Đang tải lịch sử...', 'Loading history...'),
      );
    }
    if (state.errorMessage != null) {
      if (state.forbidden) {
        return WebTuiEmptyState(
          icon: Icons.lock_outline_rounded,
          title: tr('Không có quyền', 'No access'),
          message: tr(
            'Bạn không có quyền xem lịch sử của tài liệu này.',
            "You don't have permission to view this document's history.",
          ),
        );
      }
      return WebTuiErrorState(
        title: tr('Chưa tải được lịch sử', "Couldn't load history"),
        message: state.errorMessage!,
        onRetry: onRetry,
      );
    }
    if (state.versions.isEmpty) {
      return WebTuiEmptyState(
        icon: Icons.history_rounded,
        title: tr('Chưa có bản lưu nào', 'No saved versions yet'),
        message: tr(
          'Lịch sử sẽ có sau lần lưu tiếp theo.',
          'History will appear after the next save.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: WebTuiSpacing.sm),
      itemCount: state.versions.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, indent: 72, color: WebTuiColors.border),
      itemBuilder: (context, index) {
        final version = state.versions[index];
        return ListTile(
          key: ValueKey('history-version-${version.version}'),
          leading: CircleAvatar(
            backgroundColor: WebTuiColors.primarySoft,
            foregroundColor: WebTuiColors.primary,
            child: Text(
              'v${version.version}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          title: Text(formatHistoryTime(version.updatedAt)),
          subtitle: Text(_authorLine(version, currentVersion)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => onSelect(version.version),
        );
      },
    );
  }
}

String _authorLine(CollaborationDocumentVersion version, int currentVersion) {
  final author =
      version.authorName ?? tr('Không rõ người sửa', 'Unknown editor');
  return version.version == currentVersion
      ? tr('$author · Bản hiện tại', '$author · Current version')
      : author;
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.state,
    required this.isWhiteboard,
    required this.currentVersion,
    required this.onRestore,
  });

  final CollaborationHistoryState state;
  final bool isWhiteboard;
  final int currentVersion;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final selected = state.selected;
    if (selected == null) {
      if (state.previewError != null) {
        return WebTuiErrorState(
          title: tr('Chưa tải được bản này', "Couldn't load this version"),
          message: state.previewError!,
        );
      }
      return WebTuiLoadingState(
        message: tr('Đang tải bản xem trước...', 'Loading preview...'),
      );
    }
    final isCurrent = selected.version == currentVersion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.lg,
            WebTuiSpacing.md,
            WebTuiSpacing.lg,
            WebTuiSpacing.sm,
          ),
          child: Text(
            tr(
              'Bản v${selected.version} · ${formatHistoryTime(selected.updatedAt)}'
                  ' · ${selected.authorName ?? 'Không rõ người sửa'}',
              'Version v${selected.version} · ${formatHistoryTime(selected.updatedAt)}'
                  ' · ${selected.authorName ?? 'Unknown editor'}',
            ),
            style: WebTuiTypography.bodySmall.copyWith(
              color: WebTuiColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.lg),
            child: isWhiteboard
                ? _WhiteboardPreview(content: selected.content)
                : _NotesPreview(content: selected.content),
          ),
        ),
        if (state.restoreError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTuiSpacing.lg,
              WebTuiSpacing.sm,
              WebTuiSpacing.lg,
              0,
            ),
            child: Text(
              state.restoreError!,
              style: WebTuiTypography.bodySmall.copyWith(
                color: WebTuiColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(WebTuiSpacing.lg),
          child: FilledButton.icon(
            onPressed: isCurrent || state.restoring ? null : onRestore,
            icon: state.restoring
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore_rounded),
            label: Text(
              isCurrent
                  ? tr('Đang là bản hiện tại', 'This is the current version')
                  : tr('Khôi phục bản này', 'Restore this version'),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotesPreview extends StatelessWidget {
  const _NotesPreview({required this.content});

  final Map<String, Object?> content;

  @override
  Widget build(BuildContext context) {
    final text = content['text']?.toString() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: WebTuiColors.background,
        border: Border.all(color: WebTuiColors.border),
        borderRadius: BorderRadius.circular(WebTuiRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(WebTuiSpacing.md),
        child: text.trim().isEmpty
            ? Text(
                tr('Bản này trống.', 'This version is empty.'),
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textMuted,
                ),
              )
            : SelectableText(
                text,
                style: WebTuiTypography.bodySmall.copyWith(
                  color: WebTuiColors.textPrimary,
                  height: 1.45,
                ),
              ),
      ),
    );
  }
}

class _WhiteboardPreview extends StatelessWidget {
  const _WhiteboardPreview({required this.content});

  final Map<String, Object?> content;

  @override
  Widget build(BuildContext context) {
    final document = WhiteboardDocument.parse(content);
    return Semantics(
      label: tr(
        'Xem trước bảng trắng (chỉ đọc)',
        'Whiteboard preview (read-only)',
      ),
      child: AspectRatio(
        aspectRatio: whiteboardWidth / whiteboardHeight,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: WebTuiColors.border),
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WebTuiRadii.md),
            child: CustomPaint(
              key: const ValueKey('history-whiteboard-preview'),
              painter: WhiteboardPainter(
                document: document,
                textStyle:
                    Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `HH:mm dd/MM/yyyy` theo giờ máy.
String formatHistoryTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)} '
      '${two(local.day)}/${two(local.month)}/${local.year}';
}
