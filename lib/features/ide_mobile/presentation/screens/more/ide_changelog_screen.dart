import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../design_system/components/webtui_components.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../domain/ide_insight_models.dart';
import '../../controllers/ide_more_controllers.dart';
import '../../widgets/ide_wb.dart';
import '../../widgets/markdown/ide_markdown.dart';
import 'ide_more_common.dart';

/// Changelog nền tảng (`changelog.read`): mỗi phiên bản một mục mở ra đọc.
class IdeChangelogScreen extends ConsumerWidget {
  const IdeChangelogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(ideMoreServiceProvider);
    return IdeMorePage(
      title: tr('Changelog nền tảng', 'Platform changelog'),
      body: IdeLoader<IdeChangelog>(
        load: service.changelog,
        builder: (context, log, reload) {
          if (log.items.isEmpty) {
            return WebTuiEmptyState(
              title: tr('Chưa có changelog', 'No changelog'),
              message: tr(
                'IDE chưa có nội dung thay đổi nào để hiện.',
                'The IDE has no changes to show yet.',
              ),
              icon: Icons.new_releases_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              key: const Key('ide_changelog_list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(WebTuiSpacing.lg),
              children: [
                if (log.version.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                    child: Text(
                      '${tr('Phiên bản hiện tại', 'Current version')}: ${log.version}',
                      style: IdeType.bodySmall.copyWith(color: IdeWb.text2),
                    ),
                  ),
                for (var i = 0; i < log.items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: WebTuiSpacing.sm),
                    child: _Entry(
                      item: log.items[i],
                      initiallyExpanded: i == 0,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.item, required this.initiallyExpanded});

  final IdeChangelogItem item;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IdeWb.bg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: IdeWb.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key('ide_changelog_${item.version}'),
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: WebTuiSpacing.md,
            vertical: 4,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            WebTuiSpacing.md,
            0,
            WebTuiSpacing.md,
            WebTuiSpacing.md,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            item.title.isEmpty ? item.version : item.title,
            style: IdeType.titleMedium.copyWith(color: IdeWb.textStrong),
          ),
          subtitle: Text(
            [item.version, if (item.date.isNotEmpty) item.date].join(' · '),
          ),
          children: [
            if (item.body.trim().isNotEmpty) IdeMarkdown(text: item.body),
          ],
        ),
      ),
    );
  }
}
